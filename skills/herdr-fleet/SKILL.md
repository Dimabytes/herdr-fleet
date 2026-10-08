---
name: herdr-fleet
description: Run several coding agents in parallel through Herdr panes, with each agent reporting through a file. The agents come from a per-project config, so any mix of supported CLIs works. Use when the user asks to orchestrate several models via herdr, spawn N agents in herdr panes, fan out a review, or split a big investigation across agents.
---

# Herdr fleet

**HARD RULE, STEP 1: load the `herdr` skill (Skill tool) before anything else.** Do it before you read the config, write files, or run any script. The fleet scripts do not replace it: it holds the CLI rules this skill assumes. No exceptions, even if you plan no direct `herdr` calls.

Before any `herdr` command: `test "${HERDR_ENV:-}" = 1`. Never run bare `herdr` (it opens the TUI).

Scripts: `S` is the `scripts/` directory of this skill, as an absolute path. Installed with `npx skills add -g` it is `~/.agents/skills/herdr-fleet/scripts`; from a repo checkout it is `skills/herdr-fleet/scripts`. Check it exists before you use it. Every `$S/...` below uses it.

## Agents

The agent list lives in `.herdr-fleet.config.json` in the project root (git top level), not in this skill. Each project has its own. Run `$S/launch.sh` from inside the project repo: on first use it creates the file from `herdr-fleet.config.example.json`. Outside a git repo it stops, so the config is never written to the wrong place.


| field         | meaning                                                          |
| ------------- | ---------------------------------------------------------------- |
| key           | agent name the user says: "run it on codex-sol and cursor-grok"  |
| `kind`        | `herdr agent start --kind` value, or `command-code` (see below)  |
| `model`       | optional. Passed as `--model <model>`. Omit it to use the CLI's own default |
| `model_flag`  | optional. Flag used for the model, if the CLI does not take `--model` (`-m` is already used for command-code, opencode, gemini) |
| `args`        | extra CLI args, one array item per argv item                     |
| `notes`       | what it is good at, what to watch, how long it takes; pick by it |

Read the file before you pick agents. To add or change an agent, edit the file. Every kind is optional: keep only the CLIs the user has installed and logged in to. The shipped example is a starting point, not a recommendation.

### Models: one per entry, checked against the CLI

The example has one entry per model, and every entry sets `model`. Ids go stale: if a launch fails on an unknown model, run `$S/models.sh` and fix the config. Two more ways to pick a model:

1. **Choose at launch.** Run `$S/models.sh [kind...]` (no argument: every installed CLI). It asks each CLI for its live list. Filter with `grep -i`. Then launch with `MODEL=<id> $S/launch.sh ...`, which overrides the config for this launch only. When the user names a model ("run it on the newest codex"), resolve it this way yourself.
2. **Use a bare kind.** `launch.sh <name> $PANE codex` works with no config entry at all: the CLI starts with its own defaults. Add `MODEL=` or extra args as needed.

`models.sh` covers cursor, codex, devin, command-code, opencode, pi and grok through their listing commands. claude has none (its `--model` takes aliases or full ids, see `claude --help`); for other kinds it points you to `<cli> --help`. `herdr agent start --help` lists every supported `--kind`.

### Kind notes

One place for per-kind behaviour. Skip the lines for kinds you do not use.

- **cursor**: `--force --trust` auto-approves. May stop with `Agent stopped retrying` (connection); `prompt.sh <name> continue` resumes it. A new prompt in the same session keeps context.
- **codex**: `--approve-for-me` routes each command through a reviewer model and the sandbox still confines writes; it is not the `--dangerously-bypass-…` mode. Pass `-c` overrides (reasoning effort, service tier) in `args`; user `config.toml` may set different defaults. Confirm the settings in the welcome card. Self-updates on start (see Gotchas). A new prompt in the same session keeps context.
- **claude**: `--permission-mode auto` lets a classifier approve routine actions and block destructive ones, with no prompt. Stricter modes (`acceptEdits`, `manual`) leave the agent `blocked` on its first shell command; `watch.sh` reports that.
- **devin**: `--permission-mode bypass` auto-approves, but `DEVIN_PERMISSION_MODE` in the environment overrides argv. Trust the footer: it must say `(bypass permissions on)`; if a permission dialog appears without it, close that pane and start a new one. Never `/new` in a devin pane: it resets the permission mode and the agent hangs on approval. Start a fresh pane per task. A working devin may queue new prompts; `prompt.sh` presses Enter to flush them.
- **command-code**: headless, see the next section.

