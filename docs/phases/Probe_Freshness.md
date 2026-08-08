# Probe Freshness — the bench must not hide a working seat

Status: **Draft v1 — Spec Review Min pending. No slice authorized.**
Owner: AllnighterCore (`SourceProbeService`, `DriverListProjector`,
`MenuCatalog`, `DoctorReport`, `DispatchReadiness`); `alln serve` for PF-S03
Created: 2026-08-08
Origin: Founder dogfood 2026-08-08 — `alln menu --json` reported Grok and Kimi
as `notReady` / "Rate limited — resets Aug 14" while both CLIs answered a live
prompt in the same minute. Founder: *"why on launch alln menu is LYING."*

Companion packets:
[`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) (a signal answers
only for the source that produced it — PF-S02 is that packet's missing Works
Test), [`Capacity_Warm_Bench.md`](Capacity_Warm_Bench.md) (owns the 30-minute
freshness clock and the Dock schedule PF-S03 re-homes),
[`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md)
(runtime park/substitution — must not consume an expired verdict).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

---

## 1. Defect

`alln menu --json` and `alln drivers --json` report working seats as unavailable,
with an invented reason and an unrelated date, and the report cannot age out.

### 1.1 Live probe (2026-08-08 13:22 UTC, dogfood host)

| Probe | Result |
| --- | --- |
| `grok -p "reply with exactly: OK"` | **`OK`** — works (`grok 1.0.0 (3cd0d0cb)`) |
| `kimi -p "reply with exactly: OK"` | **`OK`** — works (`kimi 0.34.0`) |
| `alln drivers --json` → `grok` | `notReady` · *"Rate limited — resets Aug 14, 2026 at 11:11 AM"* |
| `alln drivers --json` → `kimi` | `notReady` · *"Rate limited — resets Aug 14, 2026 at 12:14 PM"* |
| `alln menu --json` → `model_grok`, `model_kimi_k3`, `model_kimi_k27` | `ready: false` · `blockedReason: "Source not ready"` |

Three seats removed from the bench. Both CLIs were working the whole time.

### 1.2 Cost

The damage is **asymmetric**, and that asymmetry is the design driver:

| Wrong verdict | Cost |
| --- | --- |
| Stale `ready` on a dead CLI | One failed run. Loud, immediate, self-correcting. |
| Stale `notReady` on a live CLI | A seat the user pays for disappears from selection, silently, until a human happens to disagree with the tool. |

Here it cost two days of Grok and Kimi, and was found only because the founder
contradicted the menu from memory. Mission damage: *you already pay for the
team* — and the bench quietly sent two of them home.

---

## 2. Root cause — four layers

### 2.1 The freshness data exists and nothing reads it

`ToolProbeRecord.lastProbeAt` **is** persisted. Every record in
`~/Library/Application Support/Allnighter/Config/cli_setup.json` carries
`"lastProbeAt": "2026-08-06T22:55:24Z"` — 38 hours stale at probe time.

```
grep -rn "lastProbeAt" Packages/AllnighterCore/Sources
→ CensusIngest.swift:47   (writes it)
→ (no other hit)
```

**One writer, zero readers.** The timestamp needed to make every surface honest
is already on disk. Nothing consults it, nothing expires on it, nothing shows
it. This makes the fix small.

### 2.2 The probe cache is immortal on the fast path

`SourceProbeService.swift:214–216`:

```swift
let cached = previous.records.filter { headlessIds.contains($0.driverId) }
if cached.count == headlessIds.count, !cached.isEmpty { return cached.sorted { … } }
```

If every headless driver has a record, the whole cache is returned. No TTL, no
`lastProbeAt` check, no `retryAfterSeconds` check. Only `--full` re-probes.
`cli_setup.json` was last written **Aug 6 15:56** and could not have aged out on
its own.

Independent corroboration: cached `grok` version is `0.2.118`; the binary on
PATH is `1.0.0`. `DispatchReadiness.invalidateStaleVersions` exists precisely to
self-heal this (its doc comment names the grok version-drift case), but it is
called only from `RunService:334` (dispatch) and `SourceProbeService:152` —
and the latter applies it **only to parked drivers inside `detect()`**. The
menu / drivers / models path never gets it.

### 2.3 The verdict was inferred, not observed

Both cached records:

```
kimi: kind=rateLimited  sourceConfidence=localPolicy  retryAfterSeconds=3600
      observedAt=2026-08-06T22:55:47Z  rawSnippet="kimi version 0.34.0"
grok: kind=rateLimited  sourceConfidence=localPolicy  retryAfterSeconds=3600
      observedAt=2026-08-06T22:55:50Z  rawSnippet="Internal error: {"
```

`sourceConfidence: localPolicy` means **Allnighter guessed**. No vendor stated a
limit. Grok's entire evidence is a truncated crash string; Kimi's is its own
version banner. And `retryAfterSeconds: 3600` — the observation's own stated
validity — expired 37 hours before it was rendered as current fact.

