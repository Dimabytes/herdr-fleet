#!/bin/zsh
# usage: R=<run dir> collect.sh
# One table for the whole run: every task of every agent in work/, with the state watch.sh uses (task.sh).
# Reports no task owns are listed as untracked. Writes $R/index.md and prints the same table.
# Exit 0 only when every task is done or replaced (prompt.sh --replaces), so it can gate a merge.
# A later task does not close an earlier one.
: ${R:?set R to the run dir}; R=${R:a}  # absolute: panes and command-code-run.sh resolve it from another cwd
source ${0:A:h}/task.sh
OUT=$R/index.md
row() { local f=$1; [ -f "$f" ] && print -r -- "$(wc -c < $f | tr -d ' ') | ${f:t} | $(head -1 $f | tr -d '|' | cut -c1-80)" || print -r -- "0 | ${f:t} |"; }
{
  echo "# Run index: ${R:t}"
  echo ""
  echo "| agent | task | status | bytes | report | title (line 1) |"
  echo "| --- | --- | --- | --- | --- | --- |"
  open=0; owned=()
  for W in $R/work/*(/N); do
    N=${W:t}; [ $N = orchestrator ] && continue  # orchestrator is not an agent
    latest=$(cat $W/run 2>/dev/null || echo 0)
    [ $latest = 0 ] && { echo "| $N | - | no task | 0 | | |"; open=$((open+1)); continue; }
    for n in {1..$latest}; do
      F=$(task_report $W $n); owned+=($F)
      s=$(task_state $W $n)
      case $s in
        done) label=FINAL;;
        pending) if [ -f $W/send-failed-$n ]; then label="send failed"; elif [ -s "$F" ]; then label=WIP; else label=missing; fi;;
        replaced:*) label="replaced by ${s#replaced:}";;
        *) label="EXITED ${s#exited:}";;
      esac
      [[ $s == (done|replaced:*) ]] || open=$((open+1))
      echo "| $N | $n | $label | $(row $F) |"
    done
  done
  for f in $R/reports/*.md(N); do (( ${owned[(Ie)$f]} )) || echo "| - | - | untracked | $(row $f) |"; done
  echo ""
  echo "Open tasks (not done, not replaced): $open."
} > $OUT
cat $OUT
[ $open = 0 ]
