# 04 - Observed Usage

Status: Fast follow after Work Threads MLP
Owner: AllnighterCore + AllnighterEngine
Updated: 2026-06-15

## Goal

Record and display usage metadata only when a provider or CLI reports it
directly.

This gives users useful accountability without violating the product law against
cost, quota, runtime, or token estimates.

This doc is not the MLP context meter. The MLP may show packet size, included
sources, and truncation by bytes/characters. Token counts belong here only when
reported by a provider/CLI or computed by a known exact tokenizer for that
provider and model.

## Product Law

Allowed:

```text
observed duration
observed input tokens, if reported by the provider/CLI
observed output tokens, if reported by the provider/CLI
observed total tokens, if reported by the provider/CLI
provider-reported usage text, source-labeled and local
```

Banned:

```text
estimated tokens
estimated dollar cost
estimated quota burn
estimated remaining quota
normalizing opaque provider limits into percentages
"$0.00 marginal" chrome unless it is a product-law amendment
preflight token guesses from generic tokenizers
```

If usage is not reported, show "usage unavailable" or omit it. Do not infer.

## Current State

Already exists:

- Legacy `WorkerAnswer.durationMs` for team workers.
- `WorkerRunner` measures `startedAt`, `finishedAt`, and `durationMs`.
- Worker-answer cards show per-worker duration.
- `WorkerScorecard.medianLatencyMs` exists.

Gaps:

- No first-class usage struct.
- No source-labeled token metadata.
- No UI display for scorecard median latency.
- `ExecutionReturn` has start/finish times but no duration helper.
- MLP context reveal has size/truncation but no source-labeled token usage.

## Core Model

Suggested:

```text
ObservedUsage
- inputTokens?
- outputTokens?
- totalTokens?
- source                 # stdout | stderr | output_file | provider_json | manual
- sourceLabel            # "Claude CLI usage footer", etc.
- observedAt
- rawSnippet?            # capped local text for parser proof
```

Attach where usage is observed:

```text
WorkerAnswer.observedUsage?
StageOutput.observedUsage?
ExecutionReturn.observedUsage?
ThreadTurn.observedUsage?   # only for worker_chat turns
```

Prefer attaching usage to the concrete execution result, then deriving timeline
display from that result.

## Parser Rules

- Each parser is driver-specific.
- Parser failure means usage unavailable.
- Store capped raw snippets only for proof/debug.
- Fixtures must cover every parser.
- If a provider changes output format, fail closed.
- If usage appears in streamed output, capture it only when the driver parser can
  identify a stable usage footer/event; do not mine arbitrary prose.

## UI Rules

Turn metadata order:

```text
worker | model | observed duration | usage if reported
```

Examples:

```text
Claude | Opus | 18.4s
Codex | GPT-5.5 | 44.1s | 12.1k tokens reported by codex
Grok | 31.0s | usage unavailable
```

Avoid dollar figures unless a future law explicitly allows source-reported
billing data. Subscription users care more about "which lane is noisy/slow" than
fake precision.

## Ordered Slices

- [ ] USG-S01 - Surface median latency already stored in `WorkerScorecard`.
- [ ] USG-S02 - Add `ObservedUsage` model and Codable fixtures.
- [ ] USG-S03 - Add one driver-specific parser from a real CLI output fixture.
- [ ] USG-S04 - Attach observed usage to worker chat and worker answers.
- [ ] USG-S05 - Add local scorecard aggregation for observed tokens when present.
- [ ] USG-S06 - Add UI metadata display with source labels and unavailable state.
- [ ] USG-S07 - Evaluate provider-reported billing data only as a separate law
  amendment, not as a UI flourish.

## Works Test

```text
Run one worker whose fixture includes provider-reported token usage. Allnighter
stores exact observed usage with source label and raw snippet capped. The turn
shows observed duration and source-labeled token count. Run a worker with no
usage output; Allnighter does not estimate and shows usage unavailable or
nothing.
```

## Proof Command

```text
swift test
scripts/check.sh
```

Parser tests must be deterministic and fixture-backed.