This breaks three project laws at once: *absence of a declared signal yields no
observation, never an inferred one*; *a locally computed value is never
presented as a vendor-stated fact*; *a derived signal is attributed to the
source that produced it*.

### 2.4 Two sources spliced into one confident sentence

`DriverListProjector.swift:68` passes a `vendorReset` into
`DoctorReport.rateLimitedDetail(observation:vendorReset:)`. That reset comes
from `Capacity/grok.json`'s newest weekly window — a window reading
**`peakUsedPercent: 5`**, i.e. 5% consumed, not limited.

So the rendered sentence *"Rate limited — resets Aug 14, 2026 at 11:11 AM"* is:

```
"Rate limited"     ← a 38h-old localPolicy guess from a crash string
"resets Aug 14…"   ← a reset date from an unrelated, 5%-used capacity window
```

Note `rateLimitedDetail` refuses to use the observation's own reset when
confidence is `localPolicy` (it would say *"reset time unknown"*). The
`vendorReset` parameter routes around that guard. The guard was right; the
splice defeated it.

### 2.5 Scope — this is a selection bug, not a dispatch bug

`DispatchReadiness` already enforces the founder law that derived readiness
informs but never blocks: `hardBlockReason` consults only park / disabled /
unknown-id / write-lock, never the probe cache. So `alln run --model model_grok`
would likely have worked all along.

The lie lives entirely in the **selection surfaces** — `menu`, `drivers`,
`models`. Which is worse than it sounds: an agent reading `alln menu --json`
sees `ready: false` and **never attempts the run**. A sensor that informs
selection by stating a false fact does not inform selection; it silently
subtracts seats. That is the letter of the law honored and its intent broken.

---

## 3. Product law (candidate)

1. **A verdict carries its own age.** Every readiness verdict a selection
   surface emits also emits when it was taken. `lastProbeAt` already exists;
   surface it.
2. **An expired verdict is not a verdict.** Past `retryAfterSeconds`, or past
   the freshness clock, the record yields `unknown` — not its last known value.
3. **Staleness may never rank a seat below `unknown`.** A stale positive may
   decay to `unknown`; a stale negative must *also* decay to `unknown`. An old
   negative verdict may never hide a seat. (§1.2 asymmetry.)
4. **No verdict without a declared signal.** `sourceConfidence: .localPolicy`
   may report `probeFailed`; it may never report `rateLimited`. A vendor limit
   is a vendor-printed fact or it is not a fact.
5. **One sentence, one source.** A reset time from capacity history may not be
   attached to a limit verdict produced by a probe. If the observation cannot
   name its own reset, the copy says so.
6. **Scheduled refresh belongs to `alln serve`.** Freshness must not depend on
   a SwiftUI view appearing.

---

## 4. Slice plan

PF-S00 and PF-S02 stop the lie and are independent of each other. PF-S01 is the
founder's disclosure. PF-S03 is the structural fix and can run in parallel —
different files, different owner.

### PF-S00 — Expire the verdict

**Scope:** `SourceProbeService` fast path honors freshness. A record whose
`lastProbeAt` is older than the freshness clock, or whose `retryAfterSeconds`
has elapsed, is not returned as fact. Reuse the **existing 30-minute clock**
from `Capacity_Warm_Bench.md` — do not introduce a second freshness constant.

Expired ⇒ `installedNotProbed` (or an explicit `unknown`), never `notReady`,
never `rateLimited`. Also feed `invalidateStaleVersions` on this path so a
version-drifted record self-heals as it already does at dispatch.

**Works Test:**
```
Given: a cached record with status=rateLimited, retryAfterSeconds=3600,
       lastProbeAt = now - 38h
When:  alln drivers --json / alln menu --json
Then:  the driver is NOT reported notReady for a rate limit
And:   its models are not blockedReason "Source not ready"
And:   the surface states the verdict is unknown / not recently checked
```

### PF-S01 — Disclose age on every selection surface

**Scope:** `menu`, `drivers`, `models` JSON each carry `checkedAt`,
`ageMinutes`, and `stale: true` past the clock, plus a `nextAction` naming the
refresh command. Structured first — a human-only banner leaves every agent
reading `--json` believing the stale value.

Past the threshold the surface **stops asserting** rather than asserting
louder (law 3). Contract change ⇒ `contractVersion` bump per the version rule.

**Works Test:**
```
Given: cli_setup.json last written 38h ago
When:  alln menu --json
Then:  every driver/model row carries checkedAt + ageMinutes
And:   stale == true, with a nextAction whose command actually refreshes
And:   no row reports a negative readiness verdict sourced from that record
```

### PF-S02 — No verdict without a declared signal

