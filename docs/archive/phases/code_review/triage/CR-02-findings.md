# CR-02 — SliceTerminalClassifier: compaction ≠ stall (but the protection is brittle)

## Summary

`SliceTerminalClassifier.classify` orders compaction detection ahead of the stall
check for `status != .done`, so for the *known* marker "compaction" the F2
invariant (never kill a compacting GLM as stalled) holds. The protection,
however, rests on a bare `contains("compaction")` substring match with no
structured contract and no test proving it under stall-timeout pressure; a single
wording change in the CLI silently reopens the invariant. Beyond F2, there are
real misclassifications: `isInfraBackoff` runs on `.done` workers (so a finished
worker whose log mentions "429"/"busy" is routed as `.infraBackoff`), and the
empty-output → `.stalled` branch runs before the check result, so a file-writing
worker that exits clean with a passing check is wrongly marked stalled. The
"busy" heuristic is too broad, and "compaction completed" produces a false
positive that can mask a genuinely stuck worker (the inverse F2 risk).

## Findings

### P0 — F2 invariant is protected by a non-contract substring and is unproven under stall pressure

- **Invariant:** Never kill a compacting GLM as stalled (F2).
- **Evidence:**
  - `SliceTerminalClassifier.swift:46-49` — `isCompactionMarker` is
    `haystack.contains("compaction")`: a free-text substring match, not a
    structured CLI marker. No contract binds the CLI to emit the literal
    "compaction".
  - `SliceTerminalClassifier.swift:31-34` — compaction is only consulted when
    `status != .done`; correct for the kill path, but only as good as the marker
    detector above it.
  - `SliceTerminalClassifierTests.swift:42-51` — the sole compaction test uses a
    30s-old start. It proves the marker is *detected*, not that compaction
    *overrides an exceeded stall timeout*. The F2 invariant is never asserted
    under pressure, so a regression that reorders the checks or weakens the
    detector would pass CI silently.
- **Risk:** If the GLM CLI emits any wording other than "compaction" — e.g.
  "compressing context", "summarizing history", "context window full" — the
  marker is missed, a compacting worker is classified `.stalled`, and is killed.
  The invariant holds today by luck of wording, not by contract or proof.
- **Suggested fix:**
  1. Introduce a structured compaction signal emitted by the CLI (a sentinel
     line, an exit reason enum, or a `isCompacting` field on `WorkerRunOutcome`)
     and detect that, not prose.
  2. Add the missing invariant test: `status == .running` + compaction marker +
     `age >= stallTimeoutSeconds` → `.compacting` (not `.stalled`).
- **Suggested slice:** Structured compaction marker + F2 invariant test

### P1 — `isInfraBackoff` misclassifies `.done` workers

- **Invariant:** A finished worker is judged by its check result, not by
  incidental substrings in its log.
- **Evidence:**
  - `SliceTerminalClassifier.swift:30` — `if isInfraBackoff(outcome) { return
    .infraBackoff }` is unconditional on `status`.
  - `SliceTerminalClassifier.swift:51-54` — `isInfraBackoff` has no status guard;
    it scans `errorReason` + `output` for "429" / "busy" / "rate limit".
- **Result:** A `.done` worker whose output says "recovered from 429, retry
  succeeded" or "the queue was busy" is returned as `.infraBackoff` before the
  done-path ever runs. A successful run is misrouted to backoff handling.
- **Suggested fix:** Guard `isInfraBackoff` with `outcome.status != .done`, or
  move the infraBackoff branch below the done-path.

### P1 — Empty output → `.stalled` ignores the check result

- **Invariant:** A verified run is `passed`, regardless of stdout volume.
- **Evidence:**
  - `SliceTerminalClassifier.swift:38-39` — `if visible.isEmpty { return .stalled
    }` executes before the check is evaluated at `:40-43`.
- **Result:** A worker that does its work by writing files (no stdout), exits
  `.done`, and has `check.exitCode == 0` is classified `.stalled`, not `.passed`.
  The check result is discarded. This can trigger a needless kill/retry of
  successful, verified work.
- **Suggested fix:** Evaluate the check first; only fall back to `.stalled` on
  empty output when the check also fails/is skipped, or drop the empty-output
  heuristic entirely now that `CheckResult` is the source of truth.

### P1 — `infraBackoff` precedence over compaction misroutes compacting workers

- **Invariant:** A compacting worker is reported as compacting, not as a backoff.
- **Evidence:**
  - `SliceTerminalClassifier.swift:30` runs before `:31-34`.
- **Result:** A compacting worker whose output also contains "429" (e.g.
  "compaction triggered after 429") returns `.infraBackoff`, not `.compacting`.
  This is not a kill-as-stalled (F2 holds strictly — `.infraBackoff` ≠
  `.stalled`), but it misroutes handling: the supervisor may back off/retry a
  worker that should simply be waited on.
- **Suggested fix:** Check compaction before infraBackoff, or scope infraBackoff
  to runs that are not actively compacting.

### P1 — "compaction completed" false positive can mask a stuck worker (inverse F2)

- **Invariant:** A worker that is *no longer* compacting but is stuck must remain
  reapable as stalled.
