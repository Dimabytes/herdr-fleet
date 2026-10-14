#!/bin/zsh
# usage: finish.sh <run dir> <agent> <task#>
# The agent runs this as its last action; prompt.sh writes the exact line into every task.
# Checks the report prompt.sh assigned to that task, then records the task as done in work/<agent>/done-<task#>.
R=${1:?usage: finish.sh <run dir> <agent> <task#>}; N=${2:?agent name}; n=${3:?task number}
W=${R:a}/work/$N
[[ $n == <-> ]] || { echo "task number must be an integer, got '$n'" >&2; exit 2; }
F=$(cat $W/report-$n 2>/dev/null) || { echo "no task #$n for agent $N in $R: use the line from your task" >&2; exit 2; }
[ -s $F ] || { echo "report $F is missing or empty: write it, then run this command again" >&2; exit 1; }
{ print -r -- "report=$F at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > $W/.done-$n.tmp && mv $W/.done-$n.tmp $W/done-$n } \
  || { echo "could not write $W/done-$n: task #$n is NOT done; fix the error above, then run this command again" >&2; exit 1; }
echo "task #$n done: $F"
