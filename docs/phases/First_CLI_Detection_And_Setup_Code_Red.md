# First CLI Detection & Setup — CODE RED

Status: **CODE RED — OPEN — v2 (execution-ready)**
Owner: AllnighterMac (`RootView` cold launch, `BenchHealthBadge`, `ThreadEmptyStateBody`,
`ReadinessView` / `SetupViews`) + AllnighterCore (proposed tally projector,
`ProbeFreshnessGate`, `BenchReadiness`) + AgentOS `CLIDetector` / `ModelSetupStatus`
Created: 2026-08-10
Revised: 2026-08-10 (v2 — first-principles, decision table, sliced for a builder)
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
| 2 | Thread empty state repeats **`0/9 CLIs ready`** with a grey dot | `ThreadEmptyStateBody` — `ThreadView.swift` ~90–108 |
| 3 | Composer still lists Auto / Composer 2.5 / Cursor Grok 4.5, each labelled **"Not detected"** | `AppModel.composeBench` — `AppModel.swift` ~545–582 |
| 4 | Capacity strip paints seats as live | `HomeNewRunPane.notReadyOrParked` — `HomeView.swift` ~762–773 |
| 5 | Nothing offers a scan; setup never opens | `RootView` cold launch → `loadCachedSetupState()` only, ~388–399 |

### The two numbers, and why they are both wrong together

| Symbol | Code | What it actually means |
| --- | --- | --- |
| **X = 0** | `AppModel.readyToolCount` (`AppModel.swift` ~438) | Probe records whose status `.isSmokeReady`, minus parked. On a virgin host there are **no records at all** — so this is not "zero ready", it is "zero measurements". |
| **Y = 9** | `AppModel.totalToolCount` (~442) | Every bundled `headlessCLI` manifest, minus parked: Antigravity, Claude Code, Codex, Cursor Agent, Grok, Kimi, Muse, OpenCode, Qwen. Support-catalog size. |

Cold launch calls `loadCachedSetupState()` (~685), which assigns `toolStatuses`
**only if the persisted record set is non-empty**. Empty store ⇒ `toolStatuses`
stays `[]` ⇒ X = 0 forever until the user finds setup on their own. The badge
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

**Shape A — framed first-run scan.** On a host with no completed setup, the
first window presents a small "Find your team" frame whose primary button runs
one `runFullSetupProbe(userInitiated: true)` with live per-source progress.

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

**Recommended default: A over B, with B as the landing.** Ship the framed scan
whose *result surface is the roster* — success lands on Home, anything unresolved
lands on the roster with the founder's cards already partitioned. Neither shape
is worth building until **FCS-S01 lands**, because both inherit the same tally.

**Hard constraint on A:** the scan fires from a press, never from `onAppear`,
never from a sheet that auto-runs on presentation. If the sheet appears and the
user does nothing, zero child processes are spawned. That is the wall-reachable
gate (§9, FCS-S02).

---

## 7. The missing truth owner: one bench tally

Today three surfaces each do their own arithmetic over `toolStatuses`. There is
no owner. Introduce one pure projector in **AllnighterCore** — not in the Mac app
— because the Mac target has no mid-slice proof path (`scripts/swift-test.sh`
covers `Packages/AllnighterCore` only; app tests run at closeout under
`scripts/check.sh`). Putting the law in Core is what makes it provable during
the slice.

Proposed shape (builder may rename; there must be exactly one):

```text
BenchTallyProjector.tally(registry:records:parked:now:) -> BenchTally

BenchTally {
  supported: Int        // headlessCLI manifests, minus parked  (a fact about us)
  measured: Int         // supported drivers WITH a probe record (a fact about this host)
  ready: Int            // records .isSmokeReady, minus parked
  needsStep: Int        // installedNotSignedIn / shimmedNeedsConfirm / probeFailed / rateLimited
  notInstalled: Int
  notChecked: Int       // supported minus measured  — the state that does not exist today
  headline: Headline    // .neverScanned | .partial(ready:needsStep:) | .allReady | .noneReady
}
```

Rules the projector encodes, so no caller can re-derive them wrong:

- `measured == 0` ⇒ `headline == .neverScanned`. **No ratio is emitted at all** —
  the type does not carry one, so a caller cannot print `0/9`.
- `supported` is never a denominator in chrome. It belongs on the setup page
  ("we support 9, found 4"), which is a sentence, not a grade.
- Parked sources are excluded from every count (already true of
  `readyToolCount` / `totalToolCount`; keep it).
- Freshness is *disclosed*, not folded in: `ProbeFreshnessGate` decides whether a
  stored negative may still be asserted, and the tally reports what it reports.

### Required chrome mapping

| Tally headline | Title-bar badge | Thread empty state | Home / composer |
| --- | --- | --- | --- |
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

**The content for this card already ships.** The AgentOS catalog
(`Sources/AgentOSCLI/Catalog/catalog.json`, `cursor_agent.setup`) already carries
the install one-liner, both docs URLs, the login command, the auth patterns, and
the trust disclosure. This slice is rendering, not authoring.

