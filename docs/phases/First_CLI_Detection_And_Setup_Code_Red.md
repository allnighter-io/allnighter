# First CLI Detection & Setup — CODE RED

Status: **CODE RED — OPEN — v3 (Sol-hardened, execution-ready)**
Owner: AllnighterMac (`RootView` cold launch, `BenchHealthBadge`, `ThreadEmptyStateBody`,
`ReadinessView` / `SetupViews`) + AllnighterCore (proposed tally projector,
`ProbeFreshnessGate`, `BenchReadiness`) + AgentOS `CLIDetector` / `ModelSetupStatus`
Created: 2026-08-10
Revised: 2026-08-10 (v3 — code-checked touchpoints, falsifiable proofs, S01-first dogfood order)
Origin: First launch of the Mac app on a new host shows amber **`0/9 ready`**, a
capacity strip painting every seat as up, and a composer seat list labelled "Not
detected" — while **zero** CLI probes have ever run on that machine. The product
promise dies before the first message.

Related (read before coding — do not relitigate closed law):
- Live setup intent: `docs/phases/setup/00_First_Run_Setup_Experience.md`,
  `docs/phases/setup/01_CLI_Detection_Auth_And_Bench.md` (§4 probe authority,
  §5 status model), `docs/phases/setup/README.md`
- Launch Authority (process-quiet cold launch): archived
  `docs/archive/phases/Launch_Authority_TCC_Hotfix.md`
- Same-day TCC resurface: `docs/operations/debugger/2026-08-10-first-launch-tcc-popups-PACKET.md`
- Cursor Agent CLI (built): archived `docs/archive/phases/setup/Cursor_Agent_CLI_Support.md`
- Freshness / absent-signal law: archived `docs/archive/phases/Probe_Freshness.md`,
  open `docs/phases/Vendor_Signal_Isolation.md`
- Product vocabulary: `docs/workflows/Product_Vocabulary.md` (source / model / worker)

Phases are ephemeral. At closeout: promote the tally law + first-scan authority
into the setup docs and AGENTS routing; code stays SSOT; archive this packet.

---

## 0. Code-red claim (one sentence)

**Opening Allnighter must either find the CLIs the user already paid for, or put
each one an honest button away — never grade a machine it has never looked at
against the size of our support catalog.**

`0/9 ready` is not humility. It is a confident measurement of something we never
measured, printed in warning amber, as the first thing the product says.

---

## 1. What the founder saw (2026-08-10) — verified against code

| # | Observed | Code |
| --- | --- | --- |
| 1 | Title-bar badge reads **`0/9 ready`**, amber/warning tone | `BenchHealthBadge.label` / `.tone` — `SetupViews.swift` ~933–942 |
| 2 | An **existing selected thread with zero turns** repeats **`0/9 CLIs ready`** with a grey dot | `ThreadEmptyStateBody` — `ThreadView.swift` ~86–108. Correction from v2: this is not necessarily the virgin app's first pane; a host with no threads is in `HomeMarketingEmptyState`. It is still a live duplicate lie reached as soon as an empty thread is selected. |
| 3 | Composer still lists Auto / Composer 2.5 / Cursor Grok 4.5, each labelled **"Not detected"** | `AppModel.composeBench` — `AppModel.swift` ~545–582 |
| 4 | Capacity strip has no setup-derived reason to suppress never-probed seats, so cached/live rows can paint them as available | `HomeNewRunPane.notReadyOrParked` — `HomeView.swift` ~762–773 |
| 5 | Nothing offers a scan; setup never opens | `RootView` cold launch → `loadCachedSetupState()` only, ~388–399 |

### The two numbers, and why they are both wrong together

| Symbol | Code | What it actually means |
| --- | --- | --- |
| **X = 0** | `AppModel.readyToolCount` (`AppModel.swift` ~438) | Probe records whose status `.isSmokeReady`, minus parked. On a virgin host there are **no records at all** — so this is not "zero ready", it is "zero measurements". |
| **Y = 9** | `AppModel.totalToolCount` (~442) | Every bundled `headlessCLI` manifest, minus parked: Antigravity, Claude Code, Codex, Cursor Agent, Grok, Kimi, Muse, OpenCode, Qwen. Support-catalog size. |

Cold launch calls `loadCachedSetupState()` (~685), which assigns `toolStatuses`
**only if the persisted record set is non-empty**. Empty store ⇒ `toolStatuses`
stays at its initialized `[]` value ⇒ X = 0 until the user explicitly opens setup
and runs a probe. The badge
formula (`ready == total ? "N ready" : "N/T ready"`) then renders a ratio whose
numerator was never sampled, and tones it `.warning`.

