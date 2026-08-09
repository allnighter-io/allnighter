# Probe Freshness — the bench must not hide a working seat

Status: **v7 — COMPLETE. PF-S00, PF-S01, PF-S02, PF-S03 and the final
  capability-clock ruling all SHIPPED. Nothing open; ARCHIVE READY.
  The "capacity is a table, not a status" redesign is REFUTED (§0.4) — read it
  before proposing it again.**
  **Follow-on (not this packet):** serve-scheduler residuals after PF-S03 →
  [`Capacity_Serve_Refresh_Polish.md`](Capacity_Serve_Refresh_Polish.md)
  (CRS-S01…S05); code unauthorized there until Ready.

  **PF-S01 shipped 2026-08-09 (`4a150fd3`).** `checkedAt` / `ageMinutes` /
  `stale` / `evidenceSource` / `nextAction` on every driver and model row across
  `menu`, `drivers`, `models`. Contract 9.10.0 → 9.11.0, binary 0.12.2 → 0.12.3.
  A model row carries `evidenceSource: "driver"` so inherited evidence is stated
  rather than implied.

  Worth keeping from that slice: Swift's synthesized `Encodable` emits
  `encodeIfPresent` for optionals, which **omits** the key instead of writing
  `null`. The Works Test's insistence on `checkedAt: null` — "not epoch, not now"
  — is exactly the corner the default synthesis gets wrong, and a decoded-value
  test cannot see it. `ProbeFreshnessJSON` hand-writes `encode(to:)` with
  `encodeNil(forKey:)`, gated by a test that inspects raw JSON keys.

  **RESOLVED 2026-08-09 — the last open item is closed** (`fd188308` AgentOS +
  `12ef89c2` Allnighter, contract 9.13.0, binary 0.12.5). Option A (§521) shipped
  *plus* the writer that was actually missing.

  The contradiction was never about permission to spend smoke. One field was
  carrying two facts with completely different decay rates: *is the binary there*
  (milliseconds, no quota, decays in months) and *does it work when invoked*
  (seconds, sometimes quota, decays in hours). `lastDetectedAt` now takes the
  cheap fact; `lastProbeAt` narrows to capability evidence.

  The real gap: `lastProbeAt` had exactly **one** writer, `CensusIngest.swift:47`,
  the probe path. `RunService` never wrote it — a user could invoke Codex fifty
  times while the bench "did not know" whether Codex worked, sitting on fifty
  proofs. **A probe is a simulated run; a real run is better evidence and costs
  nothing.** Run settlement now writes the capability clock: success confirms,
  `missingCLI`/`authRequired` record the negative, and everything else
  (`timedOut`, `nonzeroExit`, `emptyOutput`, `cancelled`, `permissionRequired`)
  writes nothing, because a bad prompt says nothing about whether a seat works.

  Three honest states replace two: **not detected** / **detected, never
  exercised** / **confirmed at T**. The middle one did not exist before and is the
  correct answer for a new user — better than a fabricated verdict or a scary
  `notReady`. Scheduled smoke is therefore not needed and is not authorized:
  spending a user's own paid quota to answer a question they did not ask is the
  thing to refuse.

  Verified live: a failed run (`emptyOutput`) moved **zero** clocks; a successful
  run set `evidenceSource: "run"`; genuine pre-split records on disk correctly
  read as capability-unknown under the fail-closed migration rule.

  Known dormant: `authRequired` is implemented and unit-tested but no driver
  emits it yet, so the "installed but logged out" state is wired and unexercised.

  **Menu cost — FIXED 2026-08-09** (`2d07b303`, contract 9.14.0, binary 0.12.6),
  founder: *"simplify, don't repeat the full diagnostics."* PF-S01 put a full
  freshness object on every model row, costing 6,325 B (+26.7%) and leaving ~2%
  headroom on the front door — the payload every agent reads first, every session.

  It was a denormalized foreign key, not a compression problem: freshness is a
  *driver* fact, and model rows said so themselves by emitting
  `evidenceSource: "driver"`. So model rows now carry only the one bit an agent
  acts on — `stale` — and reach the detail through the `driverId` they already
  had, on driver rows already in the same payload.

  30,732 B → 23,882 B. Nothing left the payload and no second call is needed, so
  `Menu_Envelope_Compression`'s *"usability > size"* ruling is untouched and was
  not re-opened. The byte budgets were **lowered** (30→25 KiB, 34→28 KiB) rather
  than banked: a gate left high after the payload shrank has stopped guarding
  anything, and that ratchet was the actual risk.
  PF-S03 shipped WITHOUT the evidence-contract decision §0.3 said it needed:
  that blocker applied to re-homing the PROBE-RECORD refresh (`cli_setup.json`,
  where "new lastProbeAt with no smoke" is a contradiction). The founder's
  actual ask was CAPACITY refresh, which is a different store with no such
  problem — see PF-S03 below.
  Spec Review Min `FCF51DB2` Ready (§0.1). PF-S03 carries the 2026-08-08
  founder ruling that supersedes the Capacity Warm Bench Dock-only lock (§0.2),
  and the 2026-08-08 design review that found its scope named the wrong
  function and its cheap refresh path unable to produce evidence (§0.3).