| Fact (verified in the shipped catalog) | Field | Implication |
| --- | --- | --- |
| Seat id `cursor_agent`, display "Cursor Agent" | manifest id | Copy says **Cursor Agent CLI**, never "Cursor" alone |
| Bins are `agent` **and** `cursor-agent` | `setup.bins` | Detection tries both; "not installed" means *neither* resolved |
| Detect `agent --version`; smoke `-p … --model composer-2.5 --trust` | manifest | Ready requires the smoke token; an open IDE proves nothing |
| `curl https://cursor.com/install -fsS \| bash`, then `agent login` | `setup.installHint` | The install card needs no invented copy — render this, copyable |
| `https://cursor.com/docs/cli/installation` / `…/cli/using` | `setup.docsURL`, `setup.loginFlow.docsURL` | Two distinct links; install vs. usage |
| `agent login`, plus "open Cursor once and retry" for Keychain errors | `setup.loginFlow` | The sign-in card opens Terminal with exactly this |
| `SecItemCopyMatching failed`, `not authenticated`, `401`, … | `setup.loginFlow.authErrorPatterns` | Classify as `installedNotSignedIn`, not `probeFailed` |
| `--trust` required, with a full disclosure sentence | `setup.headlessTrust` | The disclosure must survive onto the card; do not silently drop it |

Builder path for the Cursor-without-CLI card:

1. Probe resolves neither `agent` nor `cursor-agent` ⇒ `.notInstalled`.
2. Card headline names the gap in the user's words: *"Cursor Agent CLI not found
   — the Cursor app is not the seat."*
3. Render `setup.installHint` (copyable) + `setup.docsURL`, then `agent login`
   from `loginFlow`, then one **Re-check** that calls
   `runSetupProbe(userInitiated: true, onlyDriverId: "cursor_agent")` and flips
   the card in place.
4. **No IDE detection anywhere in this path.** Do not read the running process
   list, `~/.cursor`, or any Cursor config to soften the card. If we later want
   "installed, not checked", that is `installedNotProbed` after a real resolve —
   still not ready. (The enum case already exists; it is not required for v1.)

---

## 9. Slices

Ship order is S01 → S02 → S03 → S04. **S01 alone removes the worst lie** and is
worth landing on its own.

### FCS-S00 — Packet + routing (this document)

- Truth owner: this packet + `docs/phases/README.md` board row.
- Works Test: a builder can start S01 without asking what the tally means.
- Proof: doc review.

### FCS-S01 — One bench tally, no invented ratio

- Goal: `BenchTallyProjector` in AllnighterCore; badge, thread empty state, and
  setup header all read it. Never-scanned emits a CTA, not `0/9`, and not amber.
- Truth owner: `BenchTallyProjector` (new) over `registry` + `[ToolProbeRecord]`.
- Lie-prone layer: `BenchHealthBadge.label` / `.tone`; `ThreadEmptyStateBody`;
  any future surface tempted to divide.
- Works Test (owner-visible): with an empty `cli_setup.json`, first open shows a
  **Find my team** CTA in neutral tone in both the title bar and the thread empty
  state; with one ready source it shows `1 ready`.
- Proof: `scripts/swift-test.sh --filter BenchTallyProjectorTests` (empty
  records ⇒ `.neverScanned`; parked excluded; partial/all-ready mapping) +
  `bash scripts/check.sh` at closeout for the Mac-layer call sites; GUI proof if
  the pill's footprint changes (`scripts/gui_proof.sh`, `docs/gui/Visual_Proof_Gate.md`).

### FCS-S02 — Framed first scan (Shape A), once, on a press

- Goal: on `setupCompletedAt == nil` **and** zero probe records, present the
  first-run frame whose primary button runs `runFullSetupProbe(userInitiated:
  true)` with live per-source progress; land on the roster if anything is
  unresolved, Home if all clear. Gate fires once until completed or deferred.
- Truth owner: `SetupStore` (`setupCompletedAt`, records) + the once-gate.
- Lie-prone layer: the presentation path — a sheet that scans on appear is
  indistinguishable from a silent launch spawn to macOS and to TCC.
- Works Test: after `tccutil reset`, open the app and **touch nothing** — zero
  child processes, zero dialogs; press the button — exactly one probe wave, real
  found/ready partition; quit and reopen — the frame does not return.
- Proof: `scripts/swift-test.sh --filter LaunchAuthorityProbeTests` plus a new
  case asserting the presented frame spawns nothing until the action fires;
  founder TCC-reset dogfood.

### FCS-S03 — Roster as the recovery UI (Shape B) + Cursor card

- Goal: every supported source has exactly one primary action in its
  `notChecked` / needs-step state; the Cursor-without-CLI card of §8 exists.
- Truth owner: `AppModel.setupCards` / `AppSetupModel` (already enumerates
  supported drivers — extend, do not fork).
- Lie-prone layer: copy that implies the IDE is the seat; multi-step cards.
- Works Test: on a host with Cursor IDE and no `agent` binary, the roster shows
  the Cursor Agent CLI card with install + `agent login` + Re-check, and
  re-check flips it in place without an app restart.
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
- Proof: `scripts/swift-test.sh --filter 'CapacityStripModelTests'` for the
  down-set derivation once it moves behind the projector; Mac call sites at
  closeout.