**The lie is not the 0. It is the slash.** A ratio asserts that both sides were
measured on the same machine. One side is a build-time constant; the other is an
empty array.

### The absence-of-record trap (worse than the badge)

`ModelSetupStatus` (AgentOS `DriverProbeTypes.swift`) has **no `notChecked`
case** — never-probed is represented by the *absence* of a `ToolProbeRecord`.
Every consumer that iterates records therefore silently treats a virgin host as
"nothing to report":

- `HomeNewRunPane.notReadyOrParked` (`HomeView.swift` ~762–773) builds its
  down-set by walking `appModel.toolStatuses` for non-ready records. Zero records
  ⇒ **empty down-set** ⇒ the capacity strip treats every seat as not-down.
- `AppModel.composeBench` (~558–564) collapses `.notInstalled` and `.none` into
  the same copy, **"Not detected"** — a negative assertion about a driver we
  never looked at. That is the inverse lie of the badge, in the same window.
- `BenchReadiness` / `TeamAssembler.readyDriverIds` correctly return nothing —
  so dispatch is honest. The *display* surfaces are the divergent ones.

So on one virgin screen the chrome says *nothing is ready* (measured nothing),
the strip says *every seat is up* (found no problems), and the seat list says
*not detected* (ran no detection). Three surfaces, three different unmeasured
claims, all sincere.

One layer already gets this right and should be the model for the rest:
`AppModel.setupCards` (~496) enumerates **supported drivers**, not records, and
renders a never-probed driver as `SetupCardState.notChecked` ("Not checked").
That state exists in the view layer and nowhere else.

---

## 2. First principles

1. **Never measured is a state, not a value.** It is not zero, not failure, not
   pending. It gets its own rendering and its own copy, everywhere.
2. **A ratio is a claim about two measurements.** If one side is a constant from
   the build, do not print a slash. Catalog size is a fact about *us*; readiness
   is a fact about *this machine*. They belong on different surfaces.
3. **Enumerate the supported set, not the observed set.** Anything derived by
   filtering existing records inherits "empty cache means nothing is wrong."
   Start from the registry; treat a missing record explicitly.
4. **Ready is earned by a smoke token, once, and only there.** Presence, a
   running IDE, a config file, a Keychain item, and a vendor dashboard are not
   evidence. (`ModelSetupStatus.isSmokeReady` is already the one gate — keep it
   the only one.)
5. **Asymmetric costs decide the default.** A false "ready" costs one loud failed
   run. A false "not ready" silently deletes a seat the user pays for. So an
   unmeasured seat must read as *unknown and one click from certain*, never as
   *absent* and never as *ready*. This is the same asymmetry `ProbeFreshnessGate`
   already encodes for stale negatives.
6. **The first proof is the product.** The thesis is "you already pay for the
   team." A user who has to go looking for the scan has already been told the
   opposite by the chrome.
7. **Spawning is a user's decision, and it must be visible when it happens.**
   Process-quiet is not a performance policy; it is who-authorized-this policy.

---

## 3. Anti-patterns (forbidden shapes, with the reason)

| Anti-pattern | Why it is banned |
| --- | --- |
| `0/<catalogSize> ready` on an unscanned host | Prints a measurement that was never taken (§2.1, §2.2) |
| A second surface recomputing `X/Y` from `readyToolCount` / `totalToolCount` | Two owners of one number always drift; the badge and thread empty state have already drifted into duplicate copy |
| Deriving "down / not ready" by filtering existing records | Empty cache ⇒ empty problem set ⇒ everything looks fine (§1 trap) |
| Collapsing "never probed" into "not installed" / "not detected" | Asserts a detection result from a detection that never ran — the fail-closed law inverted into a fail-confident one |
| Silent `onAppear` full-bench smoke to "fix" the empty cache | Repeals Launch Authority; this is exactly the 2026-08-10 TCC-storm class |
| Inferring ready from Cursor IDE running, a credentials file, or a dashboard | Repeals §2.4 and the AGENTS law that a local computation is never a vendor-stated fact |
| Auto-seating an unmeasured driver so the composer looks populated | Turns "unknown" into "ready" — the exact failure the founder saw as grey-dot theater |
| Hard-gating the app behind "≥1 ready" | Repeals the non-trapping law in `00_First_Run_Setup_Experience.md` §3 |
| Rebuilding the cut 6-scene cinematic onboarding | Already ruled out; the wow is recognition and speed, not motion |

