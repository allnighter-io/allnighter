# CAP-S05 — Capacity history store

Slice packet per `docs/operations/Execution-Playbook.md`. Product truth:
`docs/phases/CLI_Capacity_TUI_Sampling.md`. Read `AGENTS.md` first.

```text
Slice:            CAP-S05 — durable per-window capacity history
Goal:             Persist what acquisition observes, so the utilization tab and
                  unused-at-reset become possible. Retention is in the schema
                  from day one; history is unrecoverable if we skip it now.
Out of scope:     Utilization projection/cards. CLI verbs. GUI. Probes.
                  Any new acquisition trigger.
Truth owner:      AllnighterEngine — CapacityHistoryStore + CapacityWindowRecord.
Lie-prone layer:  Window identity. Codex re-bases its reset timestamp, so naive
                  keying fragments one logical window into many records and
                  silently destroys the averages.
Works Test:       Unit tests, listed below.
Proof command:    swift test --package-path Packages/AllnighterCore --filter CapacityHistoryStoreTests
Missing proof:    None.
Done when:        Tests green, committed, nothing else touched.
```

## Design decisions — MADE, do not re-litigate

I made these. Implement them; if one is genuinely wrong, stop and say so rather
than substituting your own.

### 1. Store one record per **window**, not per observation

Codex alone produced **28,909 readings in six weeks**. The utilization maths only
ever needs *peak used-% per window*, and six weeks of codex is **~16 windows**.
Storing raw observations would be a thousand times the data for the same answer.

### 2. Window identity uses a **tolerance**, because Codex re-bases

Grok has fixed boundaries. **Codex does not** — its 7-day clock restarts on first
use after the previous window closes, and its `resets_at` drifts by *seconds*
within a single cycle. Keying on exact `resetAt` shatters one window into many.

Identity is `(sourceId, scope, resetAt ± tolerance)`. Named constant, default
**15 minutes** — comfortably larger than the observed intra-cycle drift
(seconds) and far smaller than the gap between cycles (days). On write: if an
existing record for the same source+scope has a `resetAt` within tolerance,
merge into it; otherwise open a new record.

### 3. Store facts, filter at read time

The record keeps `firstObservedAt`, `lastObservedAt`, `observationCount`. It does
**not** store a "was this well observed?" verdict.

This matters: coverage filtering moved Codex's average from **49% to 82%** and
flipped the conclusion from downgrade to upgrade. That threshold will be tuned.
If the filter is baked into storage, every tuning pass invalidates all history.
Store the raw facts; let a later projection decide.

### 4. Peaks and counts are **monotone**, which is how we get concurrency for free

`peakUsedPercent` only rises; `observationCount` only rises; `lastObservedAt`
only moves forward. Merge is therefore `max`/`+`, never overwrite.

Consequence: a lost update under a concurrent writer loses at most a slightly
higher peak, and the **next observation heals it**. Use read-modify-write with an
atomic replace (temp file + rename). If the codebase already has a cross-process
file lock helper, prefer it — but do not build a new locking primitive for this,
and document the monotonicity argument in the type's doc comment rather than
pretending writes are serialized.

### 5. Per-source files

`<Application Support>/Allnighter/Capacity/<sourceId>.json`, resolved through
`AllnighterPaths` (add an accessor if there isn't a suitable one — match how
`AllnighterPaths.config` is used by `NotificationPolicyStore`).

Acquisition is per-source, so concurrent writers usually touch different files
and most contention disappears structurally. Volume is trivial either way — seven
sources × a year ≈ tens of KB.

### 6. Never store PII or raw vendor text

**No** account emails, org names, session ids, or `rawSnippet`. The strip already
has a redaction rule and this history is far longer-lived than a log line. Raw
snippets are for live debugging, not permanent storage.

### 7. Carry `planTier` per window

This gives the plan timeline for free — your own Codex history contains the
`pro` → `plus` change — which the utilization card's detail panel needs, and
which makes "34% of Pro" distinguishable from "34% of Plus".

### 8. `schemaVersion` on the file

House pattern. Migrations must be possible without discarding the moat.

## Required shape

`CapacityWindowRecord` — `Codable`, `Sendable`, `Equatable`:
`sourceId`, `scope`, `resetAt`, `resetPrecision`, `peakUsedPercent`,
`firstObservedAt`, `lastObservedAt`, `observationCount`, `planTier?`,
`poolLabel?`, and whether the window is closed (`resetAt <= now` at read time —
derive it, do not store a stale bool).

`CapacityHistoryStore` — house pattern: injectable file/root URL so tests never
touch the real Application Support, fail-soft `load` (unreadable or absent →
empty, never throw), `record(_ windows: [CapacityWindow], now:)` performing the
tolerance merge, and a `load(sourceId:)` returning records newest-first.

**No clock reads inside.** `now` is a parameter, as everywhere else in this
subsystem.

## out of scope

- No utilization projection, no cards, no averages — this slice only *stores*.
- No CLI verb, no `ContractRegistry`, no `docs/generated/`, no version bump.
  The contract is still red from `CLI_Park`; stay away from it.
- No GUI, no probes.
- **No new acquisition trigger.** This store records what acquisition already
  found. Writing must never cause a probe, a spawn, or a file scan of a vendor
  directory. Standing rule: events record from what is already known; they never
  go and ask.
- Do not modify `CapacityWindow`, the five extractors, the projection, the
  renderer, or `CapacityAcquisition`.

## Works Test — `CapacityHistoryStoreTests`

1. Round-trip: record then load returns equal records.
2. **Codex re-base merge**: two observations whose `resetAt` differ by 40 seconds
   merge into **one** record; peak is the max, count is 2.
3. **Distinct cycles stay distinct**: `resetAt` two days apart → two records.
4. Tolerance boundary: just inside and just outside 15 minutes.
5. Monotonicity: recording a *lower* used-% does not lower the stored peak, and
   `lastObservedAt` still advances.
6. `unknown` windows are not recorded at all — a missing sample must never
   become a stored 0%.
7. Missing/corrupt file → empty load, no throw.
8. Per-source isolation: writing grok does not touch the codex file.
9. Plan change: two records for the same source carrying different `planTier`
   both survive (the pro→plus timeline).
10. No PII: a `CapacityWindow` carrying an account string produces a record whose
    encoded JSON does not contain it.

## Rules

- Read `MEMORY.md` at the repo root first and cite honored lines.
- Match the surrounding style — read `NotificationPolicyStore.swift` for the
  store pattern and `CapacityWindow.swift` for tone.
- Swift 6 strict concurrency.
- Isolated `--scratch-path`; filtered tests only, never the full suite.
- Regression gates that must stay unchanged: `CapacityLogTests` 39,
  `CapacityWindowTests` 13, `CapacityBenchProjectionTests` 9,
  `CapacityAcquisitionTests` 11, `CapacityStripRendererTests` 14.

## Commit

Explicit paths, your own seat trailer. Leave the pre-existing dirty files.
Never `git reset --hard`, never rewrite history on `feat/design-chain`.

## Stop conditions

- A design decision above is genuinely wrong → stop and say which and why. Do
  not silently substitute a different one.
- You need a lock primitive that does not exist → stop and report; do not invent
  one for a monotone merge.
- Any regression gate moves → stop and report.
