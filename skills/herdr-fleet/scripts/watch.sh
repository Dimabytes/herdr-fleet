#!/bin/zsh
# usage: R=<run dir> watch.sh <agent> [task#] [timeout_s]   (run in background)
# Waits for one task: the number prompt.sh printed, by default the agent's latest task when the watcher starts.
# A later task never satisfies or replaces this one, and a late finish of an older task does not either.
# DONE: finish.sh recorded this task (task.sh). It is checked first, so a watcher started after the agent finished,
#   restarted mid-run, or started after the pane closed still reports DONE.
# EXITED (command-code): the run ended with a non-zero code, or with code 0 and no finish.
# IDLE: agent not working, no busy marker on screen, task report unchanged IDLE_S (600) s -> nudge: prompt.sh --raw.
# Exits early on BLOCKED / GONE, or TIMEOUT. Blocks on `herdr agent wait`, so it wakes within ~10 s.
: ${R:?set R to the run dir}; R=${R:a}  # absolute: panes and command-code-run.sh resolve it from another cwd
E=$(${0:A:h}/session.py) || exit 1; eval "$E"  # this agent's own herdr session, pinned in $R/herdr.env
source ${0:A:h}/task.sh
zmodload -F zsh/stat b:zstat  # portable size (BSD and GNU stat flags differ)
N=$1; W=$R/work/$N; n=${2:-$(cat $W/run 2>/dev/null)}; T=${3:-5400}
[[ $n == <-> ]] || { echo "no task to watch for $N: send one with prompt.sh, or pass its number" >&2; exit 1; }
F=$(task_report $W $n); [ -n "$F" ] || { echo "no task #$n for $N in $R" >&2; exit 1; }
IDLE_S=${IDLE_S:-600}; POLL_S=${POLL_S:-5}  # test knobs; keep the defaults in real runs
# say <status line>: print it, and raise a herdr notification so the user sees it without watching the tab
say() { echo "$@"; herdr notification show "fleet $N #$n" --body "$*" --sound request >/dev/null 2>&1; }
CC=0; [ -f $W/kind ] && [ "$(cat $W/kind)" = command-code ] && CC=1
start=$(date +%s); last=-1; since=$start; gone=0
while true; do
  now=$(date +%s)
  s=$(task_state $W $n)
  case $s in
    done) say "DONE $N #$n $F"; exit 0;;
    exited:*) say "EXITED $N #$n ${s#exited:} (read $F; send a new task to continue)"; exit 0;;
  esac
  [ $((now-start)) -ge $T ] && { say "TIMEOUT $N #$n"; exit 0; }
  if [ $CC = 1 ]; then
    # headless command-code: herdr has no state for it; its run is over when exit-<n> appears
    herdr pane get "$(cat $W/pane 2>/dev/null)" >/dev/null 2>&1 || { say "GONE $N #$n (its pane closed mid-run)"; exit 0; }
    sleep $POLL_S; continue
  fi
  size=0; [ -f $F ] && { zstat -A st +size -- $F; size=$st[1]; }
  [ $size -ne $last ] && { last=$size; since=$now; }
  st=$(herdr agent get $N 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["result"]["agent"]["agent_status"])
except Exception: print("gone")')
  # one failed `agent get` is a hiccup, not a dead agent: GONE only after 3 in a row
  if [ "$st" = gone ]; then gone=$((gone+1)); [ $gone -ge 3 ] && { say "GONE $N #$n size=$size"; exit 0; }; sleep $POLL_S; continue; fi
  gone=0
  [ "$st" = blocked ] && { say "BLOCKED $N #$n"; exit 0; }
  if [ "$st" != working ]; then
    # herdr can report idle/done while the agent waits on a long shell command; trust its on-screen busy marker
    busy=0; herdr agent read $N --source visible --lines 30 2>/dev/null | grep -qE 'ctrl\+c to stop|esc to interrupt|while it works|command still running' && busy=1
    [ $busy = 0 ] && [ $((now-since)) -ge $IDLE_S ] && { say "IDLE $N #$n size=$size"; exit 0; }
    sleep $POLL_S  # wait returns at once on an idle agent; do not spin
  fi
  herdr agent wait $N --timeout 10000 >/dev/null 2>&1
done