---

## 4. Standing law this packet must not repeal

- **Launch Authority (archived hotfix, rules 1–4).** Ordinary cold launch renders
  cached/unknown state and spawns nothing. Full smoke and login-shell PATH
  capture are explicit user intent. `runFullSetupProbe(userInitiated:)` is the
  only door (`AppModel.swift` ~732), and it must stay the only door.
- **Non-trapping (`00_…` §3).** The user may leave setup with 0 ready. The badge
  stays honest and offers a way back.
- **Honesty (`01_…` §5).** `.ready` only on a returned smoke token; the five-way
  status split (`installedNotSignedIn` vs `probeFailed` etc.) is what makes the
  fix actionable.
- **Freshness asymmetry (`ProbeFreshnessGate`).** Positives are disclosed, not
  decayed; negatives stop being asserted when they outlive their evidence. A
  never-measured seat is weaker than an expired negative, so it may not be
  rendered as a stronger claim than one.

This packet resolves the collision between "returning launches stay quiet" and
"a first launch has nothing to be quiet about" — by making the first scan a
**visible, attributed, one-time user action**, not a background sweep.

---

## 5. Ideal outcome

Within ~60 seconds of first open on a Mac that already has ≥1 agent CLI
installed and signed in:

1. The user reads **what we found**, never a grade against our catalog.
2. Installed + signed-in sources flip to **ready** with real versions.
3. Each source that needs a step shows **one** primary action (sign in, confirm
   path, re-check) — not a wizard.
4. Cursor IDE users are told plainly that the seat is the **Cursor Agent CLI**,
   with install → `agent login` → one re-check.
5. The composer, capacity strip, and badge agree with each other and with
   dispatch.
6. The next launch, with a warm cache, is silent. No TCC dialog, no spawn.

---

## 6. Shape A vs Shape B — decision table

**Shape A — framed first-run scan.** On a host with no completed setup, normal
Home includes a small "Find your team" frame whose primary button runs one
`runFullSetupProbe(userInitiated: true)` with live per-source progress. It is
content inside Home, not an auto-open setup sheet.

**Shape B — roster-first.** The first meaningful surface is the CLI setup roster,
pre-populated with every supported source as `notChecked`, each with one primary
action; a "Scan all" sits at the top.

| Dimension | Shape A (framed scan) | Shape B (roster-first) |
| --- | --- | --- |
| Time to first ready seat | Fastest — one click, parallel probes | Slower if the user works card by card |
| Clicks in the happy path | 1 | 1 (Scan all) + reading a full roster |
| Launch Authority risk | **Moderate** — must be a real button, never `onAppear` | **Low** — roster renders from cache; nothing spawns |
| TCC moments | One, clearly attributed to the button press | One, on Scan all |
| Failure mode | Scan finds nothing → dead-end frame unless it falls back to the roster | Degrades gracefully; the roster *is* the recovery UI |
| Build cost | New first-run surface + once-only gate | Mostly routing + copy on surfaces that exist |
| Proof surface | New gate tests + GUI proof | Existing `CLISetupGroupingTests` / setup GUI proof |
| Dogfood truth | Best "it found my team" moment | Best "I understand what I have" moment |

**Recommended default: A over B, with B as the result/recovery surface.** Ship
the framed Home scan; after the press, all-clear stays on Home and unresolved
results open the roster with the founder's cards already partitioned. Neither
shape is worth building until **FCS-S01 lands**, because both inherit the same
tally.

**Hard constraint on A:** the scan fires from a press, never from `onAppear`,
and never from presentation. If the frame renders and the user does nothing,
zero child processes are spawned. That is the wall-reachable gate (§10,
FCS-S02).

---

## 7. The missing truth owner: one bench tally

Today the badge and empty-thread surface duplicate ratio arithmetic, while the
capacity strip derives a different "down" set from only existing records and
the composer maps an absent record to a detection result. The setup page is
**not** a third ratio owner: `ReadinessView.summaryLine` currently shows
`availableModelCLICount` + `availableModels.count`. v2 incorrectly grouped that
header with the ratio bug.

Introduce one pure projector in **AllnighterCore** — not in the Mac app
— because the Mac target has no mid-slice proof path (`scripts/swift-test.sh`
covers `Packages/AllnighterCore` only; app tests run at closeout under
`scripts/check.sh`). Putting the law in Core is what makes it provable during
the slice.

