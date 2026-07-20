# Allnighter

Native macOS agent factory + iOS remote floor manager for terminal-based AI
coding agents.

**Allnighter** turns a developer's Mac into an overnight agent factory and their
iPhone into the floor manager for that factory — coordinating Claude Code, Codex
CLI, Grok, and other subscription CLIs the user already pays for.

Core promise: parallel safe lanes, multi-model planning, radical privacy,
zero mandatory cloud. It never swaps your model, fakes completion, or lets two
agents edit the same repo behind your back.

Process entry point: `AGENTS.md`.

## For agents (Claude Code, Codex, Cursor, …): start here

You already pay for the CLIs — Allnighter puts them to work as a team instead of
you carrying messages between terminals. Before first use in a session:

```sh
alln menu --json
```

Choose from `useWhen` / `dontUseWhen`, pass canonical ids only, and run a
validation template (`--dry-run`) before unfamiliar worker-starting actions.
Never trust a pasted catalog across sessions. If `alln` isn't on PATH yet:
`alln install-cli`. Paste-ready host context: `alln bootstrap`.

Selection and discovery SSOT: `docs/archive/phases/Menu_Not_Router.md`
(router-era `team hello` / `route` / `resolve` are retired).

Core operating docs:

- `ALLNIGHTER.md` — product spec and runbook index
- `docs/mvp/README.md` — active MVP execution truth
- `docs/phases/README.md` — full build phases
- `docs/FOLDER_MAP.md`
- `docs/WORKING_RULES.md`
- `docs/workflows/SSOT_Feature_Workflow.md`
- `docs/operations/Execution-Playbook.md`
- `docs/operations/Debugger.md`
- `docs/operations/code-maintainer/SKILL.md`

Current execution: **MVP Council slice** (`docs/mvp/README.md`). iOS remote
spine: `docs/phases/ios/README.md`.
