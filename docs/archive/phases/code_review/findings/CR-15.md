# CR-15 — Terminal semantics for advisory review: empty-output asymmetry and reviewVerify silent pass

## Summary

`SliceTerminalClassifier.classify` evaluates the check result (`skipped`/`timedOut`/`exitCode`)
before the empty-output heuristic, so the CR-02 P1 "file-writing worker + passing check marked
stalled" concern is **partially resolved** for advisory reviews but **still stands** for normal
slices: a `.done` worker with `check.exitCode == 0` and empty stdout returns `.stalled` for
non-advisory slices (`:38-40`) and `.passed` for advisory reviews (`:38-39`). That asymmetry is
load-bearing — advisory reviews are disjoint-findings-only and may legitimately produce no stdout
when the reviewer finds nothing — but it has two gaps. First, `reviewVerify` slices use the same
`isAdvisoryReview` flag (`WorkSlicePacket.swift:79`), so a verify pass that emits no findings is
marked `.passed`, conflating "verification produced no dissent" with "verification never ran."
Second, the empty-output branch is reached only when `check.skipped` is false (`:35` short-circuits
to `.passed` first), so a skipped check + empty output on a non-advisory slice silently passes —
the file-writing worker risk re-enters through the `skipped` door. No P0 invariant violation
found; the advisory-review success criterion is upheld for the `review` (initial) case.

## Findings

### P0 — None

No invariant/security issue. The check is evaluated before the empty-output heuristic
(`:35-37` precede `:38-40`), so a verified run is never killed solely for empty stdout on
the advisory path. The F2 compaction invariant is upstream of this review's scope and is
covered by CR-02.

### P1 — `reviewVerify` with empty output silently passes

- **Invariant:** A verify pass (`mode == .reviewVerify`) must produce *some* verification
  signal before being marked `.passed`; "no output" should not be indistinguishable from
  "verified and found no dissent."
- **Evidence:**
  - `WorkSlicePacket.swift:79` — `isAdvisoryReview` is `mode == .review || mode ==
    .reviewVerify`, so both initial and verify slices take the advisory branch.
  - `SliceTerminalClassifier.swift:38-39` — `if visible.isEmpty { return
    packet.isAdvisoryReview ? .passed : .stalled }`. A `reviewVerify` slice with empty
    output and a passing check returns `.passed`.
  - `WorkSlicePacket.swift:77` — `inlinedFindings` is documented as "Findings markdown
    inlined for verify pass (mode reviewVerify)," confirming `reviewVerify` is expected to
    *consume* findings and emit a verdict, not stay silent.
- **Risk:** A `reviewVerify` worker that exits `.done` with `check.exitCode == 0` but
  produces no stdout (e.g., crashed after the check, or skipped the verify step) is marked
  `.passed` and the review closes as if verified. The disjoint-findings contract is
  unenforced at the terminal.
- **Suggested fix:** Split the empty-output branch on mode: `review` → `.passed` (no
  findings is a legitimate pass), `reviewVerify` → `.stalled` or a new `.verifyNoSignal`
  terminal (a verify pass must emit something). Alternatively, require `inlinedFindings`
  to be referenced in the output for `reviewVerify` to pass.
- **Suggested slice:** Distinguish reviewVerify silent pass from review no-findings pass

### P1 — Non-advisory file-writing worker with passing check is still marked `.stalled`

- **Invariant:** A `.done` worker with `check.exitCode == 0` is `passed`, regardless of
  stdout volume. (CR-02 P1, restated against the current inlined code.)
- **Evidence:**
  - `SliceTerminalClassifier.swift:38-40` — `if visible.isEmpty { return
    packet.isAdvisoryReview ? .passed : .stalled }`. For a non-advisory slice, empty
    output + passing check → `.stalled`.
  - `SliceTerminalClassifier.swift:35-37` — the check is evaluated first, so this only
    fires when `check.skipped == false`, `check.timedOut == false`, and `check.exitCode
    == 0`. I.e., the check genuinely passed and the worker genuinely produced no stdout.
