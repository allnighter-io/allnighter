# Utilization Window Priming

Status: Draft founder note - no implementation approved
Owner: AllnighterCore + AllnighterEngine + Mac Settings + CLI/MCP contracts
Updated: 2026-06-22

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

## SSOT

Truth owner:

```text
AllnighterCore owns UtilizationPolicy, UtilizationSchedule,
UtilizationPrimerEvent, and UtilizationObservation semantics.
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

## Open Questions

- Which providers explicitly allow or discourage a once-daily synthetic primer?
- Does Codex subscription usage have a first-query rolling window in the local
  products Allnighter will drive, or only general ChatGPT surfaces?
- Should v0 be reminder-only to avoid unattended quota spend?
- Should "Utilization" be the final Settings label, or should the row say
  "Workday Windows" with "Utilization" as the section/category?
- Should a real overnight run count as a primer for the same source even when it
  used a different model under the same account window?
- Should the user choose target reset time per source, or one global workday
  start with per-source offsets?
