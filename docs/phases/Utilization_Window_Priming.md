# Utilization - Boost Window

Status: Draft founder note - design aligned; no implementation approved
Owner: AllnighterCore + AllnighterEngine + Mac Settings + CLI/MCP contracts
Updated: 2026-06-22 (aligned to Boost window mockup + build spec;
value model, Settings surface, timing model, states, and data model)

## Founder Intent

Raw request:

```text
Small but powerful utilization hack.

Some high-value AI services appear to use a rolling session window that starts
when the first query lands. If the user first asks Claude at 6:00 AM, the next
reset may land at 11:00 AM. If Allnighter sends a tiny query at 3:30 AM, the
reset may land around 8:30 AM, giving the user more useful waking-hour capacity.
Do the same game for Codex. Brainstorm a Settings page surface, perhaps called
"Utilization".
```

Product value:

```text
Align paid AI worker windows with the user's actual workday.
```

This is a very Allnighter idea: the product already exists to make the user's
paid bench show up to work. Boost window adds a small local seed so the bench
is less likely to waste its first reset while the user is asleep or away.

## Design Handoff (visual SSOT)

The product surface is **designed and specced**. Implementation must match:

- `docs/phases/mockups/boost-window/README.md` - handoff pack entry
- `docs/phases/mockups/boost-window/Boost Window - Build Spec.md` - mechanic,
 timing model, screen anatomy, states, honesty rules, data model, acceptance
 criteria
- `docs/phases/mockups/boost-window/Boost Window (interactive mockup).html` -
 visual + interaction source of truth (open in any browser)
- `docs/phases/mockups/boost-window/design-tokens/` - color, type, spacing

This phase doc owns product semantics, architecture reuse, CLI/MCP contracts,
and risks. The mockup pack owns layout, copy, motion, and visual tokens.

## The Unlock (Corrected Value Model)

