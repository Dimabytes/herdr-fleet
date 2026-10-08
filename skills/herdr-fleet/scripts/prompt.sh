#!/bin/zsh
# usage: [R=<run dir>] prompt.sh <agent> "<text>"
# Send a follow-up. A working devin queues it ("Press Enter to send queued messages now"), so flush with Enter.
# command-code (headless): each prompt is a new `cmd -p` run in the agent's pane; R is required to find it.
N=$1; shift
if [ -n "${R:-}" ] && [ -f $R/work/$N/kind ] && [ "$(cat $R/work/$N/kind)" = command-code ]; then
  W=$R/work/$N
  until mkdir $W/.lock 2>/dev/null; do sleep 1; done  # two prompts at once must not take the same run number
  trap 'rmdir $W/.lock 2>/dev/null' EXIT
  n=$(( $(cat $W/run 2>/dev/null || echo 0) + 1 ))
  print -r -- "$*" > $W/prompt-$n.txt
  herdr pane run $(cat $W/pane) "R=${(q)R} ${(q)${0:A:h}}/command-code-run.sh $N $n" >/dev/null || { echo "pane gone: run $n not started" >&2; exit 1; }
  print -r -- $n > $W/run
  echo "command-code run $n started; wait with watch.sh"
  exit 0
fi
herdr agent prompt $N "$*" >/dev/null || { echo "prompt failed for $N (see error above)" >&2; exit 1; }
sleep 4
herdr agent read $N --source recent-unwrapped --lines 15 | grep -q 'send queued messages' && herdr agent send-keys $N enter >/dev/null
herdr agent get $N | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["agent"]["agent_status"])'
