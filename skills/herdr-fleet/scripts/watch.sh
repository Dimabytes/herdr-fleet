#!/bin/zsh
# usage: R=<run dir> watch.sh <agent> [report-basename] [timeout_s]   (run in background)
# Blocks on `herdr agent wait` (returns as soon as the agent stops working), then checks the report.
# DONE: report has a "Status: FINAL" line, changed after this watcher started, unchanged 15 s, agent not working.
# IDLE: agent not working and report unchanged 600 s without that -> nudge it (queued prompt? WIP report?).
# Exits early on BLOCKED / GONE, or TIMEOUT.
: ${R:?set R to the run dir}
N=$1; F=$R/reports/${2:-$1}.md; T=${3:-5400}
start=$(date +%s); last=-1; since=$start
while true; do
  now=$(date +%s); size=0; mtime=0
  [ -f $F ] && { size=$(stat -f %z $F); mtime=$(stat -f %m $F); }
  [ $size -ne $last ] && { last=$size; since=$now; }
  st=$(herdr agent get $N 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["result"]["agent"]["agent_status"])
except Exception: print("gone")')
  final=0; [ -f $F ] && grep -q '^Status: FINAL' $F && final=1
  [ "$st" = blocked ] && { echo "BLOCKED $N"; exit 0; }
  [ "$st" = gone ] && { echo "GONE $N size=$size"; exit 0; }
  if [ "$st" != working ]; then
    [ $final = 1 ] && [ $mtime -ge $start ] && [ $((now-since)) -ge 15 ] && { echo "DONE $N size=$size"; exit 0; }
    # herdr can report idle/done while the agent waits on a long shell command; trust its on-screen busy marker
    busy=0; herdr agent read $N --source visible --lines 30 2>/dev/null | grep -qE 'ctrl\+c to stop|esc to interrupt|while it works' && busy=1
    [ $busy = 0 ] && [ $((now-since)) -ge 600 ] && { echo "IDLE $N size=$size final=$final"; exit 0; }
    sleep 5  # wait returns at once on an idle agent; do not spin
  fi
  [ $((now-start)) -ge $T ] && { echo "TIMEOUT $N size=$size status=$st"; exit 0; }
  herdr agent wait $N --timeout 10000 >/dev/null 2>&1
done