**Scope:** A `localPolicy`-confidence observation may not produce
`.rateLimited`. Classify `"Internal error: {"` as `probeFailed`, not a quota
wall. Remove the `vendorReset` splice at `DriverListProjector.swift:68`, or
restrict it to observations that already carry vendor-stated reset truth.
Declared signals come from the driver manifest, per
[`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) §S04 — this slice is
that packet's missing proof.

**Works Test:**
```
Given: a probe whose only output is "Internal error: {"
When:  the record is classified
Then:  status is probeFailed with that reason — never rateLimited
And:   no reset date from any capacity window is attached to it
Given: an observation with sourceConfidence == .localPolicy
When:  a driver row renders it
Then:  the copy never states a vendor reset time as fact
```

### PF-S03 — Re-home scheduled refresh into `alln serve`

**Scope:** Capacity/probe refresh is currently driven from
`AppModel.refreshCapacityCooldowns()`, called from `TeamControlView:207`
(`onAppear`), `RoutingComposerTargetPopover:40`, and `RoutingComposer:196`. It
refreshes when a SwiftUI view happens to appear. App closed — or open on
another screen — and nothing checks anything.

Move the periodic refresh into the `alln serve` scheduler alongside Boost seed
(`BoostWindowOperations`), which already fires reliably overnight with the app
closed — founder-observed, and the existence proof that serve-hosted schedules
work. `CapacityResidentService` and `capacity.sock` (CWB S02) already ship, so
this is largely re-homing, not new construction.

In charter: `alln serve` is a scheduler and periodic refresh is scheduling, not
run semantics. Per AGENTS.md, adding an operation to serve is a new feature
packet — this is that packet.

**Does not fix the lie on its own.** On today's code a perfect 30-minute
scheduler yields a *fresher* wrong answer: the classifier still invents the
limit and the immortal cache still shadows it. PF-S03 must not be sequenced
ahead of PF-S00/S02.

**Works Test:**
```
Given: the Mac app is not running, alln serve is
When:  the freshness clock elapses
Then:  probe/capacity records refresh on disk with a new lastProbeAt
And:   alln menu --json reports stale == false without any GUI interaction
And:   with serve stopped, surfaces report stale == true — never a fresh lie
```

### PF-S04 — Closeout

- [ ] PF-S00…S03 Works Tests pass
- [ ] Promote laws §3.1–3.6 into help topics + `docs/operations/`
- [ ] Negative proof: a genuinely rate-limited vendor still reports the limit,
      with vendor-stated reset copy, and still never hard-blocks dispatch
- [ ] Archive this packet

---

## 5. Non-goals

- Making readiness block dispatch. `DispatchReadiness` law stands: sensors
  inform, never veto (`readiness-informs-never-blocks`).
- A second freshness constant. Reuse the CWB 30-minute clock.
- Probing on every `alln menu` invocation. Menu must stay fast; freshness comes
  from the scheduler plus honest disclosure, not from synchronous probing.
- Auto-substituting a seat whose verdict went `unknown`. Unknown means ask or
  attempt, not silently reseat.
- Reworking capacity window math or the strip. Out of packet.
- Any change to `alln serve` run semantics. It stays a scheduler.

---

## 6. Risks

| Risk | Response |
| --- | --- |
| Expiring negatives re-offers a genuinely dead CLI | Accepted and correct — §1.2. The failure is one loud failed run; dispatch already fails honestly with `command not found` / `errorKind: .missingCLI`. |
| `stale: true` becomes background noise agents learn to ignore | Tie loudness to consequence: stale never asserts a negative, so the only thing an agent can ignore is a *weaker* claim, not a hidden seat. |
| Contract churn on menu/drivers/models JSON | One coordinated additive change, one `contractVersion` bump; CLI/GUI/iOS share `TeamRunJSON`-adjacent shapes and must move together. |
| Refresh in `alln serve` spends quota on a schedule | The 30m refresh must be the cheap non-`--full` path. A quota-spending smoke stays explicit (`alln doctor --full`). |
| PF-S03 lands first and ships a fresher lie | Sequencing is binding: PF-S00/S02 before PF-S03. |

---

## 7. Open questions

1. Does expired resolve to existing `installedNotProbed`, or does a new explicit
   `unknown` status earn its place? Lean: reuse `installedNotProbed` — no new
   vocabulary, and the copy *"Installed, not checked"* is already honest.
2. Is 30 minutes right for probe freshness, or only for capacity? Lean: one
   clock for both until evidence separates them.
3. Should `alln menu` opportunistically refresh when it finds a stale record and
   serve is not running? Lean: no in v1 — disclose and let `nextAction` carry
   it; menu latency is a hero-loop property.
4. Does PF-S03 need a founder ruling as a new `alln serve` operation, or does
   the CWB Dock schedule already cover it?

---

## 8. Immediate unblock (available today, no code)

`alln doctor --full` re-probes and overwrites `cli_setup.json`. It smokes every
driver, so it spends some quota across all installed CLIs. Until PF-S00 lands,
that is the only way to clear a stale negative verdict — which is itself the
argument for the packet.

---

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| A working CLI shows `notReady` / missing from `alln menu`; stale or invented readiness | This packet + `SourceProbeService.swift`, `DriverListProjector.swift`, `DispatchReadiness.swift` |
| A capacity signal attributed to the wrong source | [`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) |
| Freshness clock / warm bench schedule | [`Capacity_Warm_Bench.md`](Capacity_Warm_Bench.md) |
| Whether a sensor may block dispatch | `DispatchReadiness.swift` — it may not |