The capacity that matters is the per-session allowance, not wall-clock time. Each
provider refills capacity in a rolling 5-hour window (a "bucket") whose clock
starts on the **first query** and then auto-resets every 5h while in use. A bucket
holds a fixed allowance; unused allowance does **not** bank - it is lost at the
reset. (Verified on both as of 2026-06-22: Claude Code statusline shows "5h /
% remaining / reset time"; the Max plan panel shows "Current session - resets in
N hr - % used". Codex behaves the same nominal 5h way.)

For a heavy user the binding constraint is the allowance, so the lever is **where
the reset boundary lands relative to the hours actually worked**.

Worked example (heavy morning peak, window placed at 6:00 AM-11:00 AM):

```text
No boost: first query 6:00 opens bucket 6:00-11:00. The whole peak shares ONE
 bucket and the reset lands at 11:00 - after the peak is over, useless.

With boost: a seed query at 3:30 opens bucket 3:30-8:30 (~untouched while asleep).
 Work 6:00-8:30 draws on it; at 8:30 it RESETS into a fresh bucket
 8:30-1:30 drawn on 8:30-11:00.

Net: TWO full buckets inside the SAME five-hour peak instead of one (~ 2x).
```

Headline promise (ship as-is from design):

```text
2x the capacity when you need it most.
```

UI counts buckets as `1 -> 2` inside the selected 5-hour window, not across the
whole day. Do not use a whole-day `2 -> 3` or `+50%` headline - that overstates
v1 and is not what the mockup shows.

Two honest tiers of value:

- Tier 1 (PRIMARY, the headline): reset **placement** - get a second fresh bucket
 during your chosen 5-hour peak. No scheduled work required.
- Tier 2 (secondary): **reclamation** - if the user does queue overnight work, the
 otherwise-wasted pre-dawn bucket runs real work and still hands off a fresh
 reset at peak start.

Honesty boundary (keeps the no-fake-quota law intact): a "bucket" is one real,
observable session reset. We depict **when** resets happen (sourced/observed), never
**how much** quota exists. No token counts, no "% remaining", no cost, no
guaranteed-capacity claims. The `2x` / `1 -> 2` number is a count of real reset
windows inside the user's peak, honestly `1x` / `+0` when a setting adds no
bucket (see "no quiet run-up" state).

## Settings Concept: One Window, One Graph

The screen is governed by a **single placement control** that drives a reactive
zoom chart, a 24h minimap, and a live headline. Everything else is derived.

**User-facing name:** Boost window (Settings -> Utilization -> Boost window).

**The one setting the user moves:** where their **5-hour peak window** sits in
the day - drag the bracket on the 24h strip (snap 15 min; arrow-keys when
focused). Default `08:00` window start.

**Derived automatically (not user-adjustable in v1):**

```text
WINDOW = [S, S+300] // S = windowStart; 300 min = 5h
RESET_MID = S + 150 // fresh reset auto-centered in the window
SEED_FIRES_AT = S - 150 // tiny seed query, 5h before RESET_MID
```

Reset placement is auto-centered for maximum boost. Do **not** expose a reset
dial in v1 - users would only detune their own boost. (Possible future "advanced
nudge"; out of scope now.)

**The graph (decided - match mockup):**

- **Zoom chart** (right of hero card): the selected 5 hours, two tracks -
 *Normally* (one bucket; reset at window end, "too late") vs *With boost*
 (seeded bucket + fresh bucket, amber, `+1 bucket`, `fresh reset - <time>` at
 mid-window).
- **Stat column** (left): `Your peak 5 hours` / `1 -> 2 buckets` / big `2x` +
 `the capacity / same 5 hours`.
- **24h minimap strip**: faint overnight "usually quiet" band, seed dot
 (`seed - <time>`), draggable window bracket (`<start> - <end>`).
- **Soft note** below strip: calm blue when seed falls in idle/overnight hours;
 amber warning when seed falls in daytime ("only boosts if you're idle then").

Chart honesty rules (hard):

- A bucket = a real session reset, not a quota amount. Never render token counts,
 "% quota", cost, runtime, or "guaranteed capacity".
- If the window placement adds no usable bucket (no quiet run-up), the graph and
 headline honestly collapse to `1x` / `+0`.

The single window placement is the v1 surface; see "Reset Grid (v2)".

## Hard Precondition: Quiet Run-Up

The boost **only works if there is a quiet run-up before the window** - roughly
no agent activity from `SEED_FIRES_AT` through `S`. If the user is already
running agents into their window, their bucket phase is already set, there is
nothing to seed, and the gain is **zero**. The UI must say so honestly:

```text
No quiet run-up. Nothing to seed - move it after some downtime.
```

Exact activity heuristic is an implementation decision; the UI contract is the
boolean state.

## Reset Grid (v2)

Buckets chain every 5h once a session starts, so a single morning seed
effectively sets the reset **grid** for the whole day (reset at 9 -> next at 2 -> 7).
The grid only holds if the user keeps touching the source near each boundary; a
long mid-day gap lets the next bucket start late and drift.

v2 ("hold the grid"): Allnighter sends a tiny re-seed touch at each scheduled
boundary the user has not already hit, locking resets to chosen times all day. More
spend + more automation + more provider-terms exposure - explicitly v2. v1 ships
the single Boost window only. The Settings surface can later expand to a small
list of target reset times (default: one).

## Source Notes

Planning evidence as of 2026-06-22:

- Anthropic's Claude Pro support page says session-based usage limits reset every
 five hours, and Claude Code shares limits with Claude on Pro/Max plans:
 `https://support.claude.com/en/articles/8324991-about-claude-s-pro-plan-usage`
 and `https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan`.
- OpenAI's Help Center says Free-tier GPT-5.5 uses a five-hour window, while
 Plus/Pro limits may vary with system conditions:
 `https://help.openai.com/en/articles/9275245-using-chatgpt-s-free-tier-faq`
 and `https://help.openai.com/en/articles/6950777-what-is-chatgpt-plus`.
- OpenAI's Codex page confirms Codex spans app/editor/terminal surfaces, but this
 doc does not treat any Codex five-hour behavior as an official contract:
 `https://openai.com/codex/`.

Important inference rule:

```text
Provider docs and local observations may justify an opt-in experiment.
They do not justify fake "capacity remaining" claims.
```

All provider-specific window behavior must be verified from provider messages,
official docs, or local dogfood observations before becoming product copy.

## Relationship To Existing Docs

This doc is narrower than `docs/phases/parked/Utilization_Admission_Control.md`.
Admission control asks whether a worker can accept a specific attempt now.
Boost window asks whether the user wants one tiny, scheduled, sourced seed so a
known or suspected rolling window aligns with their peak.

Read with:

- `docs/phases/mockups/boost-window/` - visual + build spec (SSOT for UI)
- `docs/phases/parked/Utilization_Admission_Control.md`
- `docs/phases/Pending_Work_And_Drain.md`
- `docs/phases/Stalled_Work_Watchdog.md`
- `docs/phases/Mac_Standalone_App_And_Background_Coordinator.md`
- `docs/phases/CLI_Implementation_Contract.md`
- `docs/phases/threads/04_Observed_Usage.md`
- `docs/phases/Team_And_Skill_Catalogs.md` for Settings navigation

## Non-Goals

- No quota dashboard.
- No billing dashboard.
- No predicted remaining quota, cost, runtime, token burn, or task difficulty.
- No hidden background prompt loops.
- No provider-limit evasion, scraping, or synthetic keepalive churn.
- No automatic pay-as-you-go credit purchase or acceptance of API credit prompts.
- No project-context seed that reads repo files merely to start a window.
- No silent worker substitution.
- No claim that boosting guarantees capacity.
- No per-provider window placement in v1 (one window, provider chips for on/off).
- No reset dial or manual `RESET_MID` nudge in v1.
- No `preview state` bar from the mockup (review-only).

## Product Shape

User-visible claim:

```text
2x the capacity when you need it most.
```

How? explainer (ship from mockup):

```text
Your capacity refills every 5 hours, but that reset usually lands after your busy
stretch. Allnighter triggers an early one so a fresh bucket resets mid-window -
two full buckets in the same five hours, not one.
```

Honesty footnote (ship as-is):

```text
Real resets only - never quota, tokens, or cost. Needs downtime before your
window, or there's nothing to seed. Off by default.
```

Never:

```text
Claude will have 100% capacity at 8:30 AM.
Codex has 47 minutes left.
We saved 63% quota.
This seed is free.
```

## Settings Surface

Navigation (flat sidebar row — v1 has one screen, no Utilization subsection):

```text
Settings sidebar (lane-agnostic block, top):
  CLIs
  Default model
  Boost window          <- third row; icon: gauge.with.dots.needle.33percent
---
  CODE / Teams / Skills
  ...
```

Deep link: Settings > Boost window (no nested Utilization parent until a second
utilization screen ships).

Lane-agnostic; sibling to CLIs and Default model (not inside Code/Design/Copy
catalogs).

Screen anatomy (top -> bottom - match mockup):

```text
1. Header
 - Eyebrow: Boost window
 - Title: 2x the capacity when you need it most.
 - How? one-liner
 - Master toggle (right)

2. Hero card
 - Stat column: Your peak 5 hours / 1 -> 2 buckets / 2x / subcopy
 - Zoom chart: Normally vs With boost for the selected 5h
 - 24h minimap: usually-quiet band / seed dot / draggable window bracket
 - Soft note: idle (blue) vs daytime seed (amber)

3. Applies to
 - Provider chips (Claude, Codex, ...) - tap to include/exclude
 - One line: One window, every CLI you switch on.
 - Not the CLI sign-in/setup screen

4. Honesty footnote (shield + copy above)
```

Settings fields (v1):

| Field | Type | Notes |
|---|---|---|
| `boostEnabled` | bool | Master on/off. **Off by default.** |
| `windowStart` | time-of-day | Minutes from midnight, snap 15. The only time control. |
| `appliesTo` | set of provider ids | Which connected CLIs the window covers. |

CLI connection, sign-in, and billing live on the existing CLI-setup screen - not
here.

## UI States

| State | Trigger | UI |
|---|---|---|
| **On - calibrated** | boost on, reset observed, quiet run-up | Full chart, `1 -> 2`, `2x`. |
| **On - unknown reset** | provider just enabled; no observed reset yet | Chart dimmed/dashed, `estimated` badge. |
| **No quiet run-up** | activity before window | One bucket, `1x`, `+0`. Honest collapse copy. |
| **Needs you** | sign-in or billing prompt | Overlay; never auto-confirm. Paused until resolved. |
| **Off** (default) | boost disabled | Dimmed card, enable CTA. |

Exact copy for each state is in the interactive mockup - lift verbatim.

## Make The Idea Better

Place the peak window, not a raw seed time.

The user thinks "I go hardest 8a-1p." Allnighter derives `SEED_FIRES_AT` and
`RESET_MID` from that placement. If window length is unknown, use a labeled
assumption and record the result after the first observed reset.

Piggyback on real overnight work.

If Claude or Codex already received a real user-authorized run during the seed
band, Allnighter should mark that source seeded and skip the synthetic seed. The
best seed is no extra prompt.

Make the seed harmless and boring.

The seed prompt should be source-specific, minimal, non-mutating, and repo-free.
Example intent:

```text
Reply with exactly "ready". Do not inspect files, use tools, or change anything.
```

Driver implementations should use the safest available non-mutating path. If a
source cannot run a repo-free or non-mutating seed, leave it unsupported until
that can be proven.

Treat "reminder mode" as v0.

Before unattended seeding, the first product slice could simply notify the user:

```text
Seed Claude now to align your mid-window reset?
```

That gives dogfood proof without quiet background quota spend.

Add a utilization receipt.

Every seed should produce a tiny local receipt:

```text
source, model/account label, scheduledAt, startedAt, finishedAt, outcome,
observed reset text, raw snippet cap, paid-prompt refusal if any
```

The receipt can surface in diagnostics or activity log, but must not become a
Project thread turn. v1 Settings does not ship a separate Observations panel -
state and copy on this screen carry the user-facing truth.

Learn conservatively.

Allnighter can learn:

- "provider reported reset at 8:31 AM";
- "first success after limit happened 5h 4m later";
- "seed did not surface any reset text";
- "window behavior changed; confidence downgraded."

Allnighter must not learn:

- "the user has X quota left";
- "this task will fit";
- "tomorrow's capacity is guaranteed."

## Execution Policy (engine - not v1 Settings UI)

These rules govern `alln serve` scheduling; they are not separate Settings rows
in v1:

- Run at most one seed per enabled source per local day.
- Skip if the source was already touched during the seed band (real work counts).
- Skip on battery below threshold (TBD).
- Skip if Mac is asleep (no wake promise in v1).
- Never accept paid credit prompts.
- Stop on auth, billing, manual, or provider-objection prompts.

## Architecture Reuse (Build Less)

Most of this already exists for the REACTIVE (cooldown -> resume) path. Boost
window is the PROACTIVE mirror. Reuse, do not reinvent:

- `CapacityObservation` (`AllnighterCore/CapacityObservation.swift`) already
 carries `source`, `observedResetAt`, `rawSnippet`, `wakeAfter`,
 `sourceConfidence` - parsed from real CLI output and JSON-projected. This IS
 the observation type. Do NOT add a parallel `UtilizationObservation`.
- `SourceCapacityLedger` already ledgers these per source - it is the calibration
 store.
- `PendingWakePlanner` + `PendingCapacityResumeWriter` already compute "wake at
 time T because capacity resets then". Seeding is the same wake mechanism aimed
 at OPENING a session at `SEED_FIRES_AT` instead of RESUMING after a cooldown.
- `alln serve` (`AllnighterCLI.runServe`) is the resident loop that fires
 scheduled seeds when enabled.

Genuinely new surface: `BoostWindowSettings` + provider boost state + seed event
semantics + this Settings screen + CLI/MCP contract. Every real run's
`observedResetAt` continuously recalibrates the window for free.

## Data Model (Settings + engine)

```swift
struct BoostWindowSettings {
 var enabled: Bool = false // off by default
 var windowStart: Int // minutes from midnight, snap 15
 var appliesTo: Set<ProviderID> // CLIs the window covers
}

struct ProviderBoostState {
 let id: ProviderID // .claude, .codex, ...
 var connected: Bool // CLI setup screen owns connection
 var signedIn: Bool
 var lastObservedReset: Date? // nil => "unknown reset" (estimate)
 var needsAttention: AttentionKind? // .signIn, .billingPrompt
}
```

Derived timing (display + schedule):

```text
RESET_MID = windowStart + 150
SEED_FIRES_AT = windowStart - 150 // wrap mod 1440; may be previous calendar day
```

Quiet-run-up check: inspect recent activity in `[SEED_FIRES_AT, windowStart]`.
If active => no-quiet-run-up state.

## Calibration (Measure, Do Not Assume)

Both providers are nominally 5h, but treat each source+account window as
measured, not assumed-shared. First enable = a calibration run: seed once, parse
`observedResetAt` from output, derive the real window, then schedule. Until
calibrated, the chart and schedule are a **labeled assumption** (`estimated`
badge). Codex needs this more: subscription window behavior across
app/editor/terminal is genuinely uncertain, and the Claude model may not transfer.

## Admission: Seed Only When It Helps

A seed must change the outcome or be skipped - never spend for nothing:

- Skip if a fresh bucket would already be available at `RESET_MID` (no early
 touch expected and no queued overnight work) - seeding buys nothing.
- Seed (Tier 1) when an early/incidental touch would otherwise start the peak
 bucket early; or (Tier 2) when there is real queued work to place in the
 pre-window bucket.
- Skip when there is no quiet run-up - UI shows `+0` honestly; engine should not
 fire a pointless seed.

Shares the admission spirit of `Utilization_Admission_Control.md` (parked).

## SSOT

Truth owner:

```text
AllnighterCore owns BoostWindowSettings, seed schedule semantics, and seed event
records. Reset/cooldown OBSERVATIONS reuse CapacityObservation +
SourceCapacityLedger - do NOT add a UtilizationObservation.
AllnighterEngine owns source-specific seed execution and parser adapters.
alln serve owns scheduled resident execution when enabled.
Mac Settings renders and edits Core policy; it does not invent availability.
Mockup pack owns visual layout, copy, motion, and tokens.
```

Lie-prone layers:

- Settings can imply boosting creates capacity.
- Scheduler code can turn unknown windows into fake precision.
- Driver parsers can mistake generic text for a reset guarantee.
- Background execution can become an unbounded keepalive loop.
- Billing prompts can be accidentally accepted if treated like normal terminal
 input.

New semantic rules:

- A seed is a user-enabled utilization event, not Project work.
- A seed may spend subscription usage.
- A seed must be at most once per enabled source per configured local day.
- A seed must be non-mutating by mechanism or unsupported.
- A seed must stop on auth, billing, manual, or provider-objection prompts.
- A seed success only proves the source answered; it does not prove future
 capacity.
- A seed observation is local, timestamped, source-labeled, and resettable.

Duplicate truth to avoid:

- Per-source window placement outside `BoostWindowSettings` (v1).
- GUI-only "next reset" state.
- Driver-local cooldown ledgers separate from shared utilization/admission
 observations.
- Activity copy that says "capacity" without a sourced observation.

## CLI/MCP Surface Sketch

Not Ready for Implementation until the command/tool contract is fully specified,
but the direction should be CLI/MCP-first and aligned to `BoostWindowSettings`.

Possible CLI:

```bash
alln utilization boost status --json
alln utilization boost show --json
alln utilization boost set --enabled true --window-start 08:00 --applies-to claude,codex --json
alln utilization boost seed --source claude --json
alln utilization observations clear --source claude --json
```

Possible MCP:

```text
utilization_boost_status
utilization_boost_get
utilization_boost_update
utilization_boost_seed
utilization_observations_clear
```

JSON shape sketch:

```text
BoostWindowSettingsJSON
- enabled
- windowStart // minutes from midnight
- appliesTo[] // provider ids

ProviderBoostStateJSON
- sourceId
- displayName
- connected
- signedIn
- lastObservedReset?
- needsAttention? // signIn | billingPrompt
- derivedSeedAt? // SEED_FIRES_AT from windowStart
- derivedResetMid? // RESET_MID from windowStart
- quietRunUp // bool for UI state
- blockers[]

UtilizationSeedEventJSON
- id
- sourceId
- scheduledAt?
- startedAt
- finishedAt?
- outcome: succeeded | skipped | authRequired | billingPrompt | rateLimited |
 providerRejected | unsupported | failed | noQuietRunUp
- rawSnippetRef?
- observation? // CapacityObservation projection
```

Exit/error examples:

```text
UTILIZATION_SOURCE_NOT_FOUND
UTILIZATION_SOURCE_UNCONFIGURED
UTILIZATION_SEED_UNSUPPORTED
UTILIZATION_SEED_ALREADY_RAN_TODAY
UTILIZATION_AUTH_REQUIRED
UTILIZATION_BILLING_PROMPT
UTILIZATION_PROVIDER_REJECTED
UTILIZATION_NO_QUIET_RUNUP
```

## Privacy, Billing, And Permission Risks

This feature touches high-risk areas:

- It spends subscription usage on purpose.
- It may run while the user is asleep.
- It invokes authenticated local CLIs.
- It may encounter billing or API-credit prompts.
- It may reveal provider/account state.

Guardrails:

- Off by default.
- Explicit per-source opt-in via Applies to chips.
- Visible window placement, seed time, and last receipt (diagnostics).
- No automatic purchase, credit enablement, or paid fallback.
- No browser scraping by default.
- No project file access for seeds.
- No retries beyond a small, explicit failure policy.
- No wake-from-sleep promise in v1.
- Easy pause (master toggle) from Settings.

Provider terms must be reviewed before shipping unattended seeding. If a provider
disallows synthetic automation or the CLI asks the user to confirm usage, stop
and surface the blocker (needs-you state).

## Trusted Workflow Slice

First useful slice:

```text
user opens Settings > Utilization > Boost window
-> places 8:00 AM-1:00 PM window, enables Claude + Codex
-> Allnighter records BoostWindowSettings and schedules seed at 5:30 AM
-> at 5:30 AM alln serve runs one minimal seed per enabled source if Mac is awake
-> screen shows calibrated state with fresh reset at 10:30a on the zoom chart
-> if billing/auth prompt appears, needs-you overlay; never auto-confirms
```

Even smaller dogfood slice:

```text
Settings shows derived seed time from window placement
-> user clicks "Seed now" (diagnostic or v0 reminder path)
-> Allnighter records the outcome and any observed source text
```

## Works Test

No real provider quota is required for deterministic proof.

Fake-clock Works Test:

```text
Given boost is enabled with windowStart 08:00 and appliesTo includes Claude,
when the fake clock reaches 05:30 (SEED_FIRES_AT), alln serve invokes the fake
Claude seed exactly once, records a UtilizationSeedEvent receipt, and exposes the
same result through CLI and MCP JSON.
```

Negative proofs:

```text
The fake driver emits a billing prompt. The seed stops, records
UTILIZATION_BILLING_PROMPT, does not send follow-up input, and Settings shows
needs-you rather than calibrated.

Activity exists in [SEED_FIRES_AT, windowStart]. UI shows no-quiet-run-up:
1x, +0, collapsed chart; engine skips the seed.
```

Display proof:

```text
The Boost window screen matches mockup acceptance criteria: one draggable window,
zoom chart 1-bucket vs 2-bucket, no quota percentage, cost estimate, or
guaranteed-capacity copy. All five states render (calibrated, estimated,
no-quiet-run-up, needs-you, off).
```

Live provider proof is dogfood-only manual test until provider terms and
official/local behavior are reviewed.

## Done When

- User can configure Boost window from Settings > Utilization.
- UI matches `docs/phases/mockups/boost-window/` acceptance criteria.
- CLI and MCP expose the same `BoostWindowSettings`, status, seed, and observation
 contract.
- `alln serve` can run one scheduled seed per enabled source per local day.
- Seeds are non-mutating, minimal, and receipt-backed.
- Billing/auth/manual/provider-objection prompts stop the seed (needs-you).
- Settings shows sourced observations and honest `1 -> 2` / `+0` states - not
 quota forecasts.
- Deterministic fake-driver tests prove schedule, skip, no-quiet-run-up,
 billing-prompt stop, and no fake-capacity copy.

## Working Decisions (founder + design alignment 2026-06-22)

- **Product name:** Boost window (not "Morning Boost", not "priming" in UI).
- **Headline value:** `1 -> 2 buckets` / `2x` inside the user's chosen 5-hour peak
 (Tier 1 reset placement). Not a whole-day `+50%` claim.
- **One control:** drag the 5-hour window on the 24h strip. Reset is
 auto-centered (`RESET_MID`); no reset dial in v1.
- **Chart:** zoom comparison (Normally vs With boost) + minimap - decided in
 mockup; not an open design exploration.
- **v1 scope:** single Boost window; all-day reset grid is v2.
- **One window, many CLIs:** `appliesTo` chips; no per-provider window placement.
- **Quiet run-up:** hard precondition with honest `+0` UI state.
- **States:** calibrated, estimated (unknown reset), no-quiet-run-up, needs-you,
 off - copy from mockup.
- **A real overnight authorized run counts as the seed** for that source.
- **Build on the same slice** for reminder-mode AND unattended: ship
 schedule/ledger/`alln serve` together; reminder vs unattended is a flag-flip
 after dogfood + provider-terms review.
- **Observations reuse** `CapacityObservation` + `SourceCapacityLedger`; no new
 `UtilizationObservation` type.
- **Navigation:** Settings sidebar — CLIs, Default model, **Boost window** (flat
  row; no Utilization parent until v2).

## Open Questions

- Which providers explicitly allow or discourage a once-daily synthetic seed?
 (Gate before unattended seeding ships.)
- Does Codex subscription usage carry a first-query rolling window in the local
 products Allnighter drives, or only general ChatGPT surfaces? (Calibrate; do
 not assume the Claude model transfers.)
- v2 reset-grid scope: how many target resets to expose, and is re-seeding to
 hold the grid acceptable under each provider's terms?
- Window crossing midnight - supported conceptually; confirm minimap + zoom
 handle wrap for late-night windows.
- Quiet-run-up heuristic: exact activity threshold/window (UI contract is boolean).
