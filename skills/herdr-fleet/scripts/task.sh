# Task state shared by watch.sh and collect.sh, so both decide "done" the same way. Source it (zsh).
# A task is one prompt.sh call: number n, report path in work/<agent>/report-<n>, text in prompt-<n>.txt.
# Done means finish.sh wrote work/<agent>/done-<n>. command-code also needs its run's exit code 0 in exit-<n>.
# No file times and no report lines take part: a restart, a closed pane, or a later task change nothing.

task_report() { cat $1/report-$2 2>/dev/null; }  # task_report <work dir> <n>: the report path prompt.sh assigned

# task_state <work dir> <n>: done | pending | exited:<code> | exited:0-nofinish
task_state() {
  local W=$1 n=$2 code
  if [ -f $W/kind ] && [ "$(cat $W/kind)" = command-code ]; then
    [ -f $W/exit-$n ] || { echo pending; return; }
    code=$(cat $W/exit-$n)
    if [ "$code" != 0 ]; then echo exited:$code
    elif [ -f $W/done-$n ]; then echo done
    else echo exited:0-nofinish
    fi
    return
  fi
  if [ -f $W/done-$n ]; then echo done; else echo pending; fi
}