Permission rule for `args`: if the CLI has a classifier mode, use it (claude `auto`, codex `--approve-for-me`). Otherwise use full auto-approve. A mode that asks the user blocks the run.

Auto-approve (cursor `--force`, devin `bypass`, command-code `--yolo`) means no approval gate sits between the agent and `rm -rf`. The no-destruction rule in `00-context.md` (see Files, not chat) is required. Do not launch without it. If the harness you run in blocks auto-approve agents, tell the user and ask before you launch.

### command-code (headless)

`kind: "command-code"` is not a herdr agent kind, so herdr cannot see its state. Instead, each task is one `cmd -p` run in the agent's pane:

- `launch.sh` only records the pane and args in `$R/work/<name>/`. No herdr agent starts.
- `prompt.sh <name> "<task>"` writes the task to `$R/work/<name>/prompt-<n>.txt` and runs `command-code-run.sh` in the pane. Run 1 names the session `<name>` (`-n`); later runs resume it (`-r`), so follow-ups keep context.
- `watch.sh` waits for `$R/work/<name>/exit-<n>`. Exit 0 with `Status: FINAL` is DONE; any other exit is reported as EXITED. Exit 8 means the `--max-turns` cap was hit (see `cmd --help`). Other non-zero codes are reported as-is.
- Use `R=... $S/prompt.sh` (R is required). Do not use `agent_status`, `agent read`, or `prompt.sh continue` for this agent.
- `--yolo` skips every permission prompt, so the no-destruction rule applies.

## Layout

- One tab per run, never the caller's tab. Max 10 agents per tab; more → a second tab label. `grid.py` refuses an 11th pane.
- A run gets its own tab. This overrides the sibling-pane default in the `herdr` skill, which fits single-pane work.
- `grid.py` reads `$HERDR_WORKSPACE_ID`, which only exists inside a herdr pane.
- Get each agent's pane from `$S/grid.py`, never from a bare `herdr pane split`. Chained splits leave the oldest panes a few rows high.
  - `PANE=$(R=$R $S/grid.py <tab-label> --new)` adds an empty pane to that tab and creates the tab if it is missing. It then re-tiles the tab into an even grid (max 3 per row, oldest first) and prints the pane id.
  - After `herdr pane close`, run `$S/grid.py <tab-label>` so the rest fill the gap.
- Do not keep an empty "anchor" shell pane in the tab: it takes a grid cell. The tab closes with its last pane and `--new` recreates it.
- Always `--no-focus`. Parse pane ids from the JSON.
- Names: `[a-z][a-z0-9_-]{0,31}`.

## Launch

```bash
PANE=$(R=<run dir> $S/grid.py <tab-label> --new)
[MODEL=<id>] R=<run dir> $S/launch.sh <name> $PANE <agent|kind> [extra agent args...]
$S/prompt.sh <name> "<task>"
```

`launch.sh` cd's the pane to `$R` (stray relative writes land there, not in the code repo), looks up `<agent>` in the config (or accepts a bare kind) and starts it. It does not send a task. For a research run, send the standard prompt:

```text
You are agent '<name>'. Read fully: $R/00-context.md, then $R/briefs/<name>.md. Do the brief. Write the full report to $R/reports/<name>.md (file, not chat; update it as you go). Scratch files go to $R/work/<name>/. When the report is complete, make its line 2 exactly: Status: FINAL. Then reply with only the report path.
```

