#!/bin/zsh
# usage: R=<run dir> command-code-run.sh <name> <run#>   (runs inside the agent's pane; started by prompt.sh)
# One headless `cmd -p` per task. Run 1 names the session <name>; later runs resume it with -r, so follow-ups keep context.
# Exit code lands in work/<name>/exit-<run#> (watch.sh waits for that file).
: ${R:?set R to the run dir}; R=${R:a}  # absolute: panes and command-code-run.sh resolve it from another cwd
N=$1; n=$2; W="$R/work/$N"
cd "$R" || exit 1
rm -f "$W/exit-$n"
if [ $n = 1 ]; then SESS=(-n $N); else SESS=(-r $N); fi
ARGS=("${(@f)$(cat "$W/args")}")  # one argv item per line: args with spaces survive
cmd -p "$(cat "$W/prompt-$n.txt")" "${ARGS[@]}" "${SESS[@]}"
echo $? > "$W/exit-$n"
