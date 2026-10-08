#!/bin/zsh
# usage: R=<run dir> watch.sh <agent> [report-basename] [timeout_s]   (run in background)
# Blocks on `herdr agent wait` (returns as soon as the agent stops working), then checks the report.
# DONE: report has a "Status: FINAL" line, changed after this watcher started, unchanged 15 s, agent not working.
# IDLE: agent not working and report unchanged 600 s without that -> nudge it (queued prompt? WIP report?).
# Exits early on BLOCKED / GONE, or TIMEOUT.
: ${R:?set R to the run dir}
zmodload -F zsh/stat b:zstat  # portable size/mtime (BSD and GNU stat flags differ)
N=$1; F=$R/reports/${2:-$1}.md; T=${3:-5400}
# say <status line>: print it, and raise a herdr notification so the user sees it without watching the tab
say() { echo "$@"; herdr notification show "fleet $N" --body "$*" --sound request >/dev/null 2>&1; }
final_ok() { [ "$(sed -n 2p $F 2>/dev/null)" = 'Status: FINAL' ]; }  # the contract: line 2
start=$(date +%s); last=-1; since=$start
if [ -f $R/work/$N/kind ] && [ "$(cat $R/work/$N/kind)" = command-code ]; then
  # headless command-code: herdr has no state for it; a run is over when its exit file appears
  while [ $(( $(date +%s) - start )) -lt $T ]; do
    run=$(cat $R/work/$N/run 2>/dev/null || echo 0)  # re-read: the watcher may start before the first prompt
    herdr pane get "$(cat $R/work/$N/pane 2>/dev/null)" >/dev/null 2>&1 || { say "GONE $N (its pane closed mid-run)"; exit 0; }
    if [ -f $R/work/$N/exit-$run ]; then
      code=$(cat $R/work/$N/exit-$run)
      [ "${code:-x}" = 0 ] && final_ok && { say "DONE $N exit=$code"; exit 0; }
      say "EXITED $N exit=$code (non-zero, or no Status: FINAL; check the report, then prompt.sh to continue)"; exit 0
    fi
    sleep 10
  done
  say "TIMEOUT $N"; exit 0
fi
gone=0
while true; do
  now=$(date +%s); size=0; mtime=0
  [ -f $F ] && { zstat -A st +size -- $F; size=$st[1]; zstat -A st +mtime -- $F; mtime=$st[1]; }
  [ $size -ne $last ] && { last=$size; since=$now; }
  st=$(herdr agent get $N 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["result"]["agent"]["agent_status"])
except Exception: print("gone")')
  # one failed `agent get` is a hiccup, not a dead agent: GONE only after 3 in a row
  if [ "$st" = gone ]; then gone=$((gone+1)); [ $gone -ge 3 ] && { say "GONE $N size=$size"; exit 0; }; sleep 5; continue; fi
  gone=0
  final=0; final_ok && final=1
  [ "$st" = blocked ] && { say "BLOCKED $N"; exit 0; }
  if [ "$st" != working ]; then
    [ $final = 1 ] && [ $mtime -ge $start ] && [ $((now-since)) -ge 15 ] && { say "DONE $N size=$size"; exit 0; }
    # herdr can report idle/done while the agent waits on a long shell command; trust its on-screen busy marker
    busy=0; herdr agent read $N --source visible --lines 30 2>/dev/null | grep -qE 'ctrl\+c to stop|esc to interrupt|while it works' && busy=1
    [ $busy = 0 ] && [ $((now-since)) -ge 600 ] && { say "IDLE $N size=$size final=$final"; exit 0; }
    sleep 5  # wait returns at once on an idle agent; do not spin
  fi
  [ $((now-start)) -ge $T ] && { say "TIMEOUT $N size=$size status=$st"; exit 0; }
  herdr agent wait $N --timeout 10000 >/dev/null 2>&1
done