Required shape (names may change only if the same distinctions survive; there
must be exactly one projector):

```text
BenchTallyProjector.tally(registry:records:parked:now:) -> BenchTally

BenchTally {
  supported: Int        // headlessCLI manifests, minus parked  (a fact about us)
  measured: Int         // supported drivers WITH any probe record (historical observation)
  ready: Int            // records .isSmokeReady, minus parked
  needsStep: Int        // currently assertable installedNotSignedIn / shimmedNeedsConfirm /
                         // probeFailed / rateLimited
  notInstalled: Int
  needsCheck: Int       // absent record OR an unassertable expired/inferred negative
  headline: Headline    // .configurationMissing | .neverScanned | .partial |
                         // .allReady | .noneReady
}
```

Rules the projector encodes, so no caller can re-derive them wrong:

- `supported == 0` ⇒ `headline == .configurationMissing`; preserve the existing
  reinstall-style broken-configuration path. An empty registry is not an
  unscanned bench.
- Otherwise `measured == 0` ⇒ `headline == .neverScanned`. **No ratio is emitted at all** —
  the type does not carry one, so a caller cannot print `0/9`.
- Remaining headline precedence is mechanical: `ready == supported` ⇒
  `.allReady`; else `ready == 0` ⇒ `.noneReady`; else `.partial`. Buckets provide
  detail; callers do not choose a different headline.
- `supported` is never a denominator in chrome. It belongs on the setup page
  ("we support 9, found 4"), which is a sentence, not a grade.
- Parked sources are excluded from every count (already true of
  `readyToolCount` / `totalToolCount`; keep it).
- `measured` means a record exists; it does **not** mean a negative is still
  assertable. Before filling `needsStep`, call
  `ProbeFreshnessGate.unassertableNegatives(records, now:)`. An expired/inferred
  negative goes to `needsCheck`, not `needsStep`; positives stay ready. This
  removes v2's ambiguous "the tally reports what it reports," which could have
  reintroduced stale negative claims.
- Duplicate records for one `driverId` count once. The projector must choose the
  latest `lastProbeAt` record deterministically; array length is never a tally.
- Records for unknown/non-headless manifests are ignored. Parked drivers are
  excluded from `supported`, every bucket, and the headline.

### Required chrome mapping

| Tally headline | Title-bar badge | Thread empty state | Home / composer |
| --- | --- | --- | --- |
| `.configurationMissing` | **Setup unavailable**, danger | Reinstall-style configuration error | No scan/runnable seats; preserve `isConfigurationBroken` recovery |
| `.neverScanned` | **Find my team** (neutral CTA, never warning amber) | "No CLIs checked yet" + the same CTA | No seat is offered as runnable; the scan is the primary action |
| `.partial` | **`N ready`** (or `N ready · M need a step`) | `N ready` | Only ready sources power Auto and the seat list |
| `.noneReady` | **Set up CLIs** + the top reason | Reason + one action | Hopeful install list; nothing runnable claimed |
| `.allReady` | **`N ready`**, positive tone | `N ready` | Normal |

Note the tone bug rides along: `.warning` for a never-scanned host is the
chrome-level assertion that something is broken. Never-scanned is neutral.

---

## 8. Cursor IDE vs Cursor Agent CLI — the implementable path

The user is coding *inside* Cursor and reasonably expects Cursor to be seated.
Under the current contract that expectation is false, and today we neither
satisfy nor correct it.

**The content for this card already ships.** The canonical sibling AgentOS
catalog (`../AgentOS/Sources/AgentOSCLI/Catalog/catalog.json`,
`cursor_agent.setup`) already carries
the install one-liner, both docs URLs, the login command, the auth patterns, and
the trust disclosure. This slice is rendering, not authoring.

