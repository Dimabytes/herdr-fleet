#!/bin/zsh
# usage: R=<run dir> cleanup.sh [--close] [name...]
# Dry run by default: prints the processes and panes it would stop and close. --close acts.
# Stops only processes whose command line contains $R/work/<name>/, and closes only the pane of an agent named in
# this run. Never closes the orchestrator's own pane ($HERDR_PANE_ID). Re-tile the tab with grid.py afterwards.
: ${R:?set R to the run dir}
E=$(${0:A:h}/session.py) || exit 1; eval "$E"  # this agent's own herdr session, pinned in $R/herdr.env
ACT=0; [ "$1" = --close ] && { ACT=1; shift; }
names=("$@")
if [ ${#names} -eq 0 ]; then for d in $R/work/*(/N); do [ ${d:t} = orchestrator ] || names+=(${d:t}); done; fi
live=$(herdr pane list 2>/dev/null | python3 -c 'import json,sys; print(" ".join(p["pane_id"] for p in json.load(sys.stdin)["result"]["panes"]))' 2>/dev/null)
for n in $names; do
  pane=$(herdr agent get $n 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["result"]["agent"]["pane_id"])
except Exception: pass')
  # command-code has no herdr agent: fall back to the pane recorded at launch, if it is still open
  if [ -z "$pane" ] && [ -f $R/work/$n/pane ]; then p=$(cat $R/work/$n/pane); [[ " $live " == *" $p "* ]] && pane=$p; fi
  pat=$(python3 -c 'import re,sys; print(re.escape(sys.argv[1]))' "$R/work/$n/")  # regex-escaped: a path must match only itself
  procs=$(pgrep -f "$pat" | wc -l | tr -d ' ')
  echo "$n: pane=${pane:-none} processes=$procs"
  [ $ACT = 1 ] || continue
  [ "$pane" = "${HERDR_PANE_ID:-}" ] && { echo "  skip: that is this orchestrator's pane"; continue; }
  pkill -f "$pat" 2>/dev/null
  [ -n "$pane" ] && herdr pane close $pane >/dev/null 2>&1 && echo "  closed $pane"
done
[ $ACT = 1 ] || echo "dry run: add --close to act"
