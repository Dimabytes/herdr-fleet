---
name: herdr-fleet
description: Runs several coding agents in parallel in Herdr panes, each reporting through a file, and wakes the orchestrator when each agent marks its task done. Agents come from a per-project config, so any mix of supported CLIs (Claude, Codex, Cursor, Devin, Grok, command-code) works. Use when the user asks to orchestrate several models or agents via herdr, spawn N agents in herdr panes, fan out a review, cross-check one question on different models, or split a big investigation across agents.
---

# Herdr fleet

**HARD RULE, STEP 1: load the `herdr` skill (Skill tool) before anything else.** Do it before you read the config, write files, or run any script. The fleet scripts do not replace it: it holds the CLI rules this skill assumes. No exceptions, even if you plan no direct `herdr` calls.

## Run order

Copy into your todo list. Each step names the section that holds its rules.

1. Load the `herdr` skill and check `HERDR_ENV` (above).
2. Pick a persistent run dir `$R`, scaffold it, and pin the session (Files, not chat; Session pin).
3. Read `.herdr-fleet.config.json` and pick agents (Agents). For each kind you launch, read its entry in [kinds.md](kinds.md).
4. Write `$R/00-context.md` with the hard rules, then one brief per agent (Files, not chat).
5. Create panes with `grid.py`, launch, send the standard prompt (Layout; Launch).
6. Start one background watcher per agent (Watch).
7. Re-check results and build the index (Verify).
8. Stop processes and close the panes you created (Clean up).

Before any `herdr` command: `test "${HERDR_ENV:-}" = 1`. Never run bare `herdr` (it opens the TUI).

**Session pin.** Several herdr sessions can run at once, and the inherited `HERDR_*` can point to the wrong one (for example, a background job started from a pane in another session). Before the first launch, run `R=$R $S/session.py` from the project dir. It finds this agent's own pane (the agent pane whose cwd is `$PWD` or its nearest parent, in any running session) and pins it in `$R/herdr.env`. Every fleet script loads that file and stops if no single pane matches. Check that the printed pane is yours. If it fails with a tie, write `$R/herdr.env` by hand from the candidates it lists. For your own direct `herdr` calls, prefix `source $R/herdr.env;`.

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

### Kinds and permissions

[kinds.md](kinds.md) holds per-kind flags and quirks (cursor, codex, claude, devin, grok) and the headless command-code flow, which herdr cannot see and which `watch.sh` and `prompt.sh` handle differently. Read the entry for every kind you launch before you set its `args`.

Auto-approve (cursor `--force`, devin `bypass`, grok `--always-approve`, command-code `--yolo`) means no approval gate sits between the agent and `rm -rf`. The no-destruction rule in `00-context.md` (see Files, not chat) is required. Do not launch without it. If the harness you run in blocks auto-approve agents, tell the user and ask before you launch.

## Layout

- One tab per run, never the caller's tab. Max 10 agents per tab; more → a second tab label. `grid.py` refuses an 11th pane.
- A run gets its own tab. This overrides the sibling-pane default in the `herdr` skill, which fits single-pane work.
- `grid.py` uses the workspace from `$R/herdr.env` (see Session pin), so the tab lands in this agent's own session.
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
R=<run dir> $S/prompt.sh <name> [--slug <topic>] "<task>"   # prints: task #<n> sent; report: ...
```

`launch.sh` cd's the pane to `$R` (stray relative writes land there, not in the code repo), looks up `<agent>` in the config (or accepts a bare kind) and starts it. It does not send a task. For a research run, send the standard prompt:

```text
You are agent '<name>'. Read fully: $R/00-context.md, then $R/briefs/<name>.md. Do the brief. Scratch files go to $R/work/<name>/.
```

Do not name a report path or a status line in the task. `prompt.sh` gives every task a number `n` and appends a block with its report path (`$R/reports/<name>-<n>[-<topic>].md`) and the exact `finish.sh` line the agent runs when the report is complete. Keep the printed number: the watcher waits for it.

If agents use a browser tool, give each its own named session and forbid commands that close every session.

## Gotchas

- **Follow-ups: use `$S/prompt.sh`.** It sends the text and flushes the queued-message Enter some agents need. Each follow-up is a new task with its own number and report. To nudge the current task (`continue`, an answer to its question), use `prompt.sh <name> --raw "<text>"`: no new number, the watcher keeps waiting.
- `agent_status` alone lies (idle/done while still writing, or done with a half-written report). Completion = `$R/work/<name>/done-<n>`, which `finish.sh` writes (`$S/watch.sh`). Report lines and file times do not count.
- **Agent CLIs may self-update on start** (for example codex: `Update ran successfully! Please restart Codex.`) and exit. `launch.sh` restarts once if the agent is gone 8 s after start. Always wait with `watch.sh`, not a file-only loop: it reports GONE.
- **Shared state.** Agents share the machine: browser sessions, ports, lock files. Give each its own session name and profile, and never run a "close all" command.
- Agents may leave background processes running. At the end: `pkill -f "$R/work/<name>/"` per agent, and check for relative-path children (`ps -axo pid,command | grep <script>`). `cleanup.sh` does the first part. A leftover process that holds a shared lock (a GPU or CPU slot) blocks every other agent; after stopping an agent, check the lock files and kill the holder.
- **Context overflow.** A Devin footer shows `Context: N / 262k`; at 100 % it stops with `Response truncated` and cannot continue. Commits survive. Start a fresh agent (new name, same worktree and branch) with a short resume brief: its commits so far, what is left, "overwrite the WIP report". Check long runners at ~80 %.
- **Stale branch names.** A branch left from an earlier run with the same name makes worktree creation fail while launch and prompt still succeed, so the agent starts without a tree. Prefix branches per run and check the worktree exists before sending the prompt. If a remote has a branch of the same name, pass `refs/heads/<branch>` as the base.
- **Stopping a code agent early**: if its tree is clean and it has commits, merge what is committed (each commit was green); write its log line from the commit subjects. Testing-only agents can simply be stopped.

## Files, not chat

```
$R/00-context.md       goal, known facts, hard rules, report format, agent list
$R/briefs/<name>.md    one brief per agent
$R/reports/<name>-<n>[-<topic>].md   report of task n (prompt.sh names it)
$R/work/<name>/        agent scratch; prompt.sh and finish.sh keep task state here:
                       run (latest n), prompt-<n>.txt, report-<n>, done-<n>