Owner: AllnighterEngine (`SourceProbeService`, `CensusIngest`) +
AllnighterCore (`DriverListProjector`, `ModelListProjector`, `MenuCatalog`,
`BenchReadiness`, `TeamAssembler`, `DoctorReport`, `DispatchReadiness`);
`alln serve` for PF-S03
Created: 2026-08-08 · Revised: 2026-08-08 (v4 — table redesign refuted)
Origin: Founder dogfood 2026-08-08 — `alln menu --json` reported Grok and Kimi
as `notReady` / "Rate limited — resets Aug 14" while both CLIs answered a live
prompt in the same minute. Founder: *"why on launch alln menu is LYING."*

Companion packets:
[`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) (a signal answers
only for the source that produced it — PF-S02 is VSI's **sibling** on the
Allnighter consumer boundary, not its missing proof),
[`Capacity_Warm_Bench.md`](Capacity_Warm_Bench.md) (owns the 30-minute
freshness clock; its Dock-only host lock is superseded — see §0.2),
[`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md)
(runtime park/substitution — must not consume an expired verdict).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

---

## 0. Review record

### 0.1 Spec Review Min (2026-08-08) — `FCF51DB2-AC6D-4B5D-923F-AF6328D79740`

Verdict: **Ready for named slices only** — PF-S00 (merged) and PF-S02
(narrowed) authorized after doc edits; PF-S01 follows S00; PF-S03 last.

Findings accepted and applied in v2, each lead-verified against code:

| Finding | Severity | Where |
| --- | --- | --- |
| v1's §7.1 lean (expired ⇒ `installedNotProbed`) **reproduces the hide it fixes**. `TeamAssembler.readyDriverIds` (`TeamAssembler.swift:66`) admits `isSmokeReady \|\| .rateLimited` — so a rate-limited driver auto-seats today and `installedNotProbed` does not. The v1 lean would have *removed* seats from auto-assembly. | Packet-breaking | §7.1 → §3.7, PF-S00 |
| Expiry must project at **read time**, never rewrite the stored record — a read path must not mutate `cli_setup.json`, and PF-S01 needs the original `lastProbeAt` to disclose age. | Packet-breaking | §3.7, PF-S00 |
| PF-S00 scoped to `SourceProbeService` alone never reaches the lying surfaces; `drivers`/`models`/`menu` read records past the fast path. | High | PF-S00 |
| `invalidateStaleVersions` at dispatch is a **no-op**: `RunService.swift:336` passes `currentVersions: [:]`. v1 §2.2 overclaimed the self-heal. | Medium | §2.2, PF-S00 |
| PF-S02's classifier half is **already green** — AgentOS bare-error gates shipped with VSI-S03. Only the legacy records and the `vendorReset` splice are red. | Medium | PF-S02 |
| §2 package paths wrong: `SourceProbeService` / `CensusIngest` are AllnighterEngine, not AllnighterCore. | Low | §2, Owner |

Contrarian flags carried forward, not silenced:

1. **No feedback loop.** A successful real run never clears a contradicting
   stale negative, so a scheduler can refresh the same wrong answer forever.
   Expiry + disclosure removes the *silent hide* now; the loop is Follow-up (a).
2. **One clock for two facts.** Capacity paint freshness and smoke-verdict
   freshness may not deserve the same constant. Follow-up (c).

**Review honesty note:** the Proof Auditor seat never launched — it died with
`opencode serve busy: port owned by pid 48831`. No independent proof audit ran
on this packet. That is [`OpenCode_Serve_Attach.md`](OpenCode_Serve_Attach.md)'s
defect firing inside the review of this one, and a live repro for that packet.

### 0.2 Founder ruling (2026-08-08) — scheduler host