| Fact (verified in the shipped catalog) | Field | Implication |
| --- | --- | --- |
| Seat id `cursor_agent`, display "Cursor Agent" | manifest id | Copy says **Cursor Agent CLI**, never "Cursor" alone |
| Bins are `agent` **and** `cursor-agent` | `setup.bins` | Detection tries both; "not installed" means *neither* resolved |
| Detect `agent --version`; smoke `-p … --model composer-2.5 --trust` | manifest | Ready requires the smoke token; an open IDE proves nothing |
| `curl https://cursor.com/install -fsS \| bash`, then `agent login` | `setup.installHint` | The install card needs no invented copy — render this, copyable |
| `https://cursor.com/docs/cli/installation` / `…/cli/using` | `setup.docsURL`, `setup.loginFlow.docsURL` | Two distinct links exist in the catalog. **Current Mac mapping keeps only `setup.docsURL`; `SetupCardModel` has no login-doc URL. S03 must add and map it.** |
| `agent login`, plus "open Cursor once and retry" for Keychain errors | `setup.loginFlow` | The sign-in card opens Terminal with exactly this |
| `SecItemCopyMatching failed`, `not authenticated`, `401`, … | `setup.loginFlow.authErrorPatterns` | Classify as `installedNotSignedIn`, not `probeFailed` |
| `--trust` required, with a full disclosure sentence | `setup.headlessTrust` | The disclosure must survive onto the card; do not silently drop it |

Builder path for the Cursor-without-CLI card:

1. Probe resolves neither `agent` nor `cursor-agent` ⇒ `.notInstalled`.
2. Card headline names the gap in the user's words: *"Cursor Agent CLI not found
   — the Cursor app is not the seat."*
3. Render `setup.installHint` (copyable) + `setup.docsURL`, then `agent login`
   from `loginFlow` plus `loginFlow.docsURL`, then one **Re-check** that calls
   `runSetupProbe(userInitiated: true, onlyDriverId: "cursor_agent")` and flips
   the card in place.
   Correction from v2: `SetupActions.handle(.rescan)` currently calls
   `runFullSetupProbe`, so merely drawing a per-card button does not satisfy this
   path; the action must carry `driverId` and use the single-driver API.
4. **No IDE detection anywhere in this path.** Do not read the running process
   list, `~/.cursor`, or any Cursor config to soften the card. If we later want
   "installed, not checked", that is `installedNotProbed` after a real resolve —
   still not ready. (The enum case already exists; it is not required for v1.)

---

## 9. Execution start here

**Tomorrow morning, implement only FCS-S01. Do not start the framed scan in the
same change.** It removes the founder-visible false grade without changing launch
authority, probe behavior, TCC posture, manifests, capacity acquisition, or setup
routing.

FCS-S01 is done when, and only when:

- `BenchTallyProjectorTests` proves empty records, empty registry, duplicate,
  parked, unknown-manifest, partial, all-ready, and stale/inferred-negative
  fixtures.
- `AppModel.benchTally` is the sole Mac bridge; `BenchHealthBadge` and
  `ThreadEmptyStateBody` no longer read `readyToolCount` / `totalToolCount`
  directly and never construct a slash ratio.
- The never-scanned GUI fixture visibly reads **Find my team** in the badge and
  **No CLIs checked yet** in the selected empty-thread state, both neutral; a
  one-ready fixture reads **1 ready**.
- Focused Core proof passes, then the one closeout wall runs once. No S02 files or
  behavior are included.

---

## 10. Slices

Ship order is S01 → S02 → S03 → S04. **S01 alone removes the worst lie** and is
worth landing on its own.

### FCS-S00 — Packet + routing (this document)

- Truth owner: this packet + `docs/phases/README.md` board row.
- Works Test: a builder can start S01 without asking what the tally means.
- Proof: doc review.

### FCS-S01 — One bench tally, no invented ratio

- Goal: `BenchTallyProjector` in AllnighterCore; badge and selected-empty-thread
  chrome read it. Never-scanned emits a CTA, not `0/9`, and not amber. The setup
  summary is explicitly out of this slice because it does not print the ratio.
- Truth owner: `BenchTallyProjector` (new) over `registry` + `[ToolProbeRecord]`.
- Lie-prone layer: `BenchHealthBadge.label` / `.tone`; `ThreadEmptyStateBody`;
  any future surface tempted to divide.
- Exact files/types:
  - add `Packages/AllnighterCore/Sources/AllnighterCore/BenchTallyProjector.swift`
    (`BenchTally`, `BenchTally.Headline`, `BenchTallyProjector`);
  - add `Packages/AllnighterCore/Tests/AllnighterCoreTests/BenchTallyProjectorTests.swift`;
  - edit `Apps/AllnighterMac/Sources/AppModel.swift` to expose one
    `benchTally(now:)`/`benchTally` bridge (do not add a second projector);
  - edit `Apps/AllnighterMac/Sources/SetupViews.swift` (`BenchHealthBadge`) and
    `Apps/AllnighterMac/Sources/ThreadView.swift` (`ThreadEmptyStateBody`);
  - add exact presentation assertions under
    `Apps/AllnighterMac/Tests/AppModelTests.swift` or a narrowly named
    `BenchTallyPresentationTests.swift`, plus a deterministic GUI fixture only
    if needed for owner-visible proof.
