#!/bin/zsh
# usage: tests/test_completion.sh
# Task completion end to end, with no models and no herdr: a fake `herdr` on PATH plays the agents,
# and the test writes reports and runs the exact finish.sh line from each prompt. One PASS/FAIL line per check.
set -u
S=${0:A:h}/../skills/herdr-fleet/scripts
TMP=$(mktemp -d); trap 'rm -rf $TMP' EXIT
export FAKE=$TMP/fake R=$TMP/run PATH=$TMP/bin:$PATH IDLE_S=2 POLL_S=0.2 PROMPT_SETTLE_S=0
mkdir -p $FAKE $TMP/bin $R/reports
cat > $TMP/bin/herdr <<'EOF'
#!/bin/zsh
# fake herdr: an agent exists while $FAKE/<name>.status exists; a pane while $FAKE/pane-<id> exists
case "$1 $2" in
  "agent get") [ -f $FAKE/$3.status ] || exit 1; printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$(cat $FAKE/$3.status)";;
  "agent wait") sleep 0.1;;
  "agent read") cat $FAKE/$3.screen 2>/dev/null;;
  "agent prompt") print -r -- "$4" >> $FAKE/$3.prompts;;
  "agent send-keys"|"notification show") ;;
  "pane get") [ -f "$FAKE/pane-$3" ];;
  "pane run") print -r -- "$4" >> "$FAKE/pane-$3.runs";;
  *) echo "fake herdr: unhandled: $*" >&2; exit 1;;
esac
EOF
chmod +x $TMP/bin/herdr
echo 'export HERDR_SOCKET_PATH=/dev/null HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t1 HERDR_PANE_ID=w1:p0' > $R/herdr.env

passed=0; failed=0
ok() { echo "PASS $1"; passed=$((passed+1)); }
bad() { echo "FAIL $1: $2"; failed=$((failed+1)); }
starts() { [[ $3 == $2* ]] && ok $1 || bad $1 "want '$2...', got '$3'"; }   # starts <check> <prefix> <output>
has() { grep -qF -- "$2" <<< "$3" && ok $1 || bad $1 "no '$2' in output"; }   # has <check> <text> <output>
agent() { mkdir -p $R/work/$1; echo ${2:-idle} > $FAKE/$1.status; }          # agent <name> [status]
send() { $S/prompt.sh "$@" >/dev/null; }
work() { echo "# report $1 #$2" > $(cat $R/work/$1/report-$2); }               # the agent writes its report
finish() { eval "$(grep '/finish.sh ' $R/work/$1/prompt-$2.txt)" >/dev/null; } # the exact line from the prompt
watch() { $S/watch.sh "$@"; }

echo "-- finished before the watcher started"
agent a1; send a1 "task one"; work a1 1; finish a1 1
starts done-before-watcher "DONE a1 #1" "$(watch a1 1 5)"

echo "-- watcher restarted while the agent works"
agent a2 working; send a2 "task"
starts keeps-waiting-while-working "TIMEOUT a2 #1" "$(watch a2 1 1)"
watch a2 1 20 > $TMP/w2 & p=$!
sleep 0.5; work a2 1; finish a2 1; wait $p
starts restarted-watcher-sees-finish "DONE a2 #1" "$(cat $TMP/w2)"

echo "-- #2 queued, then #1 finishes"
agent a3 working; send a3 "first"; send a3 "second, queued while the first runs"
watch a3 1 20 > $TMP/w31 & p1=$!
watch a3 2 3 > $TMP/w32 & p2=$!
sleep 0.5; work a3 1; finish a3 1; wait $p1
starts first-done-while-second-queued "DONE a3 #1" "$(cat $TMP/w31)"
wait $p2
starts second-still-open "TIMEOUT a3 #2" "$(cat $TMP/w32)"
work a3 2; finish a3 2
starts second-done-later "DONE a3 #2" "$(watch a3 2 5)"
c=$(R=$R $S/collect.sh)
has collect-first-final "| a3 | 1 | FINAL |" "$c"
has collect-second-final "| a3 | 2 | FINAL |" "$c"
[[ $(cat $R/work/a3/report-1) != $(cat $R/work/a3/report-2) ]] && ok own-report-per-task || bad own-report-per-task "same path"

