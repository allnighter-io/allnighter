# Idle Stall False Kill — Hotfix

Status: **Complete** — S01+S04+S02 shipped (`6ca1e30d` / `0508120e` / `9cc93421`);
S03 posture floors deferred until telemetry. Archived 2026-07-25.
Owner: AllnighterEngine + driver manifests + CLI teaching
Updated: 2026-07-25 (IDLE-HF-S02 closeout)
Incident date: 2026-07-25

## Origin

Founder incident (design run on Opus 5 / Claude Code):

```text
The design run timed out — Opus 5 read the brief and the existing mockups,
started building, then hit the driver's default idle-stall budget. Writing a
large HTML file in one shot produces no streaming progress, so the runner
reads it as a stall. Nothing was written — full paid turn wasted.

300s is also NOT good enough for K3 reviews. They can take longer. What is
the point of killing something in flight if we know it is otherwise healthy?
This will make users furious.
```

Same disease as archived PO-F5 (`docs/archive/phases/Process_Ownership.md`):
warm workers that do legitimate silent work (tool reads, long Write, long
review) emit **zero stdout/stderr bytes** for longer than the idle budget and
get killed as `timed_out` / idle while identity-alive.

Operator workarounds (`--idle-timeout`, "write incrementally") are bandaids.
They must not become product law. Fix `alln`.

## Spec Review Min (done)

| Field | Value |
| --- | --- |
| **Run** | `902A3C9F-6021-4E4F-B4FF-F0BB7C75721B` |
| **Team** | `custom_spec_review_min_cursor_gck` |
| **Seats** | Kimi K3 (First Principles), Composer 2.5 (Proof Planner), Cursor Grok 4.5 (Scope Steward); lead Fable 5 Cursor |
| **Verdict** | **Ready** — ship amended S01; reorder backlog |
| **Clocks** | `--idle-timeout 1800 --wall-timeout 3600` |

**Lead call (locked):** Ship IDLE-HF-S01 now with two mandatory corrections the
pre-review spec would have shipped broken — the defaults table's grok row was
false (app bundle `grok.json` invoke is **300**, not 1800) and
`DefaultConfigDriftTests` never compares `timeoutSeconds` — then reorder to
**S01 → S04+telemetry → scoped S02 → S03**, because S02's fs/child signals
cannot witness the one-shot Write kill window they claimed to fix.

## Product lie

Idle progress-truth today effectively means **stream bytes** (plus external
`recordProgress` heartbeat touches). Help text claims resets on
"tool-call/reasoning/stderr/child activity" — stream bytes cover tool JSON
when the vendor emits them; **silent internal work and one-shot large Writes
do not**. Code does **not** observe child activity today
(`ContractRegistry+Milestone1.swift` FlagSpec for `idle-timeout` still claims
it). Killing an identity-alive healthy worker mid-flight wastes tokens the
user already paid for and destroys trust.

## Current defaults (verified 2026-07-25)

Two truth owners must stay in sync. Mac app prefers **App Drivers** when the
bundle loads; `DefaultConfig` embedded strings are the safety net.

| Driver | App Drivers `invoke.timeoutSeconds` | `DefaultConfig` embedded | Streaming? | Semantics of the knob |
| --- | ---: | ---: | --- | --- |
| `kimi` | **1800** | **1800** | yes | Idle (rolling stall) — already honest |
| `grok` | **300** | **1800** | yes | Idle — **live drift**; App Drivers win → Grok seats die at 300 |
| `claude_code` | **600** | **300** | yes | Idle — live drift; both too short for Opus design |
| `codex` | **300** | **300** | yes | Idle — too short |
| `cursor_agent` | **300** | **300** | yes | Idle — too short |
| `opencode` | **600** | **600** | yes | Idle — too short; omitted from pre-review raise list |
| `antigravity` | **300** | **300** | **no** | **Total** wall-style cap (no streaming stall path) — not an idle budget |
| `manual_paste` | — | — | no | Out of scope |

Other clocks (leave alone in S01 unless noted):

