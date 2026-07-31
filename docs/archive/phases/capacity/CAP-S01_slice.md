# CAP-S01 — CapacityWindow model + buckets + anchored decrement

Slice packet per `docs/operations/Execution-Playbook.md`. Read `AGENTS.md` first.
Product truth: `docs/archive/phases/CLI_Capacity_TUI_Sampling.md` (intake FINAL, launch
surface LOCKED). This doc is process + scope only.

```text
Slice:            CAP-S01 — one normalized capacity model in AllnighterCore
Goal:             A single CapacityWindow every driver extractor can emit, carrying
                  everything the strip and the utilization tab need, with no IO and
                  no clock reads inside it.
Out of scope:     PTY probes. GUI. CLI surface. Ledger changes. Rewiring the four
                  existing extractors (that is CAP-S02 — do not touch them).
Truth owner:      AllnighterCore — the new CapacityWindow type.
Lie-prone layer:  Polarity (agy reports REMAINING, everyone else USED) and reset
                  precision (cursor gives a bare month+day with no year or time).
                  Both silently produce plausible wrong numbers.
Works Test:       Unit tests in AllnighterCoreTests, listed below.
Proof command:    swift test --package-path Packages/AllnighterCore --filter CapacityWindowTests
Missing proof:    None — this slice is pure and fully unit-testable.
Done when:        Tests green, committed, extractors untouched.
```

## Why this exists

Four driver extractors shipped tonight (`GrokCapacityLog`, `AgyCapacityLog`,
`KimiCapacityLog`, `CursorCapacityLog`), each returning its own bespoke struct.
They disagree on almost every axis. This slice defines the one shape they will
all normalize into.

Observed divergence — the model must absorb all of it:

| Axis | Real values seen |
| --- | --- |
| Polarity | codex/grok/kimi/cursor report **% used**; agy reports **% remaining** |
| Reset encoding | codex unix epoch; grok ISO8601 with `+00:00`; agy/kimi **relative durations** (`164h 50m`, `1d 18h 3m`); cursor **bare month+day**, no year, no time (`Resets Aug 25`) |
| Scope | weekly, fiveHour, monthly (cursor), session/planClass (claude) |
| Grouping | flat per account; **pools sharing a limit** (agy: Gemini vs Claude+GPT); nested parent/child (cursor: Included → Auto, API) |
| Paid spend | grok `{"val": N}` objects; codex `credits.balance`; cursor **raw dollars** |
| Window behaviour | grok resets on a fixed weekly boundary; **codex re-bases** — its 7-day clock restarts on first use after the previous window closes, so its weeks never align to calendar weeks |

## Required design

### 1. `CapacityWindow`

One value type, `public struct`, `Sendable`, `Equatable`, `Codable`.

Must carry: source id, scope, **both** `usedPercent` and `remainingPercent`
(normalized so callers never guess polarity), absolute `resetAt`, a **reset
precision marker**, `observedAt`, source tier, pool/group label where the vendor
groups models, and an optional plan/tier string.

**Polarity is normalized at construction.** Provide two named constructors —
`init(used:)` and `init(remaining:)` — so no call site can pass the wrong one
positionally. Both derive the other field. There must be no way to build an
inconsistent pair.

**Reset precision is a first-class enum**, e.g. `exact` / `minute` / `day`.
Cursor's `Resets Aug 25` has no time of day; a later slice must not treat it as
minute-accurate. Never store a fabricated time and call it exact.

### 2. Bucket classification

`fat` / `thin` / `empty` / `unknown`. Routing decisions consume the bucket, never
the raw percentage — a parser can be wrong about the number while still right
about the ordering, and exposing the number as the routing input invites the fake
dashboard the packet bans. Thresholds must be **explicit named constants**, not
magic numbers scattered through the classifier.

### 3. Unknown carries a reason

Never a bare nil. Three cases, and they read differently to the user:
`vendorExposesNothing` / `parserFailed(observedAt:)` / `neverSampled`.
Zero-filling a missing percentage is banned outright — a missing sample must be
impossible to confuse with 0%.

### 4. Anchored decrement

```text
remainingCeiling = sample.remaining − (our own observed burn since sample.observedAt)
```

Our burn is a subset of total burn (other machines spend the same account), so
this is a strict **upper bound** and errs only toward caution. Requirements:

- monotone — never rises above the last observation
- clamps at zero, never negative
- with zero recorded burn it equals the observation exactly
- it is an observed anchor minus observed spend. It is **not** a projection, and
  nothing in this slice may forecast future usage

### 5. Purity

No `Date()`, no `Date.now`, no file IO, no environment reads anywhere in this
type or its helpers. Every function that needs the current time takes it as a
parameter. This is what makes the relative-duration and year-rollover cases
testable at all, and the existing extractors already follow this rule — match
them.

## Works Test — `CapacityWindowTests`

1. `init(used: 42)` and `init(remaining: 58)` produce an identical window.
2. A window built from agy's remaining-polarity data reports the same
   `usedPercent` as an equivalent kimi used-polarity window.
3. Reset precision survives: a day-precision reset is never reported as exact.
4. Bucket boundaries, including exactly-on-threshold values.
5. `unknown` cases are distinguishable from each other and from 0%.
6. Anchored decrement: equals the sample at zero burn; decreases monotonically;
   clamps at 0; never exceeds the last observation.
7. Codable round-trip preserves precision marker, scope, and unknown reason.

## Rules

- Read `AGENTS.md` and the routed docs before editing.
- Match the surrounding style — read `GrokCapacityLog.swift` and
  `SourceCapacityLedger.swift` first.
- Swift 6 strict concurrency.
- **Do not modify the four existing extractors.** They stay green as-is.
- Edit narrowly. No unrelated cleanup, no drive-by refactors.
- Run the filtered proof while iterating, never the full suite.

## Commit

```text
git add <the explicit new paths>
git commit -m "CAP-S01: normalized CapacityWindow with buckets and anchored decrement

<what shipped, test result>

Co-Authored-By: Fable 5 via Allnighter"
```

Stage only files you created. The tree has unrelated dirty files — leave them.
Never `git reset --hard`, never rewrite history on `feat/design-chain`.

## Report back

What shipped, the filtered test output, and anything in the design above that
turned out wrong or impossible. If something does not work, say so plainly.