- **Risk:** A worker that does its work entirely by writing files (edits, patches, file
  creation) and exits `.done` with a green check is classified `.stalled` and can be
  retried/killed. The check result — the declared source of truth — is discarded on the
  basis of a stdout-volume heuristic.
- **Suggested fix:** Drop the empty-output → `.stalled` heuristic for the `exitCode == 0`
  case; let the check be authoritative. If a stdout-presence signal is still needed, gate
  it on `check.skipped` (where there is no check result to trust) rather than on
  `exitCode == 0`.
- **Suggested slice:** Make check result authoritative for done+empty-output non-advisory slices

### P1 — `check.skipped` + empty output on a non-advisory slice silently passes

- **Invariant:** A skipped check should not let a non-advisory slice with no visible work
  product pass as `.passed`.
- **Evidence:**
  - `SliceTerminalClassifier.swift:35` — `if input.check.skipped { return .passed }`
    runs before the empty-output branch at `:38-40`.
  - `SliceTerminalClassifier.swift:38-40` — the empty-output heuristic is unreachable
    when `check.skipped` is true, because `:35` already returned.
- **Risk:** A non-advisory slice with `check.skipped == true`, `status == .done`, and empty
  stdout returns `.passed` at `:35` — the file-writing-worker risk that the empty-output
  heuristic was meant to catch is bypassed entirely through the `skipped` door. For
  advisory reviews this is fine (no findings + no check = pass); for normal slices it
  lets a no-op run close as passed.
- **Suggested fix:** Gate the `:35` short-circuit on `isAdvisoryReview`, or require
  non-empty output for non-advisory slices even when the check is skipped.
- **Suggested slice:** (covered by the slice above)

### P2 — `isReviewMode` is an undocumented alias of `isAdvisoryReview`

- **Evidence:** `WorkSlicePacket.swift:80` — `public var isReviewMode: Bool { isAdvisoryReview }`.
- **Result:** Two names for the same boolean with no doc comment distinguishing them. Callers
  may assume `isReviewMode` and `isAdvisoryReview` mean different things (e.g., initial-only
  vs. initial+verify) and pick the wrong one.
- **Suggested fix:** Delete `isReviewMode` if unused, or document the intended distinction.
  (Not grepped — within allowlist.)

## False alarms ruled out

- **"Empty-output heuristic runs before the check."** Not in the current inlined code.
  `:35-37` (skipped/timedOut/exitCode) precede `:38-40` (empty-output). CR-02 P1's
  ordering claim describes an older revision; the current code evaluates the check first.
  The remaining defect is that the heuristic *overrides* a passing check for non-advisory
  slices, not that it runs before the check.
- **"Advisory review with no findings should be `.stalled`."** No — for the initial
  `review` mode, no findings is a legitimate pass (the reviewer found nothing wrong). The
  `:38-39` `.passed` return is correct for `mode == .review`. The P1 above is specific to
  `reviewVerify`.
- **"`isAdvisoryReview` includes `reviewVerify` by mistake."** Not a defect —
  `WorkSlicePacket.swift:79` deliberately groups both, since both are disjoint-findings
  writes. The issue is that the *terminal* treats them identically, not that the flag does.
- **"`check.skipped` → `.passed` is always wrong."** No — for advisory reviews a skipped
  check is fine (the review is the work product). The P1 is that the same short-circuit
  applies to non-advisory slices.

## Greps avoided

Confirmed: no repo exploration. Review used only the two inlined sources
(`SliceTerminalClassifier.swift` and `WorkSlicePacket.swift:70-90`) and the resolved-symbol
list. No `grep`, `glob`, or `task` calls were made against repository sources. The two
`read` calls were for existing findings files (`CR-02.md`, `CR-16.md`) to match house style,
and the only `bash` call was `ls` on the findings directory to confirm the target path.