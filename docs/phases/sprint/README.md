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

## Superseded Serve Continuity orders

These orders record the 2026-08-09 code floor. They are **not the active build
queue** after the 2026-08-10 fork-bomb/TCC incident. Do not resume SC-S04 or
start SC-S05. The forward contract is
[`Alln_Serve_Hotfixes.md`](../Alln_Serve_Hotfixes.md); cut exactly one ASR work
order from §8, beginning with ASR-S00.

| Topic | Doc | Status |
| --- | --- | --- |
| Serve Continuity SC-S00 | [`serve-continuity/SC-S00-launchagent-honesty.md`](serve-continuity/SC-S00-launchagent-honesty.md) | **done** — `05afee05` |
| Serve Continuity SC-S01 | [`serve-continuity/SC-S01-lifecycle-migrate-orphan.md`](serve-continuity/SC-S01-lifecycle-migrate-orphan.md) | **done** — `867d72e3` |
| Serve Continuity SC-S03 | [`serve-continuity/SC-S03-demand-heal.md`](serve-continuity/SC-S03-demand-heal.md) | **done** — `861578aa` |
| Serve Continuity SC-S04a | [`serve-continuity/SC-S04a-stable-binary.md`](serve-continuity/SC-S04a-stable-binary.md) | **done** — `ef75ec50` |
| Serve Continuity SC-S04b | [`serve-continuity/SC-S04b-enable-disable.md`](serve-continuity/SC-S04b-enable-disable.md) | **done** — `b7eecd78` |
| Serve Continuity SC-S02 | [`serve-continuity/SC-S02-install-refresh.md`](serve-continuity/SC-S02-install-refresh.md) | **done** — `5de87193` |
| Serve Continuity SC-S04 | [`serve-continuity/SC-S04-logout-login.md`](serve-continuity/SC-S04-logout-login.md) | **partial** — same-session PASS; logout deferred |

**Forward next:** ASR-S00 native launchd isolation harness. The old logout/login
order cannot close the new product claim and remains historical evidence only.

## Alln serve recovery (ASR) — active queue

SSOT: [`Alln_Serve_Hotfixes.md`](../Alln_Serve_Hotfixes.md) §8. One order at a time.

| Order | Doc | Status |
| --- | --- | --- |
| ASR-S00 | [`alln-serve/ASR-S00-launchd-isolation-harness.md`](alln-serve/ASR-S00-launchd-isolation-harness.md) | **done** — `e775d586`; matrix in [`docs/qa/alln-serve/`](../../qa/alln-serve/ASR-S00-code-identity-matrix.md) |
| ASR-S01a | [`alln-serve/ASR-S01a-canonical-binary-owner.md`](alln-serve/ASR-S01a-canonical-binary-owner.md) | **done** — `d60efa8a` (39 tests) |
| ASR-S01b | [`alln-serve/ASR-S01b-install-onto-canonical.md`](alln-serve/ASR-S01b-install-onto-canonical.md) | **done** — `91cad2de` (44 tests) |
| ASR-S01c | [`alln-serve/ASR-S01c-installer-scripts-converge.md`](alln-serve/ASR-S01c-installer-scripts-converge.md) | **done** — `fa8dc145` (16 assertions) |
| ASR-S01d | [`alln-serve/ASR-S01d-honor-home-env.md`](alln-serve/ASR-S01d-honor-home-env.md) | **done** — `1f3e1add` (50 unit + installer proof) |
| ASR-S02a | [`alln-serve/ASR-S02a-desired-state-store.md`](alln-serve/ASR-S02a-desired-state-store.md) | **done** — `aa67241f` + `e9c1b195` (20 tests) |
| ASR-S02b | [`alln-serve/ASR-S02b-canonical-plist-shape.md`](alln-serve/ASR-S02b-canonical-plist-shape.md) | **done** — `1b834ec7` (20 tests) |
| ASR-S02c | [`alln-serve/ASR-S02c-convergence-transaction.md`](alln-serve/ASR-S02c-convergence-transaction.md) | **done** — `44c897f5` (78 tests, `alln` builds) |
| ASR-S02d | [`alln-serve/ASR-S02d-live-host-rebind.md`](alln-serve/ASR-S02d-live-host-rebind.md) | **done** — `9bbf95ad` (98 tests); verify-then-delete confirmed in source |
| ASR-S02e | [`alln-serve/ASR-S02e-install-enables-by-default.md`](alln-serve/ASR-S02e-install-enables-by-default.md) | **done** — `daa3ea53` + `32051a64` (38 tests) |
| ASR-S03a | [`alln-serve/ASR-S03a-wake-safe-deadlines.md`](alln-serve/ASR-S03a-wake-safe-deadlines.md) | **done** — `96b685a6` (11 tests); failing-first observed (`14400.0 > 60.0`) |
| ASR-S03b | [`alln-serve/ASR-S03b-wake-safe-park-wake.md`](alln-serve/ASR-S03b-wake-safe-park-wake.md) | **done** — `3799cdd0` (9 tests) + [deadline inventory](../../qa/alln-serve/ASR-S03b-deadline-inventory.md) |
| ASR-S03c | [`alln-serve/ASR-S03c-default-sleeper-is-wake-safe.md`](alln-serve/ASR-S03c-default-sleeper-is-wake-safe.md) | **ready** — one symbol fixes the 7 remaining sites |

