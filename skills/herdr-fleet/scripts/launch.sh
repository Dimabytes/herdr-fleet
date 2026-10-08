#!/bin/zsh
# usage: R=<run dir> launch.sh <name> <pane> <agent> [extra agent args...]
# Looks up <agent> in .herdr-fleet.config.json in the project root (created from agents.example.json if missing),
# cd's the pane to $R, starts it: --model <model> <args> <extra args>. Send the task with prompt.sh.
: ${R:?set R to the run dir}
CFG=$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.herdr-fleet.config.json
[ -f $CFG ] || { cp ${0:A:h}/../agents.example.json $CFG; echo "created $CFG from example, check the models"; }
N=$1; PANE=$2; AGENT=$3; shift 3
A=(${(f)"$(python3 -c 'import json,sys
c=json.load(open(sys.argv[1]))["agents"]; n=sys.argv[2]
n in c or sys.exit("unknown agent " + n + "; have: " + ", ".join(c))
a=c[n]; print(a["kind"], "--model", a["model"], *a.get("args", []), sep="\n")' $CFG $AGENT)"}) || exit 1
herdr pane run $PANE "cd $R" >/dev/null 2>&1; sleep 1
start() { herdr agent start $N --kind $A[1] --pane $PANE --timeout 90000 -- $A[2,-1] "$@" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); r=d.get("result"); print("start", r["agent"]["name"], r["argv"]) if r else print("ERR", d)'; }
start "$@"
# An agent CLI can self-update on start and exit ("Please restart Codex"). Retry once if it is gone.
sleep 8; herdr agent get $N >/dev/null 2>&1 || { echo "agent $N exited after start, restarting once"; start "$@"; }