The review ruled PF-S03 should ride the **Dock app** schedule, citing the
Capacity Warm Bench lock (`Capacity_Warm_Bench.md:123` *"Main Dock app only"*;
`:319` non-goal *"`alln serve` as owner"*). That lock is **superseded**.

Founder, this session, on seeing the defect:

> *"OR we refactor the scheduler and make it part of `alln serve` so the app
> does not have to be open. That might be worth a refactor."*
> *"Scheduler requiring app to be open feels like 100% the WRONG call."*

and ranked **Scheduler 2.0 as priority #1**. Evidence cited: Capacity Boost
fired overnight, reliably, with the app closed — because `BoostWindowOperations`
already runs under `alln serve`.

Per *laws are hypotheses, revisable by founder ruling only*, this is that
ruling. §3.6 stands. PF-S03 targets `alln serve`. **`Capacity_Warm_Bench.md`
must be updated to drop its Dock-only host lock** — that edit belongs to CWB's
owner, not to this packet, and is tracked as Follow-up (d).

### 0.3 PF-S03 design review (2026-08-08) — GPT Sol, run `FAC7C1CB`

Read-only review of PF-S03 against the code, commissioned because PF-S03 is the
only remaining slice whose shape was argued rather than proven. It found three
things the packet had wrong or silent about; all three were re-verified against
the source before being written down here.

| Finding | Severity | Lands in |
| --- | --- | --- |
| PF-S03's scope named `AppModel.refreshCapacityCooldowns()`, which never touches probe records. The real scheduler is `CapacityResidentService` (`AllnighterMacApp.swift:108`). Removing the cited `onAppear` calls would have deleted an unrelated picker cache. | Packet-breaking | §PF-S03 scope |
| The cheap (`full: false`) path persists nothing — `setupStore.save` is inside the `if full` branch. A non-smoke 30m refresh is a no-op against the gate. | Packet-breaking | §PF-S03 missing decision |
| No LaunchAgent/login item exists, so "the app is not running, serve is" is hand-made today and not durable across reboot. | High | §PF-S03 finding 2 |

The review also confirmed PF-S03 has no compile-time dependency on PF-S02 — the
coupling is semantic only (refreshing timestamps while retaining legacy statuses
would make an invented verdict current again). Order preserved anyway; PF-S02
shipped first.

**Process note.** The review run itself came back `status: failed` /
`incomplete_uncommitted` while delivering a complete answer, because the lead
edited files in the same repo while it was in flight. See Follow-up (e).

### 0.4 Rejected: "capacity is a table, not a status" (2026-08-08) — REFUTED

Founder proposal, from first principles: *"capacity as reading from a table —
you pulled data X minutes ago and either it worked and you have data, or it did
not and you don't know the capacity. Is that not 10x simpler?"* The lead
developed it into: retire `ModelSetupStatus.rateLimited` as a capacity signal
and promote `CapacityHistoryStore` to the SSOT.

Two independent read-only reviews were commissioned before any code was written
— K3 (architecture, run `4E5071FD`) and GPT Sol (adversarial/refutation, run
`F07E88A6`). **The proposal was REFUTED.** Do not rebuild it without reading
this section.

**The lead's headline evidence was wrong.** It cited `alln capacity` reporting
kimi at 68% remaining while the probe record called kimi rate limited, and
called that two SSOTs drifting. `alln capacity` does not read the history table
at all — it reads the resident snapshot over `capacity.sock`, else performs a
cold live acquire (`AllnighterCLI.swift:431-441`). The live path knew; the table
being promoted was never the source of that number.

| Claim | Verdict | Evidence |
| --- | --- | --- |
| The history table is a better source | **Refuted** | `lastKnownWindows` treats a record as current for the entire reset window with no observation-age limit (`CapacityHistoryStore.swift:115-128`), and the monotone merge pairs the highest historical peak with the newest timestamp — an 80% sample then a real 50% sample reads as "80% used, observed just now". `CapacityHistoryStoreTests.testMonotonicityLowerUsedDoesNotLowerPeak` locks that in. Valid peak accounting, invalid *current* accounting. |
| The table is fresh with the app closed | **Refuted** | Rows are a side effect of live acquisition (`CapacityFetch.swift:70`), whose only automatic producer is the Dock-app resident (`CapacityResidentService`). App closed, table as stale as everything else. This was the named kill-condition; it failed. |
| The two signals are one fact, drifting | **Refuted — the decisive finding** | They assert different facts. The meter says *the account allowance showed 68% remaining*. `.rateLimited` says *a concrete smoke invocation received a declared vendor capacity refusal*. A model-specific pool, concurrency cap, cooldown or endpoint restriction makes both true at once. **The meter cannot disprove the invocation result.** |
| Retiring the case is a clean deletion | **Refuted** | `TeamAssembler.readyDriverIds` admits `.rateLimited` *deliberately* (`TeamAssembler.swift:71`) so dispatch can attempt and park via QABC rather than die `AGENT_NOT_AVAILABLE`. A vendor-limited smoke would fall to `.probeFailed`, which that predicate excludes — **every vendor-limited seat lost**. Same trap as PF-S00's v1 lean (§0.1), approached from the other side. |

