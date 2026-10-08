# PRECONDITION

You need to install https://herdr.dev/ first

# Herdr Fleet

Run many coding agents (Devin, Codex, Cursor, …) in parallel Herdr panes under one orchestrator.
Use it to split a big research task, fan out a review, or cross-check one question on different models.

Agents report through files, not chat. Background watchers wake the orchestrator when a report is final.

## Install

Install via the [Skills CLI](https://github.com/vercel-labs/skills) (`npx skills`). Requires **Node.js 18+**, `herdr`, `python3`, `zsh`.

```bash
npx skills add Dimabytes/herdr-fleet -g --skill '*'
npx skills add Dimabytes/skills-lib -g --skill herdr   # Herdr CLI basics, the fleet loads it first
```

## Agents

The skill does not hardcode models. It reads `.herdr-fleet.config.json` in the project root, so each project has its own agents.
On first launch in a project the skill copies [`agents.example.json`](skills/herdr-fleet/agents.example.json) there. Edit that file when models change; the skill stays the same.

```json
{
  "agents": {
    "luna": {
      "kind": "codex",
      "model": "gpt-6-luna",
      "args": ["-c", "model_reasoning_effort=\"max\"", "-c", "service_tier=\"priority\"", "--approve-for-me"],
      "notes": "Local data and stats, careful cohort definitions. 35 min - 2 h."
    }
  }
}
```

| Field   | Meaning                                                  |
| ------- | -------------------------------------------------------- |
| key     | agent name you use in chat: "run it on grok and luna"    |
| `kind`  | `herdr agent start --kind` value, or `command-code` (headless `cmd -p` per task, see [SKILL.md](skills/herdr-fleet/SKILL.md)) |
| `model` | passed as `--model <model>`                              |
| `args`  | extra CLI args, one array item per argv item             |
| `notes` | what it is good at; the orchestrator picks agents by it  |

## Scripts

| Script      | What it does                                                         |
| ----------- | -------------------------------------------------------------------- |
| `launch.sh` | start an agent from `.herdr-fleet.config.json` in a pane, cwd = run dir |
| `prompt.sh` | send a task or follow-up; flushes Devin's queued-message Enter       |
| `watch.sh`  | background watcher: exits on `Status: FINAL`, idle, blocked, gone, timeout (raises a herdr notification) |
| `command-code-run.sh` | runs one headless `cmd -p` task inside a command-code agent's pane |
| `collect.sh` | run index: every agent's report status in `index.md`; exits 0 only when all are FINAL |
| `cleanup.sh` | dry run by default; `--close` stops a run's processes and closes its panes |
| `grid.py`   | tiles a run's panes into an even grid (max 10 per tab) |

## License

MIT — see [LICENSE](./LICENSE).