| Clock | Value | Notes |
| --- | ---: | --- |
| Wall (`RunClockDefaults.wallTimeoutSeconds`) | **3600** | Hard ceiling; keep |
| Streaming-path total backstop (`SubprocessBudget.default`, AgentOS) | **3600** | Wall-aligned; does not pre-empt 1800 idle |
| Help / `ContractRegistry` idle FlagSpec | "typically 300" + "child activity" | Both lies — rewrite in S01 |
| `imageGen.timeoutSeconds` (where present) | 600 | Non-streaming total on a different job — **do not** raise in S01 |

Code SSOT pointers:

- Idle budget: driver `invoke.timeoutSeconds` → `RunRequest.workerTimeoutSeconds` / `ProcessGroupCommandRunner` stall watchdog
- Progress: `ProcessGroupCommandRunner` + `ProcessOwnership.classifyProgressStall` / `recordProgress`
- Wall / clocks: `RunClockDefaults`, `RunClockEnforcer`
- Drift guard (incomplete today): `DefaultConfigDriftTests` — asserts command/args only, **not** `timeoutSeconds`
- Override flag: `alln run --idle-timeout` / `--wall-timeout` (PO-F5 / RLR-L8) — remains override, not primary UX
- Teaching: `ContractRegistry+Milestone1.swift` FlagSpec for `idle-timeout`; regenerate `docs/generated/alln/*`

## Non-goals

- Do not ban Opus (or any seat) from design because of false stalls.
- Do not require agents to "write incrementally so the watchdog is happy."
- Do not make `--idle-timeout` the primary UX for design/review.
- Do not disable idle detection entirely (true hangs must still die).
- Do not raise wall in S01; do not raise `imageGen.timeoutSeconds` in S01.
- Do not mix broad RLR refactors into the bleed-stop slice.
- Do not watch shared repo/cwd filesystem activity as progress (unattributable
  across parallel research Teams — masks true hangs).

## Ship order (locked)

```text
IDLE-HF-S01  bleed stop + drift guard + honest teaching     ← implement now
IDLE-HF-S04  kill-policy demotion + silence telemetry         ← next
IDLE-HF-S02  attributable process-group progress (gated)      ← after telemetry
IDLE-HF-S03  posture floors (deferred — likely shorter chat)  ← from data
```

---

### IDLE-HF-S01 — Bleed stop: raise idle floors + sync + teach + drift guard

**Authorized now. Ship first. Implementation-ready.**

#### Touch