K3 additionally found three under-specifications that would each have shipped a
defect: `probeFailed`'s fate is unnamed and it is already the bucket
*unrecognized* vendor limits fall into (`CLIDetector.swift:406,419`); the
proposed observation→row writer does not exist and cannot, because
`CapacityWindowRecord` identity requires both `usedPercent` and `resetAt`
(`CapacityHistoryStore.swift:255-260`) while smoke observations routinely carry
only `retryAfterSeconds`; and `ModelSetupStatus.Kind` is a persisted Codable
enum (`DriverProbeTypes.swift:84`), so removing the case throws on decode of
every existing `cli_setup.json`.

**What survives, and it is the founder's actual point.** The disease is real: a
verdict stored as a *status* has no age and no provenance, so a reader cannot
tell how old it is or what produced it. The cure is not to delete the signal but
to keep each fact with its own timestamp and scope, and to **surface the
disagreement rather than resolve it silently** — Sol's closing words. PF-S00 and
PF-S02 already do this at read time, which both reviews cite as the correct
layer. PF-S01 becomes *more* valuable, not less: showing two facts with their
ages is exactly what "retain both and surface their disagreement" requires.

**Bonus finding, promoted:** `CapacityResidentService` is the **only** automatic
producer of capacity data anywhere. With the Mac app closed there is no capacity
refresh at all. That makes PF-S03 more load-bearing than a convenience —
it is the reason the founder's priority ordering was right.

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

Package note: `SourceProbeService` and `CensusIngest` live in
**AllnighterEngine**; the projectors and `DispatchReadiness` live in
**AllnighterCore**.

### 2.1 The freshness data exists and nothing reads it

`ToolProbeRecord.lastProbeAt` **is** persisted. Every record in
`~/Library/Application Support/Allnighter/Config/cli_setup.json` carries
`"lastProbeAt": "2026-08-06T22:55:24Z"` — 38 hours stale at probe time.

```
grep -rn "lastProbeAt" Packages/AllnighterCore/Sources
→ AllnighterEngine/CensusIngest.swift:47   (writes it)
→ (no other hit)
```

**One writer, zero readers.** The timestamp needed to make every surface honest
is already on disk. Nothing consults it, nothing expires on it, nothing shows
it. This makes the fix small.

### 2.2 The probe cache is immortal on the fast path

`AllnighterEngine/SourceProbeService.swift:214–216`:

```swift
let cached = previous.records.filter { headlessIds.contains($0.driverId) }
if cached.count == headlessIds.count, !cached.isEmpty { return cached.sorted { … } }
```

If every headless driver has a record, the whole cache is returned. No TTL, no
`lastProbeAt` check, no `retryAfterSeconds` check. Only `--full` re-probes.
`cli_setup.json` was last written **Aug 6 15:56** and could not have aged out on
its own.

Independent corroboration: cached `grok` version is `0.2.118`; the binary on
PATH is `1.0.0`. `DispatchReadiness.invalidateStaleVersions` exists to self-heal
exactly this (its doc comment names the grok version-drift case) — **but it is
not actually healing anything.** Its two call sites:

| Call site | Reality |
| --- | --- |
| `AllnighterEngine/RunService.swift:334–336` | Passes `currentVersions: [:]` — a **no-op**. The comment says the map is "filled by detect/doctor"; on this path it never is. |
| `AllnighterEngine/SourceProbeService.swift:152` | Applied **only to parked drivers**, inside `detect()` (`full: true`). |

So no path that serves `menu` / `drivers` / `models` heals a version-drifted
record. PF-S00 must not depend on this mechanism.

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