$R/work/orchestrator/  your own checks (notes.md)
```

Scaffold it once before the first launch: `mkdir -p "$R"/briefs "$R"/reports "$R"/work/orchestrator && R=$R $S/session.py`. `launch.sh` creates `$R/work/<name>` itself.

Do not put `$R` in `/tmp` or a scratch dir that a reboot wipes. Use a persistent dir, one per task (for example `<project>/runs/<task-slug>`), and reuse it for every agent in that task.

Hard rules to put in `00-context.md` (adapt to the task):

- you may run with auto-approve, so no permission prompt will stop you. Never delete, overwrite, or destroy anything you did not create this run: no `rm`, no `mv` onto existing files, no `git clean`/`reset --hard`/`checkout --`, no `kill`/`pkill` outside your own `work/<name>/` processes, no dropping/truncating files, dirs, rows, tables, or branches. If something is in the way, write beside it or stop and report;
- read-only on code repos; write only to `work/<name>/` and the report; the user may edit the repo during the run (read `git show HEAD:<path>` if a file looks half-written);
- no access to production systems; no tests, training or long jobs unless the brief allows;
- no accounts, no purchases, no signups;
- keep work files to a size the brief names (aggregate or sample large data);
- every claim with `file:line` / URL + date / command + numbers; mark `verified` / `likely` / `speculative`;
- run the `finish.sh` line from your task only when its report is complete, and only for that task number.

## Watch

One background watcher per agent. Start it with the shell tool in background mode (`run_in_background`), never as a foreground loop:
`R=... $S/watch.sh <name> [task#] [timeout_s]`
It waits for one task: the number `prompt.sh` printed, by default the agent's latest task when the watcher starts. A later task or a late `finish.sh` of an older task never closes it.
It exits on DONE (`done-<n>` exists; checked first, so a watcher started late, restarted, or started after the pane closed still sees it; it blocks on `herdr agent wait` with a 10 s timeout, so it wakes within ~10 s),
IDLE (agent not working, no busy marker on screen, report unchanged 10 min, no finish: read the report, then nudge with `--raw`), BLOCKED, GONE, TIMEOUT (default 90 min), or EXITED (command-code only).
Each exit also raises a herdr notification (`fleet <name> #<n>`), so the user sees it without watching the tab.
That wakes you. No polling in between.

Recovery is your job. If a watcher dies, start it again with the same task number. If the agent dies before it finishes, start a fresh agent and send a new task: "Continue task #n of <old name>", the text from `$R/work/<old name>/prompt-<n>.txt`, and the path of its partial report.

In Cursor: start all watchers in one backgrounded tool shell with an output notification on `^(DONE|BLOCKED|GONE|TIMEOUT|EXITED)`; `( watch.sh ... & )` inside a normal call dies when the call ends. IDLE also fires on an agent that is only thinking for a long time, so re-run on IDLE: `while true; do o=$(watch.sh $a $n); echo "$o"; case $o in DONE*|GONE*|BLOCKED*|TIMEOUT*|EXITED*) break;; esac; sleep 30; done`.

## Clean up

When a run is over, `R=$R $S/cleanup.sh` lists the processes and panes of this run. Add `--close` to stop the processes and close the panes. It resolves each pane by agent name, so panes moved by `grid.py` are still found. It never closes the orchestrator's own pane. Then re-tile the tab with `grid.py` if you keep it.

## Verify

- Give the most suspicious topic to 2 agents of different models. Overlap finds more, and disagreement shows what needs a re-check.
- `R=$R $S/collect.sh` builds `$R/index.md`: one row per task of every agent, with the state `watch.sh` uses. FINAL (finished), WIP (report, no finish), missing, send failed, EXITED (command-code), no task. Reports no task owns show as untracked. It exits 0 only when every agent's latest task is FINAL.
- Re-check every key number yourself with a small script before it goes in the final report. Keep a "refuted" list.
- Close only panes and tabs you created, and only when the user no longer needs them.