- Out of scope: `RootView`, `ReadinessView`, probing, setup completion,
  `HomeView`, `CapacityStripModel`, Cursor card content.
- Works Test (owner-visible and falsifiable): with an empty `cli_setup.json`,
  select a zero-turn thread and capture the app: title badge is exactly **Find my
  team**, its tone is neutral, thread copy is exactly **No CLIs checked yet**, and
  the capture contains neither `0/` nor `ready` beside the badge. Seed one fresh
  ready record and recapture: both surfaces say **1 ready**.
- Proof: `scripts/swift-test.sh --filter BenchTallyProjectorTests` (empty
  records ⇒ `.neverScanned`; empty registry ⇒ `.configurationMissing`;
  duplicates dedupe; parked/unknown excluded;
  stale/inferred negatives do not become needs-step; partial/all-ready mapping).
  Mac tests cannot be run through `scripts/swift-test.sh`; run
  `bash scripts/check.sh` **once at slice closeout**, never mid-slice. The focused
  Core wrapper is the only iteration loop. GUI proof is required because visible
  copy/tone is the Works Test (`scripts/gui_proof.sh`,
  `docs/gui/Visual_Proof_Gate.md`).

### FCS-S02 — Framed first scan (Shape A), once, on a press

- Goal: on `setupCompletedAt == nil` **and** zero probe records, render the
  first-run frame **inside the normal Home launch surface**. Do not auto-present
  `TeamReadinessView` or a sheet: `RootView` and the durable setup specs currently
  say setup never hijacks launch. The frame's primary button runs
  `runFullSetupProbe(userInitiated: true)` with live per-source progress; results
  use the roster (Shape B). This is how v3 keeps Shape A+B without silently
  overriding the standing "Home first" decision.
- Truth owner: `SetupStore` (`setupCompletedAt`, records) + the once-gate.
- Lie-prone layer: the presentation path — a sheet that scans on appear is
  indistinguishable from a silent launch spawn to macOS and to TCC.
- Exact files/types: `Apps/AllnighterMac/Sources/RootView.swift` (routing only),
  the Home first-run frame in `HomeView.swift` or a new single-purpose view,
  `AppModel.hasCompletedSetup` / `markSetupCompleted`, and AppModel test
  injection for the detector/probe command. Do not edit `CLIDetector` semantics.
- Works Test: inject a recording probe command. Construct/present the frame and
  advance the main actor: recorded requests and child-command calls remain
  exactly `0`. Invoke the primary action twice while in flight: exactly `1`
  full-probe request is recorded. Complete it with one ready + one not-installed
  record: roster partitions exactly 1/1. Mark complete, reconstruct the model,
  and assert the frame predicate is false. Then founder TCC proof:
  `tccutil reset` → open app outside protected folders → touch nothing → zero
  dialogs.
- Proof: the existing `AppModelTests.testLoadCachedSetupStateDoesNotStartDetection`
  only checks `isDetecting`; it can stay green if another launch path spawns a
  process. Add the recording seam above. Core iteration:
  `scripts/swift-test.sh --filter LaunchAuthorityProbeTests`; Mac/integration
  assertions run only in the closeout `bash scripts/check.sh`.

### FCS-S03 — Roster as the recovery UI (Shape B) + Cursor card

- Goal: every supported source has exactly one primary action in its
  `notChecked` / needs-step state; the Cursor-without-CLI card of §8 exists.
- Truth owner: `AppModel.setupCards` / `AppSetupModel` (already enumerates
  supported drivers — extend, do not fork).
- Lie-prone layer: copy that implies the IDE is the seat; multi-step cards.
- Exact files/types: `Apps/AllnighterMac/Sources/AppSetupModel.swift`;
  `SetupCardModel` / `SetupCardView` / `SetupActions` in `SetupViews.swift`;
  `AppModel.runSetupProbe(userInitiated:onlyDriverId:)`; and
  `Apps/AllnighterMac/Tests/SetupCursorPresentationTests.swift`. Catalog content
  remains owned by AgentOS and is not duplicated in Mac copy.
- Works Test: build a registry from the canonical Cursor manifest and no Cursor
  record. Assert the card carries the exact catalog `installHint`, install docs
  URL, `agent login`, login docs URL, and full trust disclosure. Trigger its
  Re-check and assert the recording seam receives only `cursor_agent`, not a
  full-bench request; return ready and assert that card flips in place.
