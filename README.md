# PRECONDITION

You need to install https://herdr.dev/ first

# Herdr Fleet

Run several coding agents in parallel Herdr panes under one orchestrator. It works with any mix of the agent CLIs Herdr supports (Claude, Codex, Cursor, Devin, and others); you only need the ones you have installed.
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
On first launch in a project the skill copies [`agents.example.json`](skills/herdr-fleet/agents.example.json) there. Every agent kind is optional, and `model` is optional too: omit it to use the CLI's default.

Model ids drift, so nothing is pinned. `scripts/models.sh` asks each installed CLI for its live model list, and `MODEL=<id> launch.sh ...` picks one at launch time. You can also launch a bare kind (`launch.sh <name> <pane> codex`) with no config entry at all.

```json
{
  "agents": {
    "codex": {
      "kind": "codex",
      "args": ["--approve-for-me"],
      "notes": "Careful analysis, long single-task runs."
    }
  }
}
```

| Field   | Meaning                                                  |
| ------- | -------------------------------------------------------- |
| key     | agent name you use in chat: "run it on codex and cursor"    |
| `kind`  | `herdr agent start --kind` value, or `command-code` (headless `cmd -p` per task, see [SKILL.md](skills/herdr-fleet/SKILL.md)) |
| `model` | optional, passed as `--model <model>`; omit for the CLI default |
| `args`  | extra CLI args, one array item per argv item             |
| `notes` | what it is good at; the orchestrator picks agents by it  |

## Scripts

| Script      | What it does                                                         |
| ----------- | -------------------------------------------------------------------- |
| `models.sh` | list the live model ids of each installed agent CLI |
| `launch.sh` | start an agent (config entry or bare kind, optional `MODEL=`) in a pane, cwd = run dir |
| `prompt.sh` | send a task or follow-up; flushes the queued-message Enter some agents need       |
| `watch.sh`  | background watcher: exits on `Status: FINAL`, idle, blocked, gone, timeout (raises a herdr notification) |
| `command-code-run.sh` | runs one headless `cmd -p` task inside a command-code agent's pane |
| `collect.sh` | run index: every agent's report status in `index.md`; exits 0 only when all are FINAL |
| `cleanup.sh` | dry run by default; `--close` stops a run's processes and closes its panes |
| `grid.py`   | tiles a run's panes into an even grid (max 10 per tab) |

## License

MIT — see [LICENSE](./LICENSE).