**ASR-S01 and ASR-S02 are complete.** PATH, launchd, and update now name one
canonical binary; install converges serve to the user's desired state and
migrates a host off the Application Support staged path verify-then-delete.

Carried forward:

- The `SMAppService` authorization read landed in `AllnighterCLI`, not
  `ServeLifecycle`. Fold it into the Engine when ASR-S04 touches this area so the
  Mac app can reuse it.
- `ServeStableBinary` the **type** still exists — `ServeAutoLaunch` references it
  and both die in ASR-S04. S02d retired the staged *bytes*, not the type.
- §10.1 R4 (frozen daemon) closes the first time the founder runs
  `alln install-cli`, which triggers the S02d migration.

Remaining ASR queue: rest of **S03** (active loopback health, scheduler
receipts, `ServeStatusJSON` v2, daemon-side exit contract), **S04** (delete
`ServeAutoLaunch` + app scheduler ownership, build `ServeRequirement`,
architecture gate proven by a seeded violation), **S05** (contracts, teaching,
uninstall), **S06** (host gates — 7/8/9/10 need the founder).

_None other code work orders active — CT-S04 done; archive S123 when ready._

## Recently archived (2026-08-09)

| Topic | Location | Notes |
| --- | --- | --- |
| Probe Freshness PF-S03b | [`archive/phases/sprint/probe-freshness/`](../../archive/phases/sprint/probe-freshness/) | Serve periodic full probe smoke — **done** (`fed8f447`; Works Test 13/13) |

## Recently archived (2026-08-07)

| Topic | Location | Notes |
| --- | --- | --- |
| OpenCode CT-S01–S03 | [`archive/phases/sprint/opencode/`](../../archive/phases/sprint/opencode/) | Completion-truth follow-up — **done** (unit-proven; dogfood remains on parent packet) |
| Hygiene HY-S13 | [`archive/phases/sprint/hygiene/`](../../archive/phases/sprint/hygiene/) | CapacityAcquisition hygiene — **done** (DeepSeek V4 Pro, 2026-08-07) |
| Code-maintainer structure CM-S06–S23 | [`archive/phases/sprint/structure/`](../../archive/phases/sprint/structure/) | All **done** (Gemini delegates, 2026-08) |
| Hygiene HY-S01–S12 | [`archive/phases/sprint/hygiene/`](../../archive/phases/sprint/hygiene/) | All **done** (doc/help truth, 2026-08) |

Earlier archives (2026-08-01 and before):

| Topic | Location | Notes |
| --- | --- | --- |
| Team Run Receipt TRR-S00 | `archive/phases/sprint/team-run-receipt/` | Founder disposition only; TRR-S01+ already archived |
| OpenCode OC-S01b–d | `archive/phases/sprint/opencode/` | Superseded by AgentOS HTTP driver (`OpenCodeServeClient`) |
| Menu Not Router MR-S01–S06 | `archive/phases/sprint/menu-not-router/` | Complete 2026-07-20 |
| Design Lane DL-S01–S03 | `archive/phases/sprint/design-lane/` | Complete 2026-07-31 |
| Code review CR-01–CR10 + phase 2 | `archive/phases/sprint/` topic folders | Complete 2026-07-31 |
| Pair-programming PPT | `archive/phases/sprint/pair/` | Historical — slice queue deleted R-S09 |

### Founder-blocked (archived, not active engineering)

| Order | Doc | Status |
| --- | --- | --- |
| TRR-S00 | [Growth scorecard](../../archive/phases/sprint/team-run-receipt/TRR-S00-scorecard.md) | **awaiting founder disposition** — scaffold done; does not block product |

## Creating a new work order

```text
docs/phases/sprint/<topic>/<SLICE-ID>-<short-name>.md
```

Add a row to this README. Link from the phase SSOT implementation section.