Scope note: AgentOS shipped bare-error classifier gates with VSI-S03, so a
*newly produced* record of this shape should no longer be created. These two are
**legacy persisted records** that predate the gate and are still believed.

### 2.4 Two sources spliced into one confident sentence

`AllnighterCore/DriverListProjector.swift:68` passes a `vendorReset` into
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
`models`, and auto-assembly. Which is worse than it sounds: an agent reading
`alln menu --json` sees `ready: false` and **never attempts the run**. A sensor
that informs selection by stating a false fact does not inform selection; it
silently subtracts seats. That is the letter of the law honored and its intent
broken.

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
4. **No verdict without a declared signal.** A probe whose output matches no
   declared vendor signal yields `probeFailed` at the detector — never
   `rateLimited`. A legacy persisted `rateLimited` carrying
   `sourceConfidence: .localPolicy` is normalized to `unknown` at projection.
   A vendor limit is a vendor-printed fact or it is not a fact.
5. **One sentence, one source.** A reset time from capacity history may not be
   attached to a limit verdict produced by a probe. If the observation cannot
   name its own reset, the copy says so.
6. **Scheduled refresh belongs to `alln serve`.** Freshness must not depend on
   a SwiftUI view appearing, or on the Dock app being open (§0.2).
7. **Expiry projects; it does not rewrite.** Aging is computed at read time in
   a shared projection. The persisted record and its `lastProbeAt` are never
   mutated by a read path — PF-S01 needs that original timestamp to disclose
   age, and a menu invocation must not write durable state.

**Boundary between law 4 and law 3** (they pull in opposite directions, and the
line is exact): fail-closed governs **producing** a verdict — no declared
signal, no `rateLimited`. Law 3 governs **aging** one — an expired verdict
decays to `unknown`, never to a stronger claim and never to a `blockedReason`.
Fail-closed means *decline to assert*, which is `unknown`. It has never meant
*assert the worst case*.

**`unknown` is selectable.** It carries no `blockedReason`, it stays in
`alln menu`, and it is admitted by auto-assembly. It is a statement about our
knowledge, not about the seat.

---

## 4. Slice plan

PF-S00 and PF-S02 stop the lie and are red today. PF-S01 is disclosure on top of
S00. PF-S03 is structural and **must not lead** (see its note).

### PF-S00 — Expire the verdict, at the projection — SHIPPED `c817eaba`

**Scope:** one shared freshness projection, consumed by every surface that reads
setup records:

| Consumer | Today | After |
| --- | --- | --- |
| `DriverListProjector` | renders stale `rateLimited` copy | expired ⇒ `unknown`, no rate-limit copy |
| `ModelListProjector` | `ready: false` | expired ⇒ selectable, no `blockedReason` |
| `MenuCatalog` | `"Source not ready"` | expired ⇒ no negative assertion |
| `BenchReadiness` / `TeamAssembler` | `installedNotProbed` excluded from auto-seating | expired ⇒ admitted |
| `DoctorReport` | states the limit | states "not recently checked" |

A record is expired when `lastProbeAt` is older than the freshness clock, or
when its observation's `retryAfterSeconds` has elapsed. Reuse the **existing
30-minute clock** from `Capacity_Warm_Bench.md` — do not introduce a second
freshness constant. Compute at read time only (law 7).

**Do not** wire `invalidateStaleVersions` into this path — it is a no-op today
(§2.2) and would add a dependency on a version map that the fast path does not
have. Tracked as Follow-up (b).

**Works Test:**
```
Given: a seeded record status=rateLimited, retryAfterSeconds=3600,
       lastProbeAt = now - 38h
When:  alln drivers --json / alln menu --json / alln models --json
Then:  the driver is present and carries NO rate-limit copy
And:   its models carry no blockedReason and are not ready:false for staleness
And:   TeamAssembler.readyDriverIds admits the driver
And:   alln run --model <that model> --dry-run accepts it
And:   the persisted cli_setup.json record is byte-identical afterwards (law 7)
Mutation check: restore the old notReady projection ⇒ all five assertions fail.
```
All five fail on current code — verified this session.

### PF-S01 — Disclose age on every selection surface

**Scope:** `menu`, `drivers`, `models` each carry `checkedAt`, `ageMinutes`, and
`stale: true` past the clock, plus a `nextAction` naming the refresh command.
Structured first — a human-only banner leaves every agent reading `--json`
believing the stale value. Contract change ⇒ `contractVersion` bump per the
version rule; CLI/GUI/iOS move together.