- Proof: `SetupCursorPresentationTests`, `CLISetupGroupingTests` (closeout via
  `check.sh`); layout proof if the card changes the roster's geometry.

### FCS-S04 — Selection surfaces stop over-claiming

- Goal: composer seat list and capacity strip agree with the tally. Two concrete
  fixes: `HomeNewRunPane.notReadyOrParked` is built from **supported drivers**, so
  a driver with no record is not silently treated as up; and
  `AppModel.composeBench` stops mapping `.none` to `"Not detected"` — a
  never-probed seat reads **"Not checked"** with the scan as its action.
- Truth owner: the tally + `BenchReadiness` / `TeamAssembler.readyDriverIds`
  (already correct — the display layer must adopt them).
- Lie-prone layer: any `for record in toolStatuses` filter used to decide what is
  *wrong*; it can only ever see drivers we already looked at.
- Works Test: with an empty cache, no source is painted as live capacity and no
  unmeasured seat is offered as runnable; with one ready source, exactly that one
  is offered.
- Exact files/types: `AppModel.composeBench`; `HomeNewRunPane.notReadyOrParked`
  in `HomeView.swift`; `CapacityStripModel.updateNotReadyOrParked`; projector
  output only (no second tally). Preserve the existing `antigravity` → `agy`
  capacity-id adapter until a separate canonical source-id mapping exists.
- Proof: these are Mac-target tests, so the v2 command
  `scripts/swift-test.sh --filter CapacityStripModelTests` was wrong: that wrapper
  covers the Swift package, not `Apps/AllnighterMac/Tests`. Put deterministic
  cases in `CapacityStripModelTests` / `AppModelTests` and run them through the
  one closeout `bash scripts/check.sh`; use the Core wrapper only for any new
  projector cases.

### FCS-S05 — Teaching surface

- Goal: `alln help` / bootstrap teach the first scan and state plainly that the
  Cursor **IDE** is not the `cursor_agent` seat.
- Truth owner: `TeachingSnippet` / `HelpTopicRegistry`.
- Works Test: `alln help search cursor` returns the CLI-vs-IDE distinction.
- Proof: teaching/help tests via `scripts/swift-test.sh`.

### FCS-S06 — Closeout

- Goal: promote the tally law + first-scan authority into
  `docs/phases/setup/00_…` and `01_…`; add the regression laws (§11) to the
  debugger law backlog; archive this packet.
- Works Test: founder first-open dogfood PASS on a clean host.
- Proof: `bash scripts/check.sh` + founder note.

---

## 11. Regression laws (must never happen again)

| # | Law | Enforced by |
| --- | --- | --- |
| **FCS-L1** | No surface prints a readiness ratio whose numerator was never measured. Never-scanned is its own state with its own copy. | `BenchTally` carries no ratio in `.neverScanned`; projector test |
| **FCS-L2** | No "what is wrong" set is derived by filtering existing probe records, and no absent record is rendered as a detection result. Enumerate supported drivers; a missing record reads "not checked". | S04 test over an empty record set |
| **FCS-L3** | `ready` comes only from a returned smoke token. Never from presence, a running IDE, a config file, a Keychain item, or a vendor dashboard. | `ModelSetupStatus.isSmokeReady` stays the single gate |
| **FCS-L4** | No launch-time or on-appear path may spawn a CLI, login shell, or `Process`. A new first-run surface must have a wall-reachable "zero children until pressed" gate. | `LaunchAuthorityProbeTests` + the 2026-08-10 TCC packet's standing rule |
| **FCS-L5** | Exactly one owner computes the bench tally. A second surface recomputing `X/Y` is a regression, not a convenience. | Projector in Core; call sites read it |
| **FCS-L6** | Cursor IDE presence never seats `cursor_agent`, and product copy never calls the IDE the seat. | `SetupCursorPresentationTests` + copy review |

---

## 12. Out of scope

- Capacity acquire policy, `alln serve`, remote relay (separate 2026-08-10
  packets). Do not re-open silent capacity waves to "fix" setup.
- New vendor drivers, pricing, iOS companion.
- Rebuilding the cut cinematic 6-scene onboarding.
- Keychain reads, vendor dashboards, IDE process inspection, or any other
  inferred readiness source.
- Repealing process-quiet for returning launches with a warm cache.
- Auto-installing CLIs (we guide; the user installs — `01_…` §14).

---

