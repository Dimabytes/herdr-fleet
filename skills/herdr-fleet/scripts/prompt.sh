#!/bin/zsh
# usage: R=<run dir> prompt.sh <agent> [--slug <topic>] "<task>"   send a new task
#        R=<run dir> prompt.sh <agent> --raw "<text>"               nudge the current task (continue, an answer)
# A new task gets the next number n (work/<agent>/run; numbers are never reused), its own report
# reports/<agent>-<n>[-<topic>].md, and a closing block with the exact finish.sh line. The text sent is saved in
# work/<agent>/prompt-<n>.txt and the report path in report-<n>. Wait with: watch.sh <agent> <n>.
# --raw sends the text as is: no number, no report, the watcher of the current task keeps waiting.
# Some agents queue a prompt sent while working, so flush with one more Enter:
# devin shows "Press Enter to send queued messages now"; cursor holds a follow-up until the whole task ends
# and shows "enter steer", where Enter delivers it at the next step.
# command-code (headless): each task is a new `cmd -p` run in the agent's pane.
: ${R:?set R to the run dir}; R=${R:a}  # absolute: panes and command-code-run.sh resolve it from another cwd
E=$(${0:A:h}/session.py) || exit 1; eval "$E"  # this agent's own herdr session, pinned in $R/herdr.env
N=$1; shift
RAW=0; SLUG=
while :; do
  case $1 in
    --raw) RAW=1; shift;;
    --slug) [[ $2 =~ '^[a-z0-9][a-z0-9-]*$' ]] || { echo "--slug takes [a-z0-9-], got '$2'" >&2; exit 2; }; SLUG=-$2; shift 2;;
    *) break;;
  esac
done
W=$R/work/$N
[ -d $W ] || { echo "no agent $N in $R: launch it first" >&2; exit 1; }
CC=0; [ -f $W/kind ] && [ "$(cat $W/kind)" = command-code ] && CC=1
[ $RAW = 1 ] && [ $CC = 1 ] && { echo "command-code: every prompt is a new run, send a task without --raw" >&2; exit 2; }
TEXT="$*"
if [ $RAW = 0 ]; then
  until mkdir $W/.lock 2>/dev/null; do sleep 1; done  # two prompts at once must not take the same number
  trap 'rmdir $W/.lock 2>/dev/null' EXIT
  n=$(( $(cat $W/run 2>/dev/null || echo 0) + 1 ))
  F=$R/reports/$N-$n$SLUG.md
  TEXT="$TEXT

---
Task #$n for agent '$N'.
Write the full report for this task to $F (a file, not chat; update it as you go).
When the report is complete, run this command as your last action:
${(q)${0:A:h}}/finish.sh ${(q)R} $N $n
It checks the report and records task #$n as done. If it fails, fix what it says and run it again.
Run it only for task #$n. Then reply with only the report path."
  print -r -- $F > $W/report-$n
  print -r -- "$TEXT" > $W/prompt-$n.txt
  print -r -- $n > $W/run  # before sending: a watcher started now waits for this task
fi
if [ $CC = 1 ]; then
  # nothing reached the agent when the pane is gone, so this number is safe to reuse
  herdr pane run $(cat $W/pane) "R=${(q)R} ${(q)${0:A:h}}/command-code-run.sh $N $n" >/dev/null || { print -r -- $((n-1)) > $W/run; echo "pane gone: task $n not started" >&2; exit 1; }
  echo "task #$n started (command-code); report: $F; wait: R=$R watch.sh $N $n"
  exit 0
fi
# a TUI that is still loading can drop a prompt (seen with devin); --wait reports it as agent_prompt_stalled, so resend once
status() { herdr agent get $N | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["agent"]["agent_status"])'; }
send() { herdr agent prompt $N "$TEXT" --wait --until working --until blocked --timeout 20000 >/dev/null; }
# a failed send may still have reached the agent, so the number stays taken; send-failed-<n> tells collect.sh
fail() { [ $RAW = 0 ] && : > $W/send-failed-$n; echo "prompt failed for $N (see error above)" >&2; exit 1; }
if [ "$(status)" = working ]; then
  # a working agent queues the prompt and may never report a new state: a resend would queue it twice
  herdr agent prompt $N "$TEXT" >/dev/null || fail
else
  send || { sleep 5; send; } || fail
fi
sleep ${PROMPT_SETTLE_S:-4}
herdr agent read $N --source recent-unwrapped --lines 15 | grep -qE 'send queued messages|enter steer' && herdr agent send-keys $N enter >/dev/null
[ $RAW = 0 ] && echo "task #$n sent; report: $F; wait: R=$R watch.sh $N $n"
status
