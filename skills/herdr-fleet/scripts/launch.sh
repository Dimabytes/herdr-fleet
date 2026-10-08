#!/bin/zsh
# usage: [MODEL=<id>] R=<run dir> launch.sh <name> <pane> <agent|kind> [extra agent args...]
# <agent> is a key in .herdr-fleet.config.json in the project root (created from agents.example.json if missing).
# If it is not a key but is a herdr agent kind (see `herdr agent start --help`) or command-code, that CLI starts with its own defaults.
# The model is optional: MODEL=<id> overrides the config, and with no model at all the CLI picks its default.
# Find current ids with models.sh. Starts: <kind> [--model <model>] <config args> <extra args>. Send the task with prompt.sh.
: ${R:?set R to the run dir}
set -o pipefail  # a failed herdr start must fail the script, not just print ERR
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "run launch.sh from inside the project repo (the config lives at its top level)" >&2; exit 1; }
CFG=$TOP/.herdr-fleet.config.json
[ -f $CFG ] || { cp ${0:A:h}/../agents.example.json $CFG; echo "created $CFG from example, check the agents"; }
N=$1; PANE=$2; AGENT=$3; shift 3
A=(${(f)"$(python3 -c 'import json,sys,os
c=json.load(open(sys.argv[1]))["agents"]; n=sys.argv[2]
a=c.get(n) or ({"kind": n} if n in sys.argv[3].split() else None)
a or sys.exit("unknown agent " + n + "; configured: " + ", ".join(c) + "; or use a herdr kind: " + sys.argv[3])
kind=a["kind"]; model=os.environ.get("MODEL") or a.get("model")
flag=a.get("model_flag") or ("-m" if kind in ("command-code", "opencode", "gemini") else "--model")
print(kind, *([flag, model] if model else []), *a.get("args", []), sep="\n")' $CFG $AGENT "$(herdr agent start --help 2>/dev/null | sed -n 's/.*possible values: //p' | tr -d '[],') command-code")"}) || exit 1
herdr pane get $PANE >/dev/null 2>&1 || { echo "pane $PANE does not exist; check the id from grid.py" >&2; exit 1; }
mkdir -p $R/briefs $R/reports $R/work/$N
herdr pane run $PANE "cd ${(q)R}" >/dev/null 2>&1; sleep 1
if [ $A[1] = command-code ]; then
  # herdr cannot classify command-code's TUI, so it runs headless: one `cmd -p` per task, in this pane (see command-code-run.sh)
  print -r -- command-code > $R/work/$N/kind && print -r -- $PANE > $R/work/$N/pane
  printf '%s\n' $A[2,-1] > $R/work/$N/args
  echo "start $N command-code (headless, no agent started). Send the task with prompt.sh."
  exit 0
fi
start() { herdr agent start $N --kind $A[1] --pane $PANE --timeout 90000 -- $A[2,-1] "$@" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); r=d.get("result"); print("start", r["agent"]["name"], r["argv"]) if r else (print("ERR", d), sys.exit(1))'; }
start "$@" || exit 1
# An agent CLI can self-update on start and exit ("Please restart Codex"). Retry once if it is gone.
sleep 8; herdr agent get $N >/dev/null 2>&1 || { echo "agent $N exited after start, restarting once"; start "$@" || exit 1; }