### FCS-S05 — Teaching surface

- Goal: `alln help` / bootstrap teach the first scan and state plainly that the
  Cursor **IDE** is not the `cursor_agent` seat.
- Truth owner: `TeachingSnippet` / `HelpTopicRegistry`.
- Works Test: `alln help search cursor` returns the CLI-vs-IDE distinction.
- Proof: teaching/help tests via `scripts/swift-test.sh`.

### FCS-S06 — Closeout

- Goal: promote the tally law + first-scan authority into
  `docs/phases/setup/00_…` and `01_…`; add the regression laws (§10) to the
  debugger law backlog; archive this packet.
- Works Test: founder first-open dogfood PASS on a clean host.
- Proof: `bash scripts/check.sh` + founder note.

---

## 10. Regression laws (must never happen again)

| # | Law | Enforced by |
| --- | --- | --- |
| **FCS-L1** | No surface prints a readiness ratio whose numerator was never measured. Never-scanned is its own state with its own copy. | `BenchTally` carries no ratio in `.neverScanned`; projector test |
| **FCS-L2** | No "what is wrong" set is derived by filtering existing probe records, and no absent record is rendered as a detection result. Enumerate supported drivers; a missing record reads "not checked". | S04 test over an empty record set |
| **FCS-L3** | `ready` comes only from a returned smoke token. Never from presence, a running IDE, a config file, a Keychain item, or a vendor dashboard. | `ModelSetupStatus.isSmokeReady` stays the single gate |
| **FCS-L4** | No launch-time or on-appear path may spawn a CLI, login shell, or `Process`. A new first-run surface must have a wall-reachable "zero children until pressed" gate. | `LaunchAuthorityProbeTests` + the 2026-08-10 TCC packet's standing rule |
| **FCS-L5** | Exactly one owner computes the bench tally. A second surface recomputing `X/Y` is a regression, not a convenience. | Projector in Core; call sites read it |
| **FCS-L6** | Cursor IDE presence never seats `cursor_agent`, and product copy never calls the IDE the seat. | `SetupCursorPresentationTests` + copy review |

---

## 11. Out of scope

- Capacity acquire policy, `alln serve`, remote relay (separate 2026-08-10
  packets). Do not re-open silent capacity waves to "fix" setup.
- New vendor drivers, pricing, iOS companion.
- Rebuilding the cut cinematic 6-scene onboarding.
- Keychain reads, vendor dashboards, IDE process inspection, or any other
  inferred readiness source.
- Repealing process-quiet for returning launches with a warm cache.
- Auto-installing CLIs (we guide; the user installs — `01_…` §14).

---

## 12. Founder decisions (defaults apply if unanswered)

1. **Shape A trigger:** framed first-run sheet with one primary **Find my team**,
   vs landing directly on the roster until the first scan completes?
   → **Default: framed sheet, roster as the result surface.**
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

## 13. Done when

- [ ] An unscanned first open never shows `0/<catalog> ready`, and never shows
      warning amber for "we haven't looked."
- [ ] One projector owns the tally; badge, thread empty state, and setup header
      all read it.
- [ ] One framed first scan finds installed CLIs and partitions
      ready / needs-a-step / not installed, from a press.
- [ ] Cursor-without-Agent is one obvious card that never calls the IDE the seat.
- [ ] No selection surface (composer, capacity strip) claims an unmeasured seat.
- [ ] Returning warm-cache launch stays process-quiet; TCC-reset dogfood shows
      zero dialogs when the user touches nothing.
- [ ] Regression laws FCS-L1…L6 each have a named test or an explicit waiver.

---

## 14. Truth owner / lie-prone layer / missing proof

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
Missing proof: empty-cache tally test; "sheet presented, nothing spawned" gate;
  Cursor-without-CLI card; supported-set derivation of the capacity down-set
Fix boundary: honest counts + one framed first scan. No silent launch spawn, no
  inferred readiness, no hard gate, no capacity/serve changes
Proof command:
  scripts/swift-test.sh --filter 'BenchTallyProjectorTests|LaunchAuthorityProbeTests'
  bash scripts/check.sh   (closeout — Mac app call sites)
  Founder: tccutil reset → open → touch nothing → zero dialogs, honest CTA
```

---

## 15. Version history

| Ver | Date | Author | Change |
| --- | --- | --- | --- |
| v1 | 2026-08-10 | Intake (dogfood code red) | Claim, RCA, Shape A/B, slices FCS-S00…S06 |
| v2 | 2026-08-10 | Opus pass | Named the ratio (not the zero) as the lie; found the absence-of-record trap in both directions — the capacity down-set silently reads "nothing wrong" and `composeBench` asserts "Not detected" without detecting; added first principles + anti-pattern table; made Shape A/B a decision table with a recommended default and a hard press-not-appear constraint; specified the missing `BenchTallyProjector` in Core (with the reason: Mac target has no mid-slice proof path); made the Cursor path implementable from the shipped manifest; added regression laws FCS-L1…L6; gave every slice a truth owner, lie-prone layer, Works Test, and a real proof command |