## 13. Founder decisions (defaults apply if unanswered)

1. **Shape A trigger:** v3 resolves the v2 ambiguity against standing law:
   framed Home content with one primary **Find my team**; no auto-open sheet.
   The roster is the result/recovery surface. A sheet requires a new explicit
   founder reversal of `00_…` §3 and `RootView`'s Home-first rule.
2. **Minimum to enter Home:** keep non-trapping (skip at 0 ready) vs soft-gate?
   → **Default: keep non-trapping.** It is existing law.
3. **Cursor without the CLI:** ~~in-app instructions only, or also an install
   one-liner?~~ Largely resolved — the catalog already ships both (§8).
   Remaining call: do we surface the `curl … | bash` install line in-app as
   copyable text?
   → **Default: yes, copyable, plus the docs link. We never run it for them.**
4. **`installedNotProbed` disclosure:** show "installed, not checked" after a
   resolve-only pass?
   → **Default: not in v1.** The case exists in the enum; adding it now widens the
   probe-authority surface for a cosmetic gain.

---

## 14. Done when

- [ ] An unscanned first open never shows `0/<catalog> ready`, and never shows
      warning amber for "we haven't looked."
- [ ] One projector owns the tally; badge and thread empty state read it. The
      setup header keeps its distinct available-CLI/model sentence and does not
      invent another readiness ratio.
- [ ] One framed first scan finds installed CLIs and partitions
      ready / needs-a-step / not installed, from a press.
- [ ] Cursor-without-Agent is one obvious card that never calls the IDE the seat.
- [ ] No selection surface (composer, capacity strip) claims an unmeasured seat.
- [ ] Returning warm-cache launch stays process-quiet; TCC-reset dogfood shows
      zero dialogs when the user touches nothing.
- [ ] Regression laws FCS-L1…L6 each have a named test or an explicit waiver.

---

## 15. Truth owner / lie-prone layer / missing proof

```text
Tier: T2 SSOT (readiness chrome + first-run routing) — T3 if probe authority regresses
Symptom: first open → 0/9 ready in warning amber, seats offered, zero probes run
Bug fingerprint: catalog-size denominator over an empty record array
  (BenchHealthBadge + ThreadEmptyStateBody) + absence-of-record read as
  "nothing down" (HomeNewRunPane.notReadyOrParked) + absence-of-record read as
  "Not detected" (AppModel.composeBench) + no first-scan affordance
Truth owner: SetupStore probe records + CLIDetector smoke; bench tally projector (missing)
Lie-prone layer: any surface that divides by totalToolCount, or filters
  toolStatuses to decide what is broken
Missing proof: empty-cache tally test; "frame rendered, nothing spawned" gate;
  Cursor-without-CLI card; supported-set derivation of the capacity down-set
Fix boundary: honest counts + one framed first scan. No silent launch spawn, no
  inferred readiness, no hard gate, no capacity/serve changes
Proof command:
  scripts/swift-test.sh --filter 'BenchTallyProjectorTests|LaunchAuthorityProbeTests'
  bash scripts/check.sh   (closeout — Mac app call sites)
  Founder: tccutil reset → open → touch nothing → zero dialogs, honest CTA
```

---

## 16. Version history

| Ver | Date | Author | Change |
| --- | --- | --- | --- |
| v1 | 2026-08-10 | Intake (dogfood code red) | Claim, RCA, Shape A/B, slices FCS-S00…S06 |
| v2 | 2026-08-10 | Opus pass | Named the ratio (not the zero) as the lie; found the absence-of-record trap in both directions — the capacity down-set silently reads "nothing wrong" and `composeBench` asserts "Not detected" without detecting; added first principles + anti-pattern table; made Shape A/B a decision table with a recommended default and a hard press-not-appear constraint; specified the missing `BenchTallyProjector` in Core (with the reason: Mac target has no mid-slice proof path); made the Cursor path implementable from the shipped manifest; added regression laws FCS-L1…L6; gave every slice a truth owner, lie-prone layer, Works Test, and a real proof command |
| v3 | 2026-08-10 | Sol review | Corrected the empty-thread and setup-header scope; bound tally freshness, dedupe, parked, and unknown-manifest behavior; reconciled Shape A with Home-first launch law; exposed the dropped Cursor login-doc field and full-scan card-action bug; named exact files/types; replaced state-only and wrong-target proofs with recording/falsifiable gates; made S01 the standalone morning dogfood slice and documented the Core-vs-Mac proof wall. |
