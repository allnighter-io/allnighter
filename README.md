# Allnighter

Cross-CLI orchestration for terminal-based AI coding agents — one command
surface (`alln`) plus a native macOS app and iOS remote.

**Allnighter** coordinates Claude Code, Codex CLI, Grok, Composer, and other
subscription CLIs the user already pays for as one bench: named Teams (Spec
Review, Bug Hunt, Growth, Research, and more) for parallel judgment, and Loop
(`alln loop`) so a strong lead can steer while one mutating worker executes —
all day, attended. Despite the name, nothing here assumes overnight.

Core promise: parallel safe lanes, multi-model planning, radical privacy,
zero mandatory cloud. It never swaps your model, fakes completion, or lets two
agents edit the same repo behind your back.

Process entry point: `AGENTS.md`.

## Public (live 2026-08-13)

Strangers download from [allnighter.io](https://allnighter.io). Current floor
is **1.1.3**.

| What | URL |
| --- | --- |
| CLI | `curl -fsSL https://get.allnighter.io \| sh` |
| Mac app | https://get.allnighter.io/Allnighter.dmg |

There is no Buy button on the site. First run starts a **14-day unlimited
trial**. After that, **3 full runs/day** stay free. The 4th run is the cash
register: Mac overlay or `alln billing checkout` → hosted Stripe Checkout with
email (Builder $8/mo or $80/yr; Founding $160 once, first 100). Offer SSOT:
`docs/marketing/Pricing_Recommendation.md`. Ship SSOT:
`docs/operations/Public_Release.md`.

## For agents (Claude Code, Codex, Cursor, …): start here

You already pay for the CLIs — Allnighter puts them to work as a team instead of
you carrying messages between terminals. Before first use in a session:

```sh
alln menu --json
```

Choose from `useWhen` / `dontUseWhen`, pass canonical ids only, and run a
validation template (`--dry-run`) before unfamiliar worker-starting actions.
Never trust a pasted catalog across sessions. Cold install (no `alln` anywhere):
`curl -fsSL https://get.allnighter.io | sh`. PATH repair only (binary exists
but plain `alln` does not resolve): `alln install-cli`. Updates appear on
`alln menu --json` (`update` field) and use the same one-liner. Paste-ready
host context: `alln bootstrap`.

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

Public download + pay are live (1.1.3). Built foundation: `docs/mvp/README.md`.
Open packets: `docs/phases/README.md`. iOS remote: `docs/phases/ios/README.md`.