echo "-- a late finish of #1 after #2 was sent"
agent a4 working; send a4 "one"; work a4 1; finish a4 1
send a4 "two"; finish a4 1
starts late-finish-does-not-close-next "TIMEOUT a4 #2" "$(watch a4 2 1)"
starts default-watches-latest "TIMEOUT a4 #2" "$(watch a4 '' 1)"

echo "-- report written, finish never run"
agent a5; send a5 "task"; work a5 1
starts no-finish-is-not-done "IDLE a5 #1" "$(watch a5 1 10)"
echo "busy: 1 command still running" > $FAKE/a5.screen
starts busy-marker-holds-idle "TIMEOUT a5 #1" "$(IDLE_S=0 watch a5 1 1)"
rm $FAKE/a5.screen

echo "-- finished, then the pane closed"
agent a6; send a6 "task"; work a6 1; finish a6 1; rm $FAKE/a6.status
starts done-survives-closed-pane "DONE a6 #1" "$(watch a6 1 5)"
agent a6b; send a6b "task"; rm $FAKE/a6b.status
starts gone-without-finish "GONE a6b #1" "$(watch a6b 1 5)"

echo "-- finish.sh refuses a missing report and a wrong number"
agent a7; send a7 "task"
finish a7 1 2>/dev/null; code=$?
[ $code = 1 ] && [ ! -f $R/work/a7/done-1 ] && ok finish-refuses-missing-report || bad finish-refuses-missing-report "exit $code"
$S/finish.sh $R a7 9 2>/dev/null; code=$?
[ $code = 2 ] && ok finish-refuses-unknown-task || bad finish-refuses-unknown-task "exit $code"

echo "-- --raw nudges the current task, --slug names the report"
agent a8; send a8 "task"; $S/prompt.sh a8 --raw "continue" >/dev/null
[ "$(cat $R/work/a8/run)" = 1 ] && ok raw-takes-no-number || bad raw-takes-no-number "run=$(cat $R/work/a8/run)"
[ "$(tail -1 $FAKE/a8.prompts)" = continue ] && ok raw-sends-text-as-is || bad raw-sends-text-as-is "$(tail -1 $FAKE/a8.prompts)"
send a8 --slug rule-data "task two"
[ "$(cat $R/work/a8/report-2)" = $R/reports/a8-2-rule-data.md ] && ok slug-in-report-name || bad slug-in-report-name "$(cat $R/work/a8/report-2)"

echo "-- command-code keeps its exit code"
mkdir -p $R/work/cc; echo command-code > $R/work/cc/kind; echo w1:p9 > $R/work/cc/pane; : > $R/work/cc/args; touch $FAKE/pane-w1:p9
send cc "task"; echo 0 > $R/work/cc/exit-1
starts cc-exit0-without-finish "EXITED cc #1 0-nofinish" "$(watch cc 1 5)"
send cc "task"; work cc 2; finish cc 2
starts cc-finish-before-exit-is-pending "TIMEOUT cc #2" "$(watch cc 2 1)"
echo 0 > $R/work/cc/exit-2
starts cc-exit0-with-finish "DONE cc #2" "$(watch cc 2 5)"
send cc "task"; work cc 3; finish cc 3; echo 3 > $R/work/cc/exit-3
starts cc-nonzero-exit "EXITED cc #3 3" "$(watch cc 3 5)"
$S/prompt.sh cc --raw "x" 2>/dev/null; code=$?
[ $code = 2 ] && ok cc-refuses-raw || bad cc-refuses-raw "exit $code"

echo "-- collect.sh: same states, gate on each agent's latest task"
echo "# old" > $R/reports/legacy.md
c=$(R=$R $S/collect.sh); code=$?
has collect-wip "| a5 | 1 | WIP |" "$c"
has collect-missing "| a7 | 1 | missing |" "$c"
has collect-cc-exited "| cc | 3 | EXITED 3 |" "$c"
has collect-untracked "| - | - | untracked | 6 | legacy.md |" "$c"
[ $code = 1 ] && ok collect-gate-fails-while-open || bad collect-gate-fails-while-open "exit $code"

echo "$passed passed, $failed failed"
[ $failed = 0 ]
