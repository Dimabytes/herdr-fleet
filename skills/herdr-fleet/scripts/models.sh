#!/bin/zsh
# usage: models.sh [kind...]
# Lists the model ids each installed agent CLI offers right now, by asking the CLI itself, so nothing here goes stale.
# No kind given: every CLI found on PATH. Output: "== <kind>" then one id per line (a description may follow after two spaces).
# Lists can be long (devin: hundreds): filter with grep -i. Pass an id to launch.sh with MODEL=<id>. CLIs with no listing command print a pointer instead.
kinds=("$@")
[ ${#kinds} -eq 0 ] && kinds=(cursor codex claude devin command-code opencode pi grok gemini kimi)
bin() { case $1 in cursor) echo cursor-agent;; command-code) echo cmd;; *) echo $1;; esac; }
for k in $kinds; do
  b=$(bin $k); command -v $b >/dev/null || { [ $# -gt 0 ] && echo "== $k\n(not installed: $b)"; continue; }
  echo "== $k"
  case $k in
    cursor) cursor-agent --list-models 2>&1 | sed -n 's/^\([A-Za-z0-9._-]*\) - \(.*\)$/\1  \2/p';;
    codex) codex debug models 2>/dev/null | python3 -c 'import json,sys
for m in json.load(sys.stdin)["models"]:
    if m.get("visibility") == "list": print(m["slug"] + "  " + m.get("display_name", ""))';;
    devin) devin models list 2>&1 | sed -n 's/^  \([a-z0-9][A-Za-z0-9._-]*\)  *\(.*\)$/\1  \2/p' | sed 's/  *\[.*\]$//';;
    command-code) cmd --list-models 2>&1 | sed -n 's/^\([a-z0-9-]*\/[A-Za-z0-9._-]*\)  *\(.*\)$/\1  \2/p';;
    opencode) opencode models 2>&1;;
    pi) pi --list-models 2>&1 | awk 'NR>1 && NF>=2 {print $1 "/" $2}';;
    grok) grok models 2>&1 | sed -n 's/^  [* ] *\([A-Za-z0-9._-]*\).*/\1/p';;
    claude) echo "no listing command; --model takes an alias that tracks the latest (for example opus, sonnet, fable) or a full id: see claude --help";;
    *) echo "no listing command; see: $b --help";;
  esac
done
