---
name: herdr-fleet
description: Run many coding agents in parallel through Herdr (devin, codex, cursor and others from .herdr-fleet.config.json in the project root) for research, review fan-out or cross-checks. Use when the user asks to orchestrate several models via herdr, spawn N agents in herdr panes, or split a big investigation across agents that report through files.
---

# Herdr fleet

Load the `herdr` skill first for CLI basics. Before any `herdr` command: `test "${HERDR_ENV:-}" = 1`. Never run bare `herdr` (it opens the TUI).

## Agents

The agent list lives in `.herdr-fleet.config.json` in the project root (git top level), not in this skill. Each project has its own. Run `scripts/launch.sh` from the project: on first use it creates the file from `agents.example.json`.

```json
{
  "agents": {
    "grok": {
      "kind": "cursor",
      "model": "grok-4.7-high",
      "args": ["--force", "--trust", "--sandbox", "disabled"],
      "notes": "Protocols, endpoints, code reading, exact numbers. 15-30 min per deep task."
    }
  }
}
```

| field   | meaning                                                          |
| ------- | ---------------------------------------------------------------- |
| key     | agent name the user says: "run it on grok and luna"              |
| `kind`  | `herdr agent start --kind` value                                 |
| `model` | passed as `--model <model>`                                      |
| `args`  | extra CLI args, one array item per argv item                     |
| `notes` | what it is good at, what to watch, how long it takes; pick by it |

Read the file before you pick agents. To add or change an agent, edit the file. Model ids drift. Check: `cursor-agent --list-models`, `devin models list | grep -oE 'swe-2[a-z0-9-]*' | sort -u`, `codex debug models`.

## Layout

- Max 10 agents per tab. More than 10 → another tab. Do not squeeze agents into the caller's tab.
- `herdr tab create --workspace "$HERDR_WORKSPACE_ID" --label <name> --cwd "$R" --no-focus`.
- 2 columns × 5 rows. `--ratio` is the share the **original** pane keeps:
  split root `right 0.5`, then each column `down 0.2`, `down 0.25`, `down 0.3333`, `down 0.5`.
- Always `--no-focus`. Parse pane ids from the JSON.
- Names: `[a-z][a-z0-9_-]{0,31}`.

## Launch

```bash
R=<run dir> scripts/launch.sh <name> <pane> <agent> [extra agent args...]
scripts/prompt.sh <name> "<task>"
```

`launch.sh` cd's the pane to `$R` (stray relative writes land there, not in the code repo), looks up `<agent>` and starts it. It does not send a task. For a research run, send the standard prompt:

```text
You are agent '<name>'. Read fully: $R/00-context.md, then $R/briefs/<name>.md. Do the brief. Write the full report to $R/reports/<name>.md (file, not chat; update it as you go). Scratch files go to $R/work/<name>/. Use agent-browser only with --session <name>; never run agent-browser close --all. When the report is complete, make its line 2 exactly: Status: FINAL. Then reply with only the report path.
```

## Gotchas

- **Bypass is blocked by the Claude Code auto-mode classifier** ("Create Unsafe Agents") until the user says bypass is allowed in chat. Ask once, up front.
- **devin and cursor run auto-approve** (`bypass`, `--force --trust`): no approval gate exists between an agent and `rm -rf`. codex runs `--approve-for-me`: the reviewer model gates each command and the sandbox still confines writes. Either way, the no-destruction rule in `00-context.md` is required. Do not launch without it.
- **codex fast tier** = `service_tier="priority"`. User `config.toml` sets `"default"`, so pin it with `-c`. Verify in the welcome card: `GPT-6-Luna max fast`. `--approve-for-me` is NOT `--dangerously-bypass-…` (YOLO).
- **Devin ignores** `--permission-mode smart` when the env has `DEVIN_PERMISSION_MODE=bypass`. Trust the footer, not argv: it must say `(bypass permissions on)`. If a permission dialog appears without bypass, close that pane and start a new one with bypass.
- **Never `/new` on a Devin.** `/new` resets it to accept-edits and it hangs on file-change approval. New task → fresh pane. cursor and codex can take a new prompt in the same session (keeps context).
- **Follow-ups: use `scripts/prompt.sh`.** Prompting a working devin queues the text; the footer shows `Press Enter to send queued messages now` and herdr may report `done` while it waits. The script presses Enter.
- `agent_status` alone lies (idle/done while still writing, or done with a half-written report). Completion = `Status: FINAL` in the report (`scripts/watch.sh`).
- **Cursor may stop with** `Agent stopped retrying` (connection). `prompt.sh <name> continue` resumes it.
- **Shared browser state.** One agent ran `agent-browser close --all` and closed every session, including the owner's logged-in Discord. Every agent uses `--session <name>`; never `close --all`. A logged-in profile (Discord) belongs to one agent only: the profile dir is locked.
- Agents leave capture processes running. At the end: `pkill -f "$R/work/<name>/"` per agent, and check for relative-path children (`ps -axo pid,command | grep <script>`).

## Files, not chat

```
$R/00-context.md       goal, known facts/numbers, hard rules, report format, agent list
$R/briefs/<name>.md    one brief per agent
$R/reports/<name>.md   agent output (follow-ups: <name>-<topic>.md)
$R/work/<name>/        agent scratch scripts and outputs
$R/work/orchestrator/  your own checks (notes.md)
```

Do not put `$R` in `/tmp` or the scratchpad: a reboot wipes them. Use a persistent dir, e.g. the task folder.

Hard rules to put in `00-context.md`:

- you run with auto-approve — no permission prompt will stop you. Never delete, overwrite, or destroy anything you did not create this run: no `rm`, no `mv` onto existing files, no `git clean`/`reset --hard`/`checkout --`, no `kill`/`pkill` outside your own `work/<name>/` processes, no dropping/truncating files, dirs, rows, tables, or branches. If something is in the way, write beside it or stop and report;
- read-only on code repos; write only to `work/<name>/` and the report; the owner may edit the repo during the run (read `git show HEAD:<path>` if a file looks half-written);
- no SSH to prod; no tests/training/full backtests unless the brief allows; run Python from the project venv;
- no accounts, no money, no signups; browser via `agent-browser --session <name>`, never `close --all`;
- keep work files under ~200 MB each (aggregate, sample, or parquet);
- every claim with `file:line` / URL + date / command + numbers; mark `verified` / `likely` / `speculative`;
- put `Status: FINAL` on line 2 of the report only when it is complete.

## Watch

One background watcher per agent: `R=... scripts/watch.sh <name> [report-basename] [timeout_s]` with `run_in_background`.
It exits on DONE (report says `Status: FINAL`, changed after the watcher started, stable 15 s; it blocks on `herdr agent wait`, so it wakes within ~20 s),
IDLE (agent not working, report stable 10 min, not final — nudge it), BLOCKED, GONE, TIMEOUT (default 90 min).
That wakes you. No polling in between.

## Verify

- Give the most suspicious topic to 2 agents of different models. Overlap finds more. In one run three agents agreed on a source; two devins disagreed on one latency by 15× and only a re-check settled it.
- Re-check every key number yourself with a small script before it goes in the final report. Keep a "refuted" list.
- Close only panes and tabs you created, and only when the user no longer needs them.
