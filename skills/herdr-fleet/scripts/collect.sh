#!/bin/zsh
# usage: R=<run dir> collect.sh
# One table for the whole run: every agent in work/ and every report in reports/, with line-2 status.
# Writes $R/index.md and prints the same table. Exit 0 only when every agent has a FINAL report, so it can gate a merge.
: ${R:?set R to the run dir}; R=${R:a}  # absolute: panes and command-code-run.sh resolve it from another cwd
OUT=$R/index.md
{
  echo "# Run index: ${R:t}"
  echo ""
  echo "| agent | status | bytes | title (line 1) |"
  echo "| --- | --- | --- | --- |"
  names=()
  for d in $R/work/*(/N); do [ ${d:t} = orchestrator ] || names+=(${d:t}); done  # orchestrator is not an agent
  for f in $R/reports/*.md(N); do n=${f:t:r}; [[ " ${names[*]} " == *" $n "* ]] || names+=($n); done
  pending=0
  for n in $names; do
    f=$R/reports/$n.md
    if [ ! -f $f ]; then echo "| $n | missing | 0 | |"; pending=$((pending+1)); continue; fi
    st=$(sed -n 2p $f); case $st in "Status: FINAL") s=FINAL;; "Status: WIP") s=WIP; pending=$((pending+1));; *) s="no status"; pending=$((pending+1));; esac
    title=$(head -1 $f | tr -d '|' | cut -c1-100)
    echo "| $n | $s | $(wc -c < $f | tr -d ' ') | $title |"
  done
  echo ""
  echo "Not final: $pending of ${#names} agents."
} > $OUT
cat $OUT
[ $pending = 0 ]
