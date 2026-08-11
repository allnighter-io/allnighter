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
| ASR-S03c | [`alln-serve/ASR-S03c-default-sleeper-is-wake-safe.md`](alln-serve/ASR-S03c-default-sleeper-is-wake-safe.md) | **done** — `4edd61be` (37 tests); zero scheduler files edited |

| ASR-S03d | [`alln-serve/ASR-S03d-active-health-handshake.md`](alln-serve/ASR-S03d-active-health-handshake.md) | **done** — `ff90583b` + wiring fix `0612b8ec` (25 tests) |
| ASR-S02f | [`alln-serve/ASR-S02f-bootout-settle-and-honest-restore.md`](alln-serve/ASR-S02f-bootout-settle-and-honest-restore.md) | **done** — live host 10/10 (baseline 2 failures in 6); **unit tests unrun, XCTest unavailable** |
| ASR-S06a | [`alln-serve/ASR-S06a-crash-restart-host-proof.md`](alln-serve/ASR-S06a-crash-restart-host-proof.md) | **done** — `7850d38a`; gate 3 run and it **FAILED**, finding ASR-S06b; harness stdout bug fixed in `476e9d80` |
| ASR-S06b | [`alln-serve/ASR-S06b-sigterm-must-restart.md`](alln-serve/ASR-S06b-sigterm-must-restart.md) | **done** — `555f72a8` + PM fixup `476e9d80`; **gate 3 now PASSES** (24 assertions). Composer committed a non-compiling build then hit vendor `resource_exhausted` twice |
| ASR-S06c | [`alln-serve/ASR-S06c-update-identity-host-proof.md`](alln-serve/ASR-S06c-update-identity-host-proof.md) | **done** — `978c6b95` (Composer 2.5); gate 4 **update half PASSES**, rollback half pending ASR-S06d |
| ASR-S06d | [`alln-serve/ASR-S06d-rollback-injected-bootstrap-failure.md`](alln-serve/ASR-S06d-rollback-injected-bootstrap-failure.md) | **done** — `f872ab00` (Composer 2.5, 81 tests, real failing-first); gate 4 rollback half run and it **FAILED**, finding ASR-S06e |
| ASR-S06h | [`alln-serve/ASR-S06h-cold-install-clean-home.md`](alln-serve/ASR-S06h-cold-install-clean-home.md) | **done** — `abcafaa7` (Terra); cold install + `--no-serve`; **found the P0 below** |
| ASR-S06i | [`alln-serve/ASR-S06i-serve-lifecycle-refuses-foreign-home.md`](alln-serve/ASR-S06i-serve-lifecycle-refuses-foreign-home.md) | **done** — `3d6a0187` (Terra); `SERVE_FOREIGN_HOME`, verified live |
| ASR-S06f | [`alln-serve/ASR-S06f-identity-and-receipts-gates.md`](alln-serve/ASR-S06f-identity-and-receipts-gates.md) | **done** — `c07375bf`; gates 2 and 5 harness |
| ASR-S06g | [`alln-serve/ASR-S06g-idle-scheduler-is-not-a-failure.md`](alln-serve/ASR-S06g-idle-scheduler-is-not-a-failure.md) | **done** — `015dda39` + `4dec32de` + PM fixup `5cc977e9`; **gates 2 and 5 PASS** |
| ASR-S06e | [`alln-serve/ASR-S06e-restore-the-binary-on-failed-install.md`](alln-serve/ASR-S06e-restore-the-binary-on-failed-install.md) | **done** — `8f9637c0` (Composer 2.5, 108 tests, real failing-first); **gate 4 now PASSES both halves** |
| ASR-S03f4 | [`alln-serve/ASR-S03f4-daemon-not-yet-reported-is-starting.md`](alln-serve/ASR-S03f4-daemon-not-yet-reported-is-starting.md) | **done** — `a26de6fe`; live host 6/6 `starting` then healthy (baseline 6/6 degraded); **unit tests unrun, XCTest unavailable** |
| ASR-S03e | [`alln-serve/ASR-S03e-scheduler-receipts.md`](alln-serve/ASR-S03e-scheduler-receipts.md) | **done** — `254cfeae` (26 tests) |
| ASR-S04a | [`alln-serve/ASR-S04a-delete-autolaunch-build-requirement.md`](alln-serve/ASR-S04a-delete-autolaunch-build-requirement.md) | **done** — `6bacc609` (Grok 4.5, 25 files, 82 tests) |
| ASR-S04a2 | [`alln-serve/ASR-S04a2-gate-pending-wake.md`](alln-serve/ASR-S04a2-gate-pending-wake.md) | **done** — `69d2f1f8` + data-loss fix `ddb039ef` (77 tests) |

| ASR-S04b | [`alln-serve/ASR-S04b-architecture-gate.md`](alln-serve/ASR-S04b-architecture-gate.md) | **done** — `4403ab3d` (3 rules, 3 seeded failures + 3 legitimate fixtures; no Swift changed) |

**ASR-S04 is complete.** Detached auto-launch is deleted and deny-listed,
`ServeRequirement` gates deferred obligations, the app owns no serve lifecycle
or periodic scheduling, and the architecture gate is proven able to fail.

**Seat note:** DeepSeek dropped one run on S04b with `incomplete_no_final_message`
(driver-level stream truncation, no repo change) and succeeded on retry. Founder
2026-08-11: use **Composer 2.5** (`model_cursor_composer_25`) for med/easy work
if DeepSeek fails again — do not retry the same order a third time.

**S04a2 lesson — do not repeat.** The work order said "assert the store is
byte-for-byte unchanged on refusal." That is right when the gate *precedes* the
work (an `add`) and **wrong** when it *follows* it. The seat correctly relocated
the gate to `settleRun`/`settleTeamRun` (the real `resume.wakeAfter` writer) but
carried the assertion along, so a refusal discarded a completed run's attempt
outcome and left a stale lease — and 77 tests defended it, because they encoded
the wrong requirement. Queue honesty means *do not queue work no daemon will
claim*; it never means *discard the result of work already done*. Correct shape:
clear the obligation, **save**, then throw.

**S04a §2.3 audit result** (Grok's own table, reported honestly):
Loop `--delivery wake` **gated**; attended loop/run **not gated** (correct);
Boost seed, notifications, cloud relay **attended, not gated**;
**Pending wake — gap, now S04a2**; vendor-backoff **deliberately not gated** —
a park is mid-run durable state during attended work, so gating it would veto a
live run. That last call is better than the work order implied and stands.

Still open in ASR-S03: **S03e2** per-scheduler attempt/success/error (receipts
currently prove registration, not progress) and **S03f** `ServeStatusJSON` v2.

**Live-host milestone:** the first `rebuild_cli.sh` → `install-cli` on the
founder's Mac ran the S02d migration for real and closed §10.1 R4. Record:
[`docs/qa/alln-serve/2026-08-11-live-host-migration.md`](../../qa/alln-serve/2026-08-11-live-host-migration.md).

**Slice sizing (founder 2026-08-10):** S03c carried four deliverables and ran
~13 min with no visible progress, which reads as hung. Cap a routed order at
~2 deliverables; a failing-first test counts as one. The rest of ASR-S03 is
split accordingly: **S03d** active loopback health, **S03e** scheduler receipts,
**S03f** `ServeStatusJSON` v2.

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