Define: `checkedAt` is null for a never-probed row (not epoch, not now); a model
row inherits its driver's evidence and says so.

The "no negative verdict from a stale record" assertion belongs to PF-S00's
gate, not here — this slice adds disclosure only.

**Works Test:**
```
Given: cli_setup.json last written 38h ago
When:  alln menu --json
Then:  every driver/model row carries checkedAt + ageMinutes
And:   stale == true, with a nextAction whose command actually refreshes
And:   a never-probed row reports checkedAt: null, not a fabricated time
```

### PF-S02 — Un-invent the verdict (Allnighter half) — SHIPPED `19dba3b3`, `84a86e0b`

**Scope — the two red jobs, both in Allnighter:**

1. **Legacy record normalization.** A persisted `rateLimited` observation with
   `sourceConfidence: .localPolicy` normalizes to `unknown` at projection. It
   never renders limit copy and never sets a `blockedReason`.
2. **Remove the splice.** Delete the `vendorReset` pass-through at
   `DriverListProjector.swift:68`, or restrict it to observations that already
   carry vendor-stated reset truth. `rateLimitedDetail`'s own confidence guard
   is correct and must not be routed around.

**Not in scope:** the detector-side bare-error classifier. AgentOS shipped those
gates with VSI-S03; that half is already green. This slice is
[`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md)'s **sibling** at the
Allnighter consumer boundary — VSI-S04 owns AgentOS manifests, PF-S02 owns what
Allnighter does with what it receives and what it already persisted.

**Works Test:**
```
Given: a persisted observation with sourceConfidence == .localPolicy
When:  a driver row renders it
Then:  no vendor reset time is stated as fact
And:   no reset date from any capacity window is attached to it
And:   the driver is not reported notReady on that basis
```

### PF-S03 — Re-home scheduled refresh into `alln serve` (Scheduler 2.0)

**Status: SHIPPED 2026-08-08 — `CapacityRefreshScheduler` (038e27a3), plus a
serve singleton (ddb5f748) without which it could not have taken effect.**

Shipped with **no lock and no arbiter**, which was the design question §0.3
worried about. Both the Dock app's resident and the serve scheduler already
write durable history through `CapacityFetch.liveSnapshot`, so *history recency
is itself the shared cross-process freshness signal*: the scheduler refreshes
only when nothing has observed capacity inside the window. App open → history
fresh → serve no-ops. App closed → history stale → serve refreshes. A lease or
socket arbiter could drift; a fact both sides read cannot.

That mattered more than tidiness: capacity probes are measurably load-sensitive,
so two processes probing at once is the failure being avoided, not just waste.

**The evidence-contract blocker did not apply.** §0.3 correctly found that
`SourceProbeService`'s cheap path persists nothing, so a non-smoke refresh of
**probe records** would be a no-op or a fresher lie. But the founder's ask —
"so the app does not have to be open to get data" — is about **capacity**, a
different store with a real writer. The probe-record half remains open and
still needs the `lastDetectedAt` decision.

**It also required a fix nobody had scoped.** Four `alln serve` daemons were
running here, oldest nine days, each on a different build — so a serve-hosted
scheduler would have been added to processes that never execute it. Shipping the
scheduler without the singleton would have looked done and changed nothing.

**Scope — corrected 2026-08-08.** v2 of this packet named
`AppModel.refreshCapacityCooldowns()` as the thing to re-home. **That is the
wrong function.** It rescans failed-run capacity observations into an in-memory
picker cache (`AppModel.swift:513`) and never touches probe records or
`cli_setup.json`; the `onAppear` call sites cited in v2
(`TeamControlView:207`, `RoutingComposerTargetPopover:40`,
`RoutingComposer:196`) are that cache, not the refresh. They must **not** be
mechanically removed.

The real app-owned scheduler is `CapacityResidentService`, started at launch
behind the capacity feature toggle (`AllnighterMacApp.swift:108`) with its own
deadline schedule and a `didWakeNotification` observer. That is what PF-S03
re-homes. `ServeDaemon` (`ServeDaemon.swift:124-178`) schedules Pending wake,
Boost, backoff and notifications today — and no capacity/probe refresh.

Founder-ruled 2026-08-08 (§0.2), superseding the CWB Dock-only host lock. In
charter: `alln serve` is a scheduler and periodic refresh is scheduling, not run
semantics.

**Does not fix the lie on its own.** On today's code a perfect 30-minute
scheduler yields a *fresher* wrong answer: the stale record still projects a
negative and the legacy verdict is still believed. **Sequencing is binding:
PF-S00 and PF-S02 land before PF-S03.** (Both have now landed —
`c817eaba`, `19dba3b3`, `84a86e0b`.)

**Three findings that change the slice (§0.3):**

1. **No arbiter exists.** Adding a schedule to serve without removing the app's
   would run two cross-process schedulers. Resident single-flight is
   actor-local (`CapacityResidentService.swift:440-506`); `capacity.sock` is
   read-only and app-owned and unlinks its path at startup
   (`CapacitySocket.swift:155-162`); `CapacityHistoryStore` explicitly accepts
   unlocked concurrent writers; `ServeDaemonStore` is a liveness record, not a
   lock. Serve must become the **sole** automatic scheduler, under a
   daemon-lifetime advisory lock.
2. **Nothing keeps serve alive across logout or reboot.** There is no
   LaunchAgent, login item, or `KeepAlive` in the repo — serve is started by
   `alln serve` or detached on demand by Loop commands
   (`ServeAutoLaunch.swift:104-118`). The Works Test's `Given` is made true by
   hand today. PF-S03 may assume it, but **may not claim** reboot continuity;
   auto-start at login is a separate slice and a founder call (activation and
   opt-out posture).
3. **The cheap path cannot produce fresh evidence — this is the blocker.**
   `SourceProbeService.probe(full: false)` persists nothing:
   `setupStore.save` lives *inside* the `if full` branch
   (`SourceProbeService.swift:194-212`). With a complete cache it returns the
   records unchanged, old `lastProbeAt` included
   (`SourceProbeService.swift:214-216`). So a 30-minute non-smoke refresh is a
   **no-op** against `ProbeFreshnessGate`, which reads `lastProbeAt` directly.

**Missing decision (must be ruled before coding):** under the current record
model, "new `lastProbeAt` with no smoke" is a contradiction — writing the
timestamp forward while keeping a smoke-derived status manufactures fresh
evidence that no probe produced, which is the same defect class this packet
exists to kill. Two candidate shapes:

| Option | Shape | Cost |
| --- | --- | --- |
| **A — split the timestamp** | Add `lastDetectedAt` for cheap detection; leave `lastProbeAt` as smoke-only evidence. The gate ages smoke; detection answers "is the binary still there". | Record model change; PF-S01's disclosure must then name *which* clock it is reporting. |
| **B — permit periodic smoke** | Serve runs a real `full: true` probe on the freshness clock. | Spends quota on a timer, against the user's own subscriptions. Needs a founder ruling on its own. |

Lean: **A.** It is the only one that keeps "fresh" meaning "recently proven",
and it composes with PF-S01 — a surface can honestly say *detected 4m ago,
last proven 3h ago*. B trades the packet's core law for convenience.

**Works Test:**
```
Given: the Mac app is not running, alln serve is
When:  the freshness clock elapses
Then:  probe/capacity records refresh on disk with a new lastProbeAt
And:   alln menu --json reports stale == false without any GUI interaction
And:   with serve stopped, surfaces report stale == true — never a fresh lie
And:   the 30m refresh uses the cheap non-full path (no quota smoke)
```

### PF-S04 — Closeout

- [ ] PF-S00…S03 Works Tests pass
- [ ] Promote laws §3.1–3.7 into help topics + `docs/operations/`
- [ ] Negative proof: a genuinely rate-limited vendor still reports the limit,
      with vendor-stated reset copy, and still never hard-blocks dispatch
- [ ] `Capacity_Warm_Bench.md` host lock reconciled with §0.2
- [ ] Archive this packet

---

## 5. Follow-ups (named, not silenced)

| # | Item | Why deferred |
| --- | --- | --- |
| (a) | **Feedback loop:** a successful real run clears a contradicting stale negative. Without it a scheduler can refresh the same wrong answer forever. | Expiry + disclosure removes the *silent hide* now. Real gap; not a reason to hold a P1 fix. Spec Review contrarian flag 1. |
| (b) | **Version source for the heal path:** `invalidateStaleVersions` is a no-op at dispatch (`currentVersions: [:]`). Either feed it or delete it. | Dead code that reads as a working safety net is its own lie. Out of PF-S00's blast radius. |
| (c) | **Split the clocks** if dogfood shows a 30-minute probe cadence churning verdicts. Capacity paint freshness ≠ smoke-verdict freshness. | One clock until evidence separates them. Contrarian flag 2. |
| (d) | **Update `Capacity_Warm_Bench.md`** to drop the Dock-only host lock per §0.2. | Belongs to CWB's owner, not this packet. |
| (e) | **Ambient-dirty misattributes a concurrent editor.** ADR-S01 narrowed the `incomplete_uncommitted` gate to paths a run introduced (`RunService.swift:2173`), but "introduced" is a git-wide set-subtract, so files the *lead* edits while a run is in flight are charged to the run. Run `FAC7C1CB` delivered a complete review and was marked `failed`. | Reopening `Ambient_Dirty_Run_Outcome.md` (archived) or a successor. It is a run-outcome semantics change — demote to warning when an answer was delivered — and does not belong inside a probe-freshness slice. Systematically punishes the founder's own prescribed "dispatch read-only diagnosis while you keep building" workflow, so it is not cosmetic. |

---

## 6. Non-goals

- Making readiness block dispatch. `DispatchReadiness` law stands: sensors
  inform, never veto (`readiness-informs-never-blocks`).
- A second freshness constant. Reuse the CWB 30-minute clock.
- Probing on every `alln menu` invocation. Menu must stay fast; freshness comes
  from the scheduler plus honest disclosure, not from synchronous probing.
- Mutating persisted records from a read path (law 7).
- Auto-substituting a seat whose verdict went `unknown`. Unknown means ask or
  attempt, not silently reseat.
- Reworking capacity window math or the strip. Out of packet.
- Any change to `alln serve` run semantics. It stays a scheduler.

---

## 7. Risks

| Risk | Response |
| --- | --- |
| Expiring negatives re-offers a genuinely dead CLI | Accepted and correct — §1.2. The failure is one loud failed run; dispatch already fails honestly with `command not found` / `errorKind: .missingCLI`. |
| `stale: true` becomes background noise agents learn to ignore | Tie loudness to consequence: stale never asserts a negative, so the only thing an agent can ignore is a *weaker* claim, not a hidden seat. |
| A read-time projection drifts from what doctor writes | One shared projection consumed by all five surfaces (PF-S00 table), not per-surface staleness logic. |
| Contract churn on menu/drivers/models JSON | One coordinated additive change, one `contractVersion` bump; CLI/GUI/iOS move together. |
| Refresh in `alln serve` spends quota on a schedule | The 30m refresh must be the cheap non-`--full` path. A quota-spending smoke stays explicit (`alln doctor --full`). |
| PF-S03 lands first and ships a fresher lie | Sequencing is binding: PF-S00/S02 before PF-S03. |
| CWB and this packet disagree on scheduler host until (d) lands | §0.2 is the ruling of record; CWB is stale on this point, not authoritative. |

---

## 8. Open questions

1. ~~Expired ⇒ `installedNotProbed` or a new `unknown`?~~ **Ruled (§0.1):** a
   read-time `unknown` at the projection layer. `installedNotProbed` projects as
   `notReady` and is excluded by `TeamAssembler` — it cannot carry this meaning.
2. Is 30 minutes right for probe freshness, or only for capacity? Lean: one
   clock for both until dogfood separates them — Follow-up (c).
3. Should `alln menu` opportunistically refresh when it finds a stale record and
   serve is not running? Lean: no in v1 — disclose and let `nextAction` carry
   it; menu latency is a hero-loop property.
4. ~~Does PF-S03 need a founder ruling?~~ **Ruled (§0.2):** it has one; it
   targets `alln serve` and supersedes the CWB Dock-only lock.

---

## 9. Immediate unblock (available today, no code)

`alln doctor --full` re-probes and overwrites `cli_setup.json`. It smokes every
driver, so it spends some quota across all installed CLIs. Until PF-S00 lands,
that is the only way to clear a stale negative verdict — which is itself the
argument for the packet.

---

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| A working CLI shows `notReady` / missing from `alln menu`; stale or invented readiness | This packet + `AllnighterEngine/SourceProbeService.swift`, `AllnighterCore/DriverListProjector.swift`, `DispatchReadiness.swift` |
| Scheduler host — app-open vs `alln serve` | §0.2 founder ruling (supersedes `Capacity_Warm_Bench.md` Dock-only lock) |
| A capacity signal attributed to the wrong source | [`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) |
| Freshness clock | [`Capacity_Warm_Bench.md`](Capacity_Warm_Bench.md) |
| Whether a sensor may block dispatch | `DispatchReadiness.swift` — it may not |
