# Utilization Window Priming

Status: Draft founder note - no implementation approved
Owner: AllnighterCore + AllnighterEngine + Mac Settings + CLI/MCP contracts
Updated: 2026-06-22 (value model corrected to reset-placement / bucket framing;
one-dial settings concept, architecture reuse, calibration, and admission added)

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
paid bench show up to work. Window priming adds a small local nudge so the bench
is less likely to waste its first reset while the user is asleep or away.

## The Unlock (Corrected Value Model)

The capacity that matters is the PER-SESSION ALLOWANCE, not wall-clock time. Each
provider refills capacity in a rolling 5-hour window (a "bucket") whose clock
starts on the FIRST query and then auto-resets every 5h while in use. A bucket
holds a fixed allowance; unused allowance does NOT bank - it is lost at the
reset. (Verified on both as of 2026-06-22: Claude Code statusline shows "5h /
% remaining / reset time"; the Max plan panel shows "Current session - resets in
N hr - % used". Codex behaves the same nominal 5h way.)

For a heavy user the binding constraint is the allowance, so the lever is WHERE
the reset boundary lands relative to the hours actually worked.

Worked example (the founder's real pattern: heavy morning runs ~6-11 AM):

```text
No priming:  first query 6:00 opens bucket 6:00-11:00. The whole peak shares ONE
             bucket and the reset lands at 11:00 - after the peak is over, useless.

Prime 3:30:  a sacrificial bucket opens 3:30-8:30 (~untouched while asleep).
             Work 6:00-8:30 draws on it; at 8:30 it RESETS into a fresh bucket
             8:30-1:30 drawn on 8:30-11:00.

Net:         TWO full buckets usable inside the 6-11 AM peak instead of one.
```

Across a day this is roughly 2 buckets -> 3 buckets - about a +50% boost in
usable capacity during waking hours, with NO overnight work scheduled. The user
simply moved the reset INTO their peak.

Earlier framing error to avoid repeating: priming is NOT "neutral in the clean
case." That reasoning assumed even, wall-clock-bound usage. For bursty heavy use
that would exhaust a bucket, a reset placed inside the peak is a real, large
unlock (the "100 -> 200 units available in the morning" the founder described).

Two honest tiers of value:

- Tier 1 (PRIMARY, the headline): reset PLACEMENT - get a second fresh bucket
  during your peak. No scheduled work required.
- Tier 2 (secondary): RECLAMATION - if the user does queue overnight work, the
  otherwise-wasted pre-dawn bucket runs real work and still hands off a fresh
  reset at workday start.

Honesty boundary (keeps the no-fake-quota law intact): a "bucket" is one real,
observable session reset. We depict WHEN resets happen (sourced/observed), never
HOW MUCH quota exists. No token counts, no "% remaining", no cost, no
guaranteed-capacity claims. The boost number is COMPUTED from the user's chosen
reset time and the measured window; it honestly shows +0 when a setting adds no
bucket.

## Settings Concept: One Dial, One Graph

The screen is governed by a SINGLE control that drives a reactive graph and a
live headline number. Everything else is derived.

- The dial = the time the user wants their fresh morning bucket to land (their
  "reset at 9, not 11" wish). Allnighter derives the primer time:
  `primerTime = targetResetTime - measuredWindowLength`.
- The graph plots capacity across the day, comparing "Regular day" vs "With
  Allnighter", with a shaded working-hours band. As the dial moves, the extra
  bucket visibly appears/disappears and the headline updates:
  `2 -> 3 buckets - +50%` (or honestly `+0 - no boost here`).
- Chart treatment is a live design exploration (step/line chart counting buckets,
  before/after timeline bars, or a refilling sawtooth "tank"). Decision pending;
  the founder is brainstorming this with a designer.

Chart honesty rules (hard):

- A bucket = a real session reset, not a quota amount. Never render token counts,
  "% quota", cost, runtime, or "guaranteed capacity".
- The before/after comparison must never flatter: if a dial position adds no
  usable bucket, the graph and the number say so.

The single morning dial is the v1 surface; see "Reset Grid (v2)".

## Reset Grid (v2)

Buckets chain every 5h once a session starts, so the single morning primer
effectively sets the reset GRID for the whole day (reset at 9 -> next at 2 -> 7).
The grid only holds if the user keeps touching the source near each boundary; a
long mid-day gap lets the next bucket start late and drift.

v2 ("hold the grid"): Allnighter sends a tiny re-prime touch at each scheduled
boundary the user has not already hit, locking resets to the user's chosen times
all day. This is more spend + more automation + more provider-terms exposure, so
it is explicitly v2. v1 ships the single morning boost only. The Settings dial can
later expand to a small list of target reset times (default: one).

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
Window priming asks whether the user wants one tiny, scheduled, sourced first
touch so a known or suspected rolling window aligns with their day.

Read with:

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
- No project-context primer that reads repo files merely to start a window.
- No silent worker substitution.
- No claim that priming guarantees capacity.

## Product Shape

User-visible claim:

```text
Allnighter can align worker reset windows with your workday.
```

Sharper Settings copy:

```text
Start selected workers before you wake so their reset lands when you work.
```

The product should let the user choose a desired reset target, not just a raw
primer time:

```text
Workday starts: 8:30 AM
Prime Claude: 5 hours before workday
Primer time: 3:30 AM
```

If Allnighter later observes a different reset interval, the UI can say:

```text
Claude last reported a reset 5h 2m after first use. Next primer: 3:28 AM.
```

If the interval is unknown:

```text
Claude has no verified reset pattern yet. Prime once and record what happens.
```

Never:

```text
Claude will have 100% capacity at 8:30 AM.
Codex has 47 minutes left.
We saved 63% quota.
This primer is free.
```

## Settings Surface

Add a lane-agnostic Settings destination if this graduates:

```text
CLIs
Utilization

Code
  Teams
  Skills

Design
  Teams
  Skills

Copy
  Teams
  Skills
```

Why top-level:

- Utilization is source/account behavior, not Code/Design/Copy catalog behavior.
- It belongs near CLIs because it depends on authenticated local worker sources.
- It should not be hidden inside individual team editors.

Suggested screen layout:

```text
Utilization

Workday
  Workday starts: 8:30 AM
  Active days: Mon Tue Wed Thu Fri
  Time zone: local Mac time

Window Priming
  Claude Code     on/off   target reset 8:30 AM   prime 3:30 AM   last: observed
  Codex           on/off   target reset 8:30 AM   prime unknown   last: unverified
  Gemini CLI      off      not configured

Primer Policy
  Run only once per source per day
  Skip if already used during the primer band
  Skip on battery below N percent
  Skip if Mac is asleep
  Notify only when action is needed
  Never accept paid credit prompts

Observations
  Last primer, result, source text, observed reset time, confidence
  Reset utilization observations
```

Small, expected controls:

- Toggle per source.
- Time picker for workday start.
- Day-of-week segmented control or checkboxes.
- "Prime now" button per source for manual testing.
- "View source" disclosure for the observed provider text.
- "Reset observations" destructive button.

Status language:

```text
Ready to prime at 3:30 AM.
Skipped today - Claude was already used at 3:12 AM.
Needs sign-in before priming.
Last primer succeeded; no reset message observed.
Last primer hit a limit; next wake observed at 8:31 AM.
```

## Make The Idea Better

Use a target reset, not a target query time.

The user thinks "I start work at 8:30." Allnighter should translate that into a
primer schedule from observed window length, official provider text, or user
override. If the window length is unknown, use a labeled assumption and record
the result.

Piggyback on real overnight work.

If Claude or Codex already received a real user-authorized run during the primer
band, Allnighter should mark that source primed and skip the synthetic primer.
The best primer is no extra prompt.

Make the primer harmless and boring.

The primer prompt should be source-specific, minimal, non-mutating, and
repo-free. Example intent:

```text
Reply with exactly "ready". Do not inspect files, use tools, or change anything.
```

Driver implementations should use the safest available non-mutating path. If a
source cannot run a repo-free or non-mutating primer, leave it unsupported until
that can be proven.

Treat "reminder mode" as v0.

Before unattended priming, the first product slice could simply notify the user:

```text
Prime Claude now to align your 8:30 AM reset?
```

That gives the founder dogfood proof without quiet background quota spend.

Add a utilization receipt.

Every primer should produce a tiny local receipt:

```text
source, model/account label, scheduledAt, startedAt, finishedAt, outcome,
observed reset text, raw snippet cap, paid-prompt refusal if any
```

The receipt should be visible from Settings and optionally from the activity
log, but it should not become a Project thread turn.

Learn conservatively.

Allnighter can learn:

- "provider reported reset at 8:31 AM";
- "first success after limit happened 5h 4m later";
- "primer did not surface any reset text";
- "window behavior changed; confidence downgraded."

Allnighter must not learn:

- "the user has X quota left";
- "this task will fit";
- "tomorrow's capacity is guaranteed."

## Architecture Reuse (Build Less)

Most of this already exists for the REACTIVE (cooldown -> resume) path. Window
priming is the PROACTIVE mirror of it. Reuse, do not reinvent:

- `CapacityObservation` (`AllnighterCore/CapacityObservation.swift`) already
  carries `source`, `observedResetAt`, `rawSnippet`, `wakeAfter`,
  `sourceConfidence` - parsed from real CLI output and JSON-projected. This IS
  the observation type. Do NOT add a parallel `UtilizationObservation` (that is
  the "duplicate truth to avoid" this doc itself warns against).
- `SourceCapacityLedger` already ledgers these per source - it is the calibration
  store.
- `PendingWakePlanner` + `PendingCapacityResumeWriter` already compute "wake at
  time T because capacity resets then". Priming is the same wake mechanism aimed
  at OPENING a session at `workdayStart - windowLength` instead of RESUMING after
  a cooldown.
- `alln serve` (`AllnighterCLI.runServe`) is the resident loop that fires
  scheduled primers when enabled.

So the genuinely new surface is small: `UtilizationPolicy` + `UtilizationSchedule`
+ `UtilizationPrimerEvent` + the Settings dial/graph + the CLI/MCP contract. Every
real run's `observedResetAt` continuously recalibrates the window for free.

## Calibration (Measure, Do Not Assume)

Both providers are nominally 5h, but treat each SOURCE+ACCOUNT window as measured,
not assumed-shared. First enable = a calibration run: prime once, parse
`observedResetAt` from output, derive the real window, then schedule. Until
calibrated, the schedule and graph are a LABELED ASSUMPTION ("no verified reset
pattern yet - prime once and record what happens"). Codex needs this more:
subscription window behavior across app/editor/terminal is genuinely uncertain,
and the Claude model may not transfer.

## Admission: Prime Only When It Helps

A primer must change the outcome or be skipped - never spend for nothing:

- Skip if a fresh bucket would already be available at the target time (no early
  touch expected and no queued overnight work) - priming buys nothing.
- Prime (Tier 1) when an early/incidental touch would otherwise start the peak
  bucket early; or (Tier 2) when there is real queued work to place in the
  pre-dawn bucket.

This turns "the best primer is no extra prompt" from a note into a decision rule,
and shares the admission spirit of `Utilization_Admission_Control.md` (parked).

## SSOT

Truth owner:

```text
AllnighterCore owns UtilizationPolicy, UtilizationSchedule, and
UtilizationPrimerEvent semantics. Reset/cooldown OBSERVATIONS reuse the existing
CapacityObservation + SourceCapacityLedger - do NOT add a UtilizationObservation.
AllnighterEngine owns source-specific primer execution and parser adapters.
alln serve owns scheduled resident execution when enabled.
Mac Settings renders and edits Core policy; it does not invent availability.
```

Lie-prone layers:

- Settings can imply priming creates capacity.
- Scheduler code can turn unknown windows into fake precision.
- Driver parsers can mistake generic text for a reset guarantee.
- Background execution can become an unbounded keepalive loop.
- Billing prompts can be accidentally accepted if treated like normal terminal
  input.

New semantic rules:

- A primer is a user-enabled utilization event, not Project work.
- A primer may spend subscription usage.
- A primer must be at most once per enabled source per configured local day.
- A primer must be non-mutating by mechanism or unsupported.
- A primer must stop on auth, billing, manual, or provider-objection prompts.
- A primer success only proves the source answered; it does not prove future
  capacity.
- A primer observation is local, timestamped, source-labeled, and resettable.

Duplicate truth to avoid:

- Per-source reset schedules outside Core policy.
- GUI-only "next reset" state.
- Driver-local cooldown ledgers separate from shared utilization/admission
  observations.
- Activity copy that says "capacity" without a sourced observation.

## CLI/MCP Surface Sketch

This is not Ready for Implementation until the command/tool contract is fully
specified, but the direction should be CLI/MCP-first.

Possible CLI:

```bash
alln utilization status --json
alln utilization schedule show --json
alln utilization schedule set --source claude --enabled true --target-reset 08:30 --days mon,tue,wed,thu,fri --json
alln utilization prime --source claude --json
alln utilization observations clear --source claude --json
```

Possible MCP:

```text
utilization_status
utilization_schedule_get
utilization_schedule_update
utilization_prime
utilization_observations_clear
```

JSON shape sketch:

```text
UtilizationSourceStatusJSON
- sourceId
- displayName
- configured
- primingEnabled
- nextPrimerAt?
- targetResetAt?
- lastPrimer?
- lastObservation?
- blockers[]

UtilizationPrimerEventJSON
- id
- sourceId
- scheduledAt?
- startedAt
- finishedAt?
- outcome: succeeded | skipped | authRequired | billingPrompt | rateLimited |
  providerRejected | unsupported | failed
- rawSnippetRef?
- observation?

UtilizationObservationJSON
- sourceId
- observedAt
- kind: resetAt | windowLength | rateLimit | authRequired | unknown
- resetAt?
- windowSeconds?
- confidence: high | medium | low
- source: providerText | cliStatus | primer | manual | recoveryObservation
- sourceLabel
```

Exit/error examples:

```text
UTILIZATION_SOURCE_NOT_FOUND
UTILIZATION_SOURCE_UNCONFIGURED
UTILIZATION_PRIMER_UNSUPPORTED
UTILIZATION_PRIMER_ALREADY_RAN_TODAY
UTILIZATION_AUTH_REQUIRED
UTILIZATION_BILLING_PROMPT
UTILIZATION_PROVIDER_REJECTED
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
- Explicit per-source opt-in.
- Visible schedule and last receipt.
- No automatic purchase, credit enablement, or paid fallback.
- No browser scraping by default.
- No project file access for primers.
- No retries beyond a small, explicit failure policy.
- No wake-from-sleep promise in v1.
- Easy pause and reset from Settings.

Provider terms must be reviewed before shipping unattended priming. If a provider
disallows synthetic automation or the CLI asks the user to confirm usage, stop
and surface the blocker.

## Trusted Workflow Slice

First useful slice:

```text
user opens Settings -> Utilization
-> enables Claude primer for weekdays with target reset 8:30 AM
-> Allnighter records a local schedule
-> at 3:30 AM alln serve runs one minimal primer if the Mac is awake
-> Settings shows a sourced receipt and any observed reset/cooldown text
-> the next morning the user sees whether the bench is aligned or needs attention
```

Even smaller dogfood slice:

```text
Settings recommends a primer time from the user's target reset
-> user clicks "Prime now"
-> Allnighter records the outcome and shows exact source text
```

## Works Test

No real provider quota is required for deterministic proof.

Fake-clock Works Test:

```text
Given Claude priming is enabled for weekdays with target reset 8:30 AM and an
observed five-hour window, when the fake clock reaches 3:30 AM, alln serve invokes
the fake Claude primer exactly once, records a UtilizationPrimerEvent receipt,
and exposes the same result through CLI and MCP JSON.
```

Negative proof:

```text
The fake driver emits a billing prompt. The primer stops, records
UTILIZATION_BILLING_PROMPT, does not send follow-up input, and Settings shows
"needs you" rather than "primed".
```

Display proof:

```text
The Utilization screen shows next primer time, last observed source text, and no
quota percentage, cost estimate, runtime estimate, or guaranteed-capacity copy.
```

Live provider proof is a dogfood-only manual test until provider terms and
official/local behavior are reviewed.

## Done When

- User can configure utilization priming from a lane-agnostic Settings page.
- CLI and MCP expose the same policy, status, primer, and observation contract.
- `alln serve` can run one scheduled primer per enabled source per local day.
- Primers are non-mutating, minimal, and receipt-backed.
- Billing/auth/manual/provider-objection prompts stop the primer.
- Settings shows sourced observations, not quota forecasts.
- Deterministic fake-driver tests prove schedule, skip, billing-prompt stop, and
  no fake-capacity copy.

## Working Decisions (founder brainstorm 2026-06-22)

- Headline value = reset PLACEMENT (Tier 1), not overnight reclamation. The pitch
  is "2 -> 3 buckets, ~+50%, no scheduling required."
- The Settings surface is ONE dial (target morning reset time) driving a reactive
  graph + a live, computed boost number. Chart shape is being designed.
- v1 ships a single morning boost; the all-day reset grid is v2 ("hold the grid").
- One global workday start with per-source OFFSETS (each source's measured
  window), not a separate target time configured per source.
- A real overnight authorized run DOES count as the primer for that source - the
  window is per-account, so any touch (regardless of model) opens the session.
- Build on the same slice for reminder-mode AND unattended: ship the
  schedule/ledger/`alln serve` path together; reminder vs unattended is a
  flag-flip after dogfood + provider-terms review (not an architecture fork).
- Observations reuse CapacityObservation/SourceCapacityLedger; no new
  UtilizationObservation type.
- Label: section "Utilization"; user-facing row uses plain-benefit wording
  (working name "Morning Boost"), not the jargon "priming".

## Open Questions

- Which providers explicitly allow or discourage a once-daily synthetic primer?
  (Gate before unattended priming ships.)
- Does Codex subscription usage carry a first-query rolling window in the local
  products Allnighter drives, or only general ChatGPT surfaces? (Calibrate to
  find out; do not assume the Claude model transfers.)
- v2 reset-grid scope: how many target resets to expose, and is re-priming to
  hold the grid acceptable under each provider's terms?
