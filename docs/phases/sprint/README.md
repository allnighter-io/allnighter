# Sprint Work Orders

**For implementer agents (especially 32K-context models):** read **only** the
single sprint doc you were assigned. Do not read `AGENTS.md`, phase boards, or
the full driver SSOT unless the sprint doc links a specific section.

Phase docs (`docs/phases/…`) hold **law** — stable contracts. Sprint docs hold
**work orders** — one slice, explicit file allowlists, one proof command.

## When to use

| Situation | Read |
| --- | --- |
| Implement one bounded slice | **This folder** — one `*.md` work order |
| Understand full driver/feature contract | Phase SSOT (e.g. `setup/OpenCode_CLI_Support.md`) |
| Process, commits, deslop, audit | `docs/operations/Execution-Playbook.md` |

## Work order template

Each sprint file must fit on **one to two screens** and include:

1. **Goal** — one sentence
2. **Copy-paste prompt** — block for the implementer
3. **Read only** — ≤3 files (pattern references)
4. **Touch only** — explicit allowlist
5. **Do not read / do not touch**
6. **Steps** — numbered, 3–7 items
7. **Works Test** — one command
8. **Done when** — checkboxes
9. **SSOT link** — anchor into phase doc

## Rules

- **One slice = one session = one commit** (unless founder waives).
- **No scope creep.** If the slice needs another file, stop and open a new sprint doc.
- **Archive when done:** move to `docs/archive/phases/sprint/<topic>/`.
- **Status header** on each work order: `Status: ready | in_progress | done`.

## Active sprints

### Structure queue (code-maintainer — delegate via alln)

PM delegates via `alln run --model model_gemini --commit-message "..." --proof "..."`.
**PM does not edit Swift.** Stop below 10% vendor context.

| Order | Doc | Status |
| --- | --- | --- |
| CM-S06 | [effort popover extract](structure/CM-S06-effort-popover-extract.md) | **done** (`1679c5c2`, Gemini) |
| CM-S07 | [ThreadsViewModel scout](structure/CM-S07-threads-vm-scout.md) | **done** (`5bed561e`, Gemini) |
| CM-S08 | [ThreadBoardRow extract](structure/CM-S08-thread-board-row.md) | **done** (`3bd188a7`, Gemini) |
| CM-S09 | [composer attachments](structure/CM-S09-composer-attachments.md) | **done** (`d4e971bb`, Gemini) |
| CM-S10 | [ThreadsViewModel notifications](structure/CM-S10-threads-vm-notifications.md) | **done** (`95a68cc7`, Gemini) |
| CM-S11 | [ThreadsViewModel fixtures](structure/CM-S11-threads-vm-fixtures.md) | **done** (`04f1214e`, Gemini) |
| CM-S12 | [ThreadsViewModel rail](structure/CM-S12-threads-vm-rail.md) | **done** (`2d45a77c`, Gemini) |
| CM-S13 | [ThreadsViewModel attachments](structure/CM-S13-threads-vm-attachments.md) | **done** (`d9b245c3`, Gemini) |
| CM-S14 | [ThreadsViewModel run service](structure/CM-S14-threads-vm-run-service.md) | **done** (`ba1665ac`, Gemini) |
| CM-S15 | [ThreadsViewModel routing send](structure/CM-S15-threads-vm-routing-send.md) | **done** (`9e43b1f5`, Gemini) |
| CM-S16 | [ThreadMutatingRunRow extract](structure/CM-S16-thread-mutating-run-row.md) | **done** (`04983459`, Gemini) |
| CM-S17 | [thread turn indicators](structure/CM-S17-thread-turn-indicators.md) | **done** (`cd5eebcf`, Gemini) |
| CM-S18 | [AnswerBody extract](structure/CM-S18-answer-body.md) | **done** (`e76c9e5b`, Gemini) |
| CM-S19 | [ThreadTurnRow extract](structure/CM-S19-thread-turn-row.md) | **done** (`fb4eae45`, Gemini) |
| CM-S20 | [ThreadTurnTimeline extract](structure/CM-S20-thread-turn-timeline.md) | **done** (`a640f0ec`, Gemini) |
| CM-S21 | [TeamEditorView scout](structure/CM-S21-team-editor-scout.md) | **done** (`d97ba5c0`, Gemini) |

### Hygiene queue (doc truth + help fidelity — one slice per commit)

| Order | Doc | Status |
| --- | --- | --- |
| HY-S01 | [phases README vocab](hygiene/HY-S01-phases-readme-vocab.md) | **done** (`290ca0c`) |
| HY-S03 | [help loop step truth](hygiene/HY-S03-help-loop-step-truth.md) | **done** (`14200a6`) |
| HY-S04 | [contract handoff summary](hygiene/HY-S04-contract-handoff-summary.md) | **done** (`a1c7685`) |
| HY-S05 | [loop comment scrub](hygiene/HY-S05-loop-comment-scrub.md) | **done** (`5c11c0f`) |
| HY-S06 | [loop test comment scrub](hygiene/HY-S06-loop-test-comment-scrub.md) | **done** (`72ba1f5`) |
| HY-S07 | [Folder_Native_Memory vocab](hygiene/HY-S07-folder-memory-vocab.md) | **done** (`d647f7b`) |
| HY-S08 | [loop engine comment scrub](hygiene/HY-S08-loop-engine-comment-scrub.md) | **done** (`1567203`) |
| HY-S09 | [Mac GUI loop vocabulary](hygiene/HY-S09-mac-gui-loop-vocab.md) | **done** (`55a2723`) |
| HY-S10 | [loop prompt headers](hygiene/HY-S10-loop-prompt-headers.md) | **done** (`13a3717`) |
| HY-S11 | [error explain + thread titles](hygiene/HY-S11-error-explain-thread-titles.md) | **done** (`dc37276`) |
| HY-S12 | [fixture seeder titles](hygiene/HY-S12-fixture-seeder-titles.md) | **done** (`8ed1231`) |

All other work orders are archived under
[`docs/archive/phases/sprint/`](../../archive/phases/sprint/).

### Founder-blocked (archived, not active engineering)

| Order | Doc | Status |
| --- | --- | --- |
| TRR-S00 | [Growth scorecard](../../archive/phases/sprint/team-run-receipt/TRR-S00-scorecard.md) | **awaiting founder disposition** — scaffold done; does not block product |

## Recently archived (2026-08-01 cleanup)

| Topic | Location | Notes |
| --- | --- | --- |
| Team Run Receipt TRR-S00 | `archive/phases/sprint/team-run-receipt/` | Founder disposition only; TRR-S01+ already archived |
| OpenCode OC-S01b–d | `archive/phases/sprint/opencode/` | Superseded by AgentOS HTTP driver (`OpenCodeServeClient`) |
| Menu Not Router MR-S01–S06 | `archive/phases/sprint/menu-not-router/` | Complete 2026-07-20 |
| Design Lane DL-S01–S03 | `archive/phases/sprint/design-lane/` | Complete 2026-07-31 |
| Code review CR-01–CR10 + phase 2 | `archive/phases/sprint/` topic folders | Complete 2026-07-31 |
| Pair-programming PPT | `archive/phases/sprint/pair/` | Historical — slice queue deleted R-S09 |

## Creating a new work order

```text
docs/phases/sprint/<topic>/<SLICE-ID>-<short-name>.md
```

Add a row to this README. Link from the phase SSOT implementation section.