- **Evidence:**
  - `SliceTerminalClassifier.swift:48` — `contains("compaction")` matches
    past-tense / completed forms ("compaction complete", "compaction finished").
- **Result:** A worker that wrote "compaction complete" and then hung (still
  `status == .running`) is classified `.compacting` indefinitely and is never
  reaped as stalled. This is the inverse of F2: the brittle marker over-protects
  a worker that should be killed.
- **Suggested fix:** Match an active-compaction phrase or — preferably — the
  structured marker from P0, not bare "compaction".

### P1 — "busy" substring is too broad

- **Invariant:** `infraBackoff` should reflect a real rate-limit/backoff signal.
- **Evidence:** `SliceTerminalClassifier.swift:53` — `text.contains("busy")`.
- **Result:** Matches "busybox", "the user is busy", "busy loop", any log line
  mentioning busy. False-positive `.infraBackoff` on unrelated output.
- **Suggested fix:** Use a structured signal or tighter patterns (e.g. an HTTP
  status enum, or "rate limit" / "429" only).

### P2 — `isStalled` returns `true` when `startedAt` is nil

- **Evidence:** `SliceTerminalClassifier.swift:57` — `guard let started =
  outcome.startedAt else { return true }`.
- **Result:** A running worker with no recorded start time is assumed stalled. If
  `startedAt` is ever unset for a freshly-started run, this reaps it immediately.
  (Compaction is checked first, so a compacting worker with nil `startedAt` is
  still protected — this only affects non-compacting runs.)
- **Suggested fix:** Default to not-stalled when `startedAt` is nil, or stamp
  `startedAt` at dispatch so nil is never a legal state.

### P2 — Inconsistent field coverage between compaction and infraBackoff checks

- **Evidence:**
  - `SliceTerminalClassifier.swift:46-49` scans `output` + `reasoning`.
  - `SliceTerminalClassifier.swift:51-54` scans `errorReason` + `output`.
- **Result:** A compaction marker in `errorReason` is missed (an F2 gap); an infra
  signal in `reasoning` is missed. The two detectors disagree on which fields are
  authoritative.
- **Suggested fix:** Both checks should scan the same union of fields
  (`output` + `reasoning` + `errorReason`), or — with P0 — both should consume
  structured fields instead of prose.

### P2 — `isCompactionMarker` is `public`

- **Evidence:** `SliceTerminalClassifier.swift:46` — `public static func`.
- **Result:** Exposes a brittle implementation detail as public API; callers
  could come to depend on the substring behavior.
- **Suggested fix:** Make `private` (like `isInfraBackoff` and `isStalled`).

## Suggested missing test cases

Ordered by invariant value:

1. **F2 invariant proof (critical):** `status == .running` + compaction marker +
   `age >= stallTimeoutSeconds` → `.compacting`. Today there is no test that
   compaction overrides an exceeded stall timeout.
2. **Compaction marker in `reasoning` only** (output nil) → `.compacting`.
3. **Compaction marker in `errorReason` only** → currently `.stalled`/`.failed`
   (documents the P2 gap; should become `.compacting` if the field union is
   fixed).
4. **infraBackoff on a `.done` worker** ("429" in output, exit 0) → should be
   `.passed`, currently `.infraBackoff` (P1).
5. **"busy" false positive** on a `.done` worker → should be `.passed`/`.failed`,
   currently `.infraBackoff` (P1).
6. **Empty output + `check.skipped`** → currently `.stalled`; pin intended
   behavior (P1).
7. **Empty output + `check.exitCode == 0`** (file-writing worker) → currently
   `.stalled`; should be `.passed` (P1).
8. **`check.skipped` + non-empty output** → `.passed` (branch at
   `SliceTerminalClassifier.swift:40` is uncovered).
9. **`check.timedOut`** → `.failed` (branch at `:41` is uncovered).
10. **infraBackoff + compaction both present** (running) → pin precedence (P1).
11. **"compaction complete" while running + old** → should be `.stalled` once
    past compaction, currently `.compacting` forever (P1 inverse-F2).
12. **Non-"compaction" wording** (e.g. "compressing context") while running + old
    → currently `.stalled`; documents the P0 false-negative / F2 risk.

## False alarms ruled out

- **Compaction-vs-stall ordering is correct for `status != .done`.** The
  compaction branch (`:31-34`) precedes the stalled branch (`:35-36`), so for the
  known marker a running compacting worker is never returned `.stalled`. The P0
  finding is about *brittleness and missing proof*, not a wrong order. No change
  to the order is suggested.
- **`.done` + compaction marker falls through to the done-path.** This is
  correct: a finished worker should not be classified as compacting. The
  compaction guard's `status != .done` clause is right.
- **`isStalled` nil-`startedAt` → `true`.** Defensible if `startedAt` is always
  stamped at dispatch; flagged P2 only because nil is treated as maximally stale
  rather than unknown.
- **`isCompactionMarker` lowercasing the haystack.** Correct; not a finding.

## Greps avoided

Confirmed: no repo exploration. Review used only the two inlined sources
(`SliceTerminalClassifier.swift`, `SliceTerminalClassifierTests.swift`) and the
required findings shape. No `grep`, `glob`, `read`, or `task` calls were made
against repository sources. The only filesystem action was checking that the
findings directory exists and writing this file.