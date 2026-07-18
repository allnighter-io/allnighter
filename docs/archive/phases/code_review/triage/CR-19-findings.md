# CR-19 — Review CheckResult exitCode consumers

## Summary
`CheckResult.passed` (CheckRunner.swift:18) encodes a tri-state — `exitCode == 0`,
not `timedOut`, not `skipped` — as a single bool. The `SliceTerminalClassifier`
re-derives pass/fail from raw `exitCode` and `timedOut` reads but omits the
`skipped` dimension, so a skipped `CheckResult` is classified inconsistently
with `CheckResult.passed`. The two diverge in opposite directions depending on
whether the skipped result carries `exitCode == 0` (false pass) or
`exitCode == nil` (false fail). The inlined `PairCoordinator` snippet does not
read `exitCode` directly (only `stdoutTail`); its `failureReason` body was not
inlined and is not reviewable. The CLI display and planner-takeover paths named
in the lenses had no source inlined and are not reviewable from this review.

## Findings

### P0 — None
No invariant or security issue found in the inlined sources. The check result is
documented as an advance signal, not a verifier (CheckRunner.swift:4), so a
misclassification affects flow control, not a security boundary.

### P1 — Classifier ignores `skipped`; diverges from `CheckResult.passed`
- **Invariant:** Any consumer that decides pass/fail from a `CheckResult` must
  account for all three dimensions `CheckResult.passed` does (`exitCode`,
  `timedOut`, `skipped`), or delegate to `passed`.
- **Evidence:** `SliceTerminalClassifier.swift:40-41` reads
  `input.check.timedOut` then `input.check.exitCode != 0` but never reads
  `input.check.skipped`. `CheckRunner.swift:18` defines
  `passed { exitCode == 0 && !timedOut && !skipped }`.
- **Two divergence cases:**
  1. **False pass** — `skipped == true, exitCode == 0`: `passed` is `false`
     (skipped), but the classifier's `exitCode != 0` is `false`, so it proceeds
     past the guard and returns `.passed` (or `.stalled` if output is empty,
     SliceTerminalClassifier.swift:43-46). A skipped check is treated as a pass.
     This is the "skipped exitCode==0" case flagged in CR-04 P1.
  2. **False fail** — `skipped == true, exitCode == nil` (the default for
     skipped, CheckRunner.swift:11): `nil != 0` is `true` in Swift optional
     comparison, so the classifier returns `.failed`
     (SliceTerminalClassifier.swift:41). A skipped check (e.g., no repo-declared
     check command) is treated as a hard failure. Reachability depends on whether
     skipped results are gated before the classifier — not visible in the inlined
     sources.
- **Suggested fix:** Add an explicit skipped branch before the raw `exitCode`
  read, e.g. `if input.check.skipped { return .stalled }` (or whichever
  semantics the product wants), or gate on `input.check.passed` and handle the
  skipped-vs-failed distinction once. Decide the skipped semantics once and
  encode it in one place.
- **Suggested slice:** SliceTerminalClassifier: honor CheckResult.skipped

### P1 — `passed` is a bool over a tri-state, which pushes callers to raw reads
- **Invariant:** When the source-of-truth property collapses a tri-state
  (passed / failed / skipped) into a bool, every caller that needs the third
  state is forced to re-derive it from raw fields — the root cause of the
  classifier divergence above.
- **Evidence:** `CheckRunner.swift:18` — `passed` returns `false` for both
  "ran and failed" and "skipped," with no way to distinguish them. The
  classifier (SliceTerminalClassifier.swift:40-41) is one such caller that
  re-derives from raw fields.
- **Suggested fix:** Either (a) document on `passed` that callers must check
  `skipped`/`timedOut` first and audit all call sites, or (b) add a
  `CheckResult.Status` enum (`.passed`, `.failed`, `.skipped`, `.timedOut`)
  computed once, and have all consumers switch on it.
- **Suggested slice:** CheckResult: tri-state status enum

### P2 — `PairCoordinator.failureReason` body not inlined; exitCode read unverified
- **Invariant:** (reviewability gap, not a code defect)
- **Evidence:** `PairCoordinator.swift:392` passes `outcome.check` to
  `Self.failureReason(terminal:check:)`; the function body is not in the
  provided snippet. The inlined `PairCoordinator` lines (388-400) read only
  `outcome.check?.stdoutTail` (lines 393-394), not `exitCode`. If
  `failureReason` re-derives pass/fail from raw `exitCode`, it has the same
  hazard as the classifier.
- **Suggested fix:** Inline `failureReason` in a follow-up review to confirm it
  does not re-derive from raw `exitCode`. No edit claimed from this review.

## False alarms ruled out
- **Classifier `timedOut` check is redundant with `passed`** — Not a defect.
  The classifier checks `timedOut` (line 40) then `exitCode` (line 41)
  separately; the split is fine on its own. The defect is the missing `skipped`
  branch, not the split reads.
- **`nil != 0` in Swift** — Confirmed: comparing `Int32?` to `Int32` yields
  `false` for `nil == 0` and `true` for `nil != 0`. This is standard Swift
  optional comparison semantics, not a misread.
- **PairCoordinator duplicated `stdoutTail`** (`checkStdoutTail` and
  `stdoutTail` both set to `outcome.check?.stdoutTail`, lines 393-394) —
  Visible but out of scope for this review (exitCode consumers only). Not
  flagged as a finding.
- **CLI display / planner takeover check** — Listed in the review lenses but
  no source was inlined for either. Not reviewable; no finding claimed.

## Greps avoided
Confirmed: no repo exploration performed. This review used only the three
inlined snippets (CheckRunner.swift:1-25, SliceTerminalClassifier.swift:40-47,
PairCoordinator.swift:388-400). No `grep`, `glob`, `read`, or `task` tool calls
were made against the repository. `failureReason`, the CLI display path, and the
planner takeover check were not inlined and are explicitly marked unreviewable
above.