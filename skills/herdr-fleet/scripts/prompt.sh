#!/bin/zsh
# usage: R=<run dir> prompt.sh <agent> "<text>"
# Send a follow-up. Some agents (e.g. devin) queue a prompt sent while working ("Press Enter to send queued messages now"), so flush with Enter.
# command-code (headless): each prompt is a new `cmd -p` run in the agent's pane.
: ${R:?set R to the run dir}; R=${R:a}  # absolute: panes and command-code-run.sh resolve it from another cwd
E=$(${0:A:h}/session.py) || exit 1; eval "$E"  # this agent's own herdr session, pinned in $R/herdr.env
N=$1; shift
if [ -f $R/work/$N/kind ] && [ "$(cat $R/work/$N/kind)" = command-code ]; then
  W=$R/work/$N
  until mkdir $W/.lock 2>/dev/null; do sleep 1; done  # two prompts at once must not take the same run number
  trap 'rmdir $W/.lock 2>/dev/null' EXIT
  n=$(( $(cat $W/run 2>/dev/null || echo 0) + 1 ))
  print -r -- "$*" > $W/prompt-$n.txt
  print -r -- $n > $W/run  # before the run starts: a watcher must not take the previous run's exit file for this one
  herdr pane run $(cat $W/pane) "R=${(q)R} ${(q)${0:A:h}}/command-code-run.sh $N $n" >/dev/null || { print -r -- $((n-1)) > $W/run; echo "pane gone: run $n not started" >&2; exit 1; }
  echo "command-code run $n started; wait with watch.sh"
  exit 0
fi
# a TUI that is still loading can drop a prompt (seen with devin); --wait reports it as agent_prompt_stalled, so resend once
send() { herdr agent prompt $N "$*" --wait --until working --until blocked --timeout 20000 >/dev/null; }
send "$@" || { sleep 5; send "$@"; } || { echo "prompt failed for $N (see error above)" >&2; exit 1; }
sleep 4
herdr agent read $N --source recent-unwrapped --lines 15 | grep -q 'send queued messages' && herdr agent send-keys $N enter >/dev/null
herdr agent get $N | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["agent"]["agent_status"])'
