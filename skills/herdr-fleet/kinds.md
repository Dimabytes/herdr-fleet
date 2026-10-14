# Agent kinds

Per-kind behaviour and permission flags. Read the entries for the kinds you are about to launch; skip the rest.

Contents: cursor, codex, claude, devin, grok, command-code (headless), permission rule.

## cursor

`--force --trust` auto-approves. May stop with `Agent stopped retrying` (connection); `prompt.sh <name> --raw continue` resumes it. A new prompt in the same session keeps context. A prompt sent while it works goes to a follow-up queue and waits until the whole task ends; a second Enter (`enter steer`) delivers it at the next step. `prompt.sh` presses that Enter.

## codex

`--approve-for-me` routes each command through a reviewer model and the sandbox still confines writes; it is not the `--dangerously-bypass-…` mode. Pass `-c` overrides (reasoning effort, service tier) in `args`; user `config.toml` may set different defaults. Confirm the settings in the welcome card. `launch.sh` adds a `-c projects=...trust_level="trusted"` override for the run dir's repo, so codex skips its "Trust this folder?" dialog (session only, not saved). Self-updates on start (see Gotchas in SKILL.md). A new prompt in the same session keeps context.

## claude

`--permission-mode auto` lets a classifier approve routine actions and block destructive ones, with no prompt. Stricter modes (`acceptEdits`, `manual`) leave the agent `blocked` on its first shell command; `watch.sh` reports that.

## devin

`--permission-mode bypass` auto-approves, but `DEVIN_PERMISSION_MODE` in the environment overrides argv. Trust the footer: it must say `(bypass permissions on)`; if a permission dialog appears without it, close that pane and start a new one. Never `/new` in a devin pane: it resets the permission mode and the agent hangs on approval. Start a fresh pane per task. A working devin may queue new prompts; `prompt.sh` presses Enter to flush them. A prompt sent right after start can be lost; `prompt.sh` resends once.

## grok

Use `--always-approve` (footer: `always-approve`). `--permission-mode auto` (footer `auto-review`) is a classifier, but it blocks at random: it let an edit of `~/.zshrc` through, then stopped on the run's own `finish.sh`, which passed in two earlier tasks. A blocked agent stalls the run until someone answers. `--effort high` (alias `--reasoning-effort`) sets the reasoning effort. A new prompt in the same session keeps context.

Long shell commands run as background tasks. Then herdr reports `done` while the screen shows `1 command still running · send a message to interrupt`, and grok continues by itself when the command ends. `watch.sh` treats that line as busy. Do not send a prompt or a `--raw` nudge then: a message interrupts the command.

## command-code (headless)

`kind: "command-code"` is not a herdr agent kind, so herdr cannot see its state. Instead, each task is one `cmd -p` run in the agent's pane:

- `launch.sh` only records the pane and args in `$R/work/<name>/`. No herdr agent starts.
- `prompt.sh <name> "<task>"` writes the task to `$R/work/<name>/prompt-<n>.txt` and runs `command-code-run.sh` in the pane. Run 1 names the session `<name>` (`-n`); later runs resume it (`-r`), so follow-ups keep context.
- `watch.sh` waits for `$R/work/<name>/exit-<n>`. Exit 0 with `done-<n>` from `finish.sh` is DONE. Exit 0 without it is EXITED `0-nofinish`; a non-zero exit is EXITED with its code. Exit 8 means the `--max-turns` cap was hit (see `cmd --help`). Other non-zero codes are reported as-is.
- Do not use `agent_status` or `agent read` for this agent. `prompt.sh --raw` refuses it: every prompt is a new run, so send a new task.
- `--yolo` skips every permission prompt, so the no-destruction rule applies.

## Permission rule

For `args`: if the CLI has a classifier mode, use it (claude `auto`, codex `--approve-for-me`). Otherwise use full auto-approve (cursor `--force`, devin `bypass`, grok `--always-approve`, command-code `--yolo`). grok has a classifier mode, but it blocks at random (see grok). A mode that asks the user blocks the run.