If agents use a browser tool, give each its own named session and forbid commands that close every session.

## Gotchas

- **Follow-ups: use `$S/prompt.sh`.** It sends the text and flushes the queued-message Enter some agents need.
- `agent_status` alone lies (idle/done while still writing, or done with a half-written report). Completion = `Status: FINAL` in the report (`$S/watch.sh`).
- **Agent CLIs may self-update on start** (for example codex: `Update ran successfully! Please restart Codex.`) and exit. `launch.sh` restarts once if the agent is gone 8 s after start. Always wait with `watch.sh`, not a file-only loop: it reports GONE.
- **Shared state.** Agents share the machine: browser sessions, ports, lock files. Give each its own session name and profile, and never run a "close all" command.
- Agents may leave background processes running. At the end: `pkill -f "$R/work/<name>/"` per agent, and check for relative-path children (`ps -axo pid,command | grep <script>`). `cleanup.sh` does the first part.

## Files, not chat

```
$R/00-context.md       goal, known facts, hard rules, report format, agent list
$R/briefs/<name>.md    one brief per agent
$R/reports/<name>.md   agent output (follow-ups: <name>-<topic>.md)
$R/work/<name>/        agent scratch scripts and outputs
$R/work/orchestrator/  your own checks (notes.md)
```

Scaffold it once before the first launch: `mkdir -p "$R"/briefs "$R"/reports "$R"/work/orchestrator`. `launch.sh` creates `$R/work/<name>` itself.

Do not put `$R` in `/tmp` or a scratch dir that a reboot wipes. Use a persistent dir, one per task (for example `<project>/runs/<task-slug>`), and reuse it for every agent in that task.

Hard rules to put in `00-context.md` (adapt to the task):

- you may run with auto-approve, so no permission prompt will stop you. Never delete, overwrite, or destroy anything you did not create this run: no `rm`, no `mv` onto existing files, no `git clean`/`reset --hard`/`checkout --`, no `kill`/`pkill` outside your own `work/<name>/` processes, no dropping/truncating files, dirs, rows, tables, or branches. If something is in the way, write beside it or stop and report;
- read-only on code repos; write only to `work/<name>/` and the report; the user may edit the repo during the run (read `git show HEAD:<path>` if a file looks half-written);
- no access to production systems; no tests, training or long jobs unless the brief allows;
- no accounts, no purchases, no signups;
- keep work files to a size the brief names (aggregate or sample large data);
- every claim with `file:line` / URL + date / command + numbers; mark `verified` / `likely` / `speculative`;
- put `Status: FINAL` on line 2 of the report only when it is complete.

## Watch

One background watcher per agent. Start it with the shell tool in background mode (`run_in_background`), never as a foreground loop:
`R=... $S/watch.sh <name> [report-basename] [timeout_s]`
It exits on DONE (report says `Status: FINAL`, changed after the watcher started, stable 15 s; it blocks on `herdr agent wait` with a 10 s timeout, so it wakes within ~10 s),
IDLE (agent not working, report stable 10 min, not final — nudge it), BLOCKED, GONE, TIMEOUT (default 90 min), or EXITED (command-code only).
Each exit also raises a herdr notification, so the user sees it without watching the tab.
That wakes you. No polling in between.

## Clean up

When a run is over, `R=$R $S/cleanup.sh` lists the processes and panes of this run. Add `--close` to stop the processes and close the panes. It resolves each pane by agent name, so panes moved by `grid.py` are still found. It never closes the orchestrator's own pane. Then re-tile the tab with `grid.py` if you keep it.

## Verify

- Give the most suspicious topic to 2 agents of different models. Overlap finds more, and disagreement shows what needs a re-check.
- `R=$R $S/collect.sh` builds `$R/index.md` from every agent and report: FINAL, WIP, or missing. It exits 0 only when all are FINAL.
- Re-check every key number yourself with a small script before it goes in the final report. Keep a "refuted" list.
- Close only panes and tabs you created, and only when the user no longer needs them.