- `Apps/AllnighterMac/Resources/Drivers/{claude_code,codex,grok,cursor_agent,antigravity,opencode}.json`
- `Packages/AllnighterCore/Sources/AllnighterEngine/DefaultConfig.swift` (embedded manifests for the same six)
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/DefaultConfigDriftTests.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift` (`idle-timeout` FlagSpec on `run`; regen contracts)
- Generated: `docs/generated/alln/*` via `alln dev export-contracts`

Leave `kimi` at 1800. Leave `imageGen.timeoutSeconds` alone. Leave wall / `SubprocessBudget.default` at 3600.

#### Steps

1. **Raise / sync six drivers to `invoke.timeoutSeconds: 1800` in both truth owners:**
   - `claude_code`, `codex`, `cursor_agent`, `antigravity`, **`grok` (App Drivers)**, **`opencode`**
   - After edit, App Drivers and `DefaultConfig` must agree on every headless driver's `invoke.timeoutSeconds`
2. **Keep wall at 3600.** Document in closeout that `SubprocessBudget.default` is already 3600 (wall-aligned) — no change.
3. **Antigravity note (in commit message / this doc only):** raising its 300→1800 lengthens a **total** cap (no streaming block), not an idle budget. Same disease class for the user (false kill of healthy long work); different knob semantics — do not claim "idle" for it in help.
4. **Teaching (same slice):**
   - Rewrite the `run --idle-timeout` FlagSpec: drop "typically 300"; drop the "child activity" claim until a later slice actually observes children
   - Preferred wording: default = driver manifest `invoke.timeoutSeconds` (commonly 1800s for agent CLIs after this slice); resets on streaming stdout/stderr bytes and durable `recordProgress` heartbeats; wall is the hard ceiling (`--wall-timeout`, default 3600)
   - Prefer generating the idle summary from live manifest values if a one-liner helper already exists; otherwise honest static prose is enough for S01
   - `alln dev export-contracts` so `docs/generated/alln/*` matches
5. **Drift guard (blocking):** extend `DefaultConfigDriftTests.testEmbeddedManifestsMatchBundledCoreFields` (or add a sibling test) to assert:
   ```swift
   XCTAssertEqual(bundled.invoke?.timeoutSeconds, embedded.invoke?.timeoutSeconds)
   ```
   for every embedded/bundled pair. This is the gap that let grok 300 vs 1800 and claude 600 vs 300 ship.
6. **Closeout fact check:** locate the 2026-07-25 Opus design incident run journal and record which clock fired (`timeoutKind: idle` vs wall vs firstActivity). S01 is still correct under either reading; the journal closes the open flag.

#### Proof (S01)

```bash
# 1. Red first (optional before edits): new timeoutSeconds assertion fails on today's grok/claude drift
swift test --package-path Packages/AllnighterCore --filter DefaultConfigDriftTests

# 2. After both-owner edits: drift + idle + stall + clock suites green
swift test --package-path Packages/AllnighterCore \
  --filter 'RunIdleTimeoutTests|ProcessOwnershipProgressStallTests|DefaultConfigDriftTests|RunClockEnforcerTests'

# 3. Spot-check both owners decode to 1800 for the six raised drivers
rg '"timeoutSeconds": 1800' \
  Apps/AllnighterMac/Resources/Drivers/{claude_code,codex,grok,cursor_agent,antigravity,opencode}.json
# DefaultConfig: each of those six ids must carry "timeoutSeconds":1800 on invoke

# 4. Teaching regenerated and honest
alln dev export-contracts
rg -n 'typically 300|child activity' \
  docs/generated/alln/ \
  Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift
# expect: no matches on the run idle-timeout FlagSpec / generated help

# 5. Works Test: identity-alive + zero stream bytes survives past the old budget (<1800);
#    total silence past 1800 still times out; wall still caps at 3600
swift test --package-path Packages/AllnighterCore --filter RunIdleTimeoutTests
```

**Done when:** no healthy Opus design / K3 / Grok / Composer seat needs a hero `--idle-timeout` just to survive quiet tool work under default dispatch; both truth owners agree; drift test would have caught today's grok/claude mismatch; help no longer claims child activity or "typically 300."

---

### IDLE-HF-S04 — Kill policy demotion + silence telemetry

**Shipped 2026-07-25.** Telemetry owner: `RunJournalSilenceTelemetry` + `alln doctor silence [--json]`.

#### Why ahead of S02

A one-shot large Write emits **no** filesystem, CPU, or child signal during the
generation window that already killed the incident — those signals appear only
when the write lands. Raising the floor (S01) and refusing to murder
identity-alive workers lightly (S04) buy the window; S02 cannot witness the
incident as written.

#### Steps

1. **Demote idle-kill** for identity-alive workers: idle remains a stall detector,
   but prefer surfacing state over immediate kill when the owner identity is
   still alive — wall stays the true hard stop.
2. **Surface silence** in `alln ps` / status JSON (and GUI if a one-line field
   already exists): `identity-alive, no stream for Ns` (reuse
   `lastProgressAt` / `progressStale` — do not invent a second clock).
3. **Telemetry slice (same or tight follow-on):** mine run journals for
   `timeoutKind: idle` (and related `RunTimingReport` if present) → per-driver
   silence-duration histograms. This stops re-litigating 1800 at the next
   incident and feeds S02/S03 go/no-go.

#### Proof (S04)

- Unit/integration: identity-alive + frozen progress past idle budget is either
  (a) still reaped only at wall under the new policy, or (b) reaped at idle
  **and** the ps/status surface showed the silence flag before kill — pick one
  behavior in the slice and test it.
- Telemetry: a dry command or test fixture that classifies at least one journaled
  idle timeout into the histogram shape.

**Done when:** users/agents can see "still alive, quiet for Ns" before/at idle
kill; wall is the documented hard stop; we have field silence data for the next
floor decision.

---

### IDLE-HF-S02 — Attributable process-group progress (gated)

**Authorized only after S01 + enough S04 telemetry to show residual false kills.**

Idle may reset on signals that are **attributable to this run's owner process
group** (recorded pgid / identity):

1. Process-group CPU / IO / new children under the owned pgid
2. Keep stream bytes as the fast path for chatty workers
3. Optional later: file activity **only** if it can be attributed to this
   worker/pgid (not shared repo cwd mtime)

**Explicitly out of scope for S02:** repo-level / working-directory filesystem
watching. Parallel research Teams share the repo root — unattributable cwd
activity masks true hangs and was rejected in Spec Review.

Guard: do not invent fake progress prose for the GUI. This is watchdog truth only.

**Works Test:** worker under recorded pgid shows attributable activity with no
stdout for > old budget → not reaped; frozen process with no stream/pgid
activity → still reaped near budget; a second process writing in the same repo
cwd must **not** keep a hung owner alive.

**Done when:** help may honestly claim child/process-group activity; residual
post-S01 false kills from silent-but-busy tool work drop in telemetry.

---

### IDLE-HF-S03 — Posture floors (deferred)

**Deferred.** After S01 the driver default is 1800 for the raised set, so the
pre-review table (design/review ≥ 1800) is a **no-op**.

Open question for later, decided from S04 telemetry:

| Posture / job | Candidate | Gate |
| --- | --- | --- |
| Design / review / mutating execute | keep ≥ 1800 (or raise further if silence histograms demand) | Field idle-kill rate still high after S01 |
| Chat / quick | possibly a **shorter** posture floor | Telemetry shows chat does not need 1800 and hangs linger too long |

Flags remain overrides. Do not implement S03 until S04 histograms exist.

---

## Explicitly rejected

| Idea | Why reject |
| --- | --- |
| Standing rule: never retry Opus design; fall back to Cursor Grok only | Operator trauma policy, not a product fix |
| Prompt law: always write files incrementally | Papers over a false stall; hurts craft quality |
| Only document `--idle-timeout` louder | Users will still forget; agents will still burn turns |
| S02 fs/child as "the real fix" for the incident | One-shot Write emits nothing during generation; signals fire after the work completes |
| Repo/cwd-level fs watching as progress | Parallel research Teams share the repo root; unattributable; masks true hangs |
| Raising wall or disabling idle in S01 | Wrong clock / non-goal; wall and `SubprocessBudget.default` already 3600 |
| Raising `imageGen.timeoutSeconds` in S01 | Different job, total cap, no field evidence — decide explicitly later |

## Related

- Archived diagnosis: `docs/archive/phases/Process_Ownership.md` (PO-F5)
- Clocks: archived `docs/archive/phases/Run_Lifecycle_Reliability.md` + code `RunClockEnforcer.swift`
- Prior slow-review threshold work: `docs/phases/sprint/watchdog/WATCHDOG-S01-slow-glm-threshold.md` (pair/advisory detector — different layer; do not conflate)
- Spec Review Min run: `902A3C9F-6021-4E4F-B4FF-F0BB7C75721B` (team `custom_spec_review_min_cursor_gck`)

## Closeout

When S01 ships: update this status line + phases board; record which clock the
incident journal shows; leave manifests + drift test as SSOT for defaults.
**S01 closeout (2026-07-25):** Opus design incident journal not found in-repo;
likely `timeoutKind: idle` per founder report (600s claude_code invoke budget).
**S04 closeout (2026-07-25):** Identity-alive owners are not idle-reaped in
`ProcessGroupCommandRunner`; silence surfaces via `silenceStatus` on `alln ps --json`
and team status; field histograms via `alln doctor silence`. **S02 closeout
(2026-07-25):** Streaming stall watchdog samples the recorded pgid for child
spawn / CPU / IO and resets progress via `pgid_activity`; repo cwd mtimes are
explicitly excluded. **Archived 2026-07-25** — code SSOT:
`DefaultConfig` + App Drivers `invoke.timeoutSeconds` (1800), `DefaultConfigDriftTests`,
`ProcessGroupCommandRunner` stall watchdog + `ProcessOwnership.sampleProcessGroupActivity`,
`alln doctor silence`. S03 posture floors stay deferred until field data.
