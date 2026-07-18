# CR-04 — verified

## Summary
One P0 was adjudicated. **Upheld.** The failure mechanism — `check.command` (an
unvalidated `String` from `WorkSlicePacket.Check`) passed verbatim to `/bin/sh -c`
with only a docstring ("repo-declared") asserting the trust boundary and no
code-level enforcement (no sanitization, no allowlist, no source check) — is
confirmed directly in the inlined source. The RCE *impact* is conditional on
`check.command` provenance (agent-influenced vs. repo config), which the finding
transparently frames as conditional and which lies outside the inlined source;
the structural gap (no defense-in-depth) is unconditionally true in source. No
actor suspension is required to confirm the mechanism itself.

## P0 adjudication

### P0 — `check.command` executed as arbitrary shell with no defense-in-depth — Uphold
- **Original claim:** The docstring asserts `check.command` is "repo-declared"
  but the code enforces no trust boundary; `check.command` is passed verbatim to
  `/bin/sh -c` with no sanitization, allowlist, or source check. If
  `check.command` is ever populated from agent/chat/preset input rather than repo
  config, this is direct RCE.
- **Verdict:** Uphold
- **Evidence:**
  - `CheckRunner.swift:4` — `/// Result of running the repo-declared check
    command` and `CheckRunner.swift:21` — `/// Runs the order's repo-declared
    check as a bounded `/bin/sh -c` subprocess.`: the "repo-declared" trust
    boundary exists only in docstrings, not in code.
  - `CheckRunner.swift:39-41` — `guard let command = check.command?
    .trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else {
    return .init(skipped: true) }`: the only processing of `check.command`
    before exec is a whitespace trim and emptiness check. This is not
    sanitization, not an allowlist, and not a source check.
  - `CheckRunner.swift:42-44` — `commandRunner.run(command: "/bin/sh", args:
    ["-c", command], ...)`: the trimmed string is passed verbatim as the shell
    script body. No validation of command content or origin occurs between read
    and exec.
  - `CheckRunner.swift:33` — `check: WorkSlicePacket.Check`: the parameter is a
    work-order data structure, not a typed/trusted config handle; nothing in
    `run` constrains how it was populated.
  - The failure mechanism (unvalidated string → `/bin/sh -c`) is fully present
    in source. The RCE impact is conditional on `check.command` being
    influenceable by non-repo sources; the finding states this conditionally
    ("if `check.command` is ever populated from agent/chat/preset input rather
    than repo config") and does not assert it as proven. The structural gap —
    no defense-in-depth behind a docstring-only assertion — is unconditionally
    confirmed. No actor suspension is required to uphold the mechanism.

## P1 notes
- **Full environment passthrough (P1):** Confirmed. `CheckRunner.swift:46` —
  `env: ProcessInfo.processInfo.environment` passes the entire parent
  environment to the subprocess. Materially correct; the secret-exfiltration
  impact is conditional on the same `check.command` trust question as the P0.
- **`/bin/sh -c` child orphan on timeout (P1):** The structural facts are in
  source (`/bin/sh -c` at `:42-44`; `timeout: timeout` at `:48`), but the kill
  behavior is delegated to `CommandRunner`, which is not inlined. The finding
  is honest about this ("`CheckRunner` does not control how `CommandRunner`
  kills on timeout"). The orphan risk is a reasonable conditional note, not an
  overclaim — the finding does not assert `CommandRunner` is broken, only that
  the contract is invisible and `/bin/sh -c` is what creates the multi-process
  tree.

## P2 notes
- **Inconsistent `exitCode` for skipped (P2):** Confirmed. Empty-command skip
  returns `.init(skipped: true)` → `exitCode: nil` (`:40`); `.guiFixture`/
  `.userObservation` returns `.init(exitCode: 0, skipped: true)` (`:57`). Same
  `skipped: true`, different `exitCode`. `passed` (`:18`) handles both correctly
  via `!skipped`, so this is a raw-field-access inconsistency, not a bypass.
  Materially correct.
- **`tail` O(n) double iteration (P2):** Partially overstated. `trimmed.count`
  (`:63`) is O(n) over grapheme clusters; `trimmed.suffix(stdoutTailLimit)`
  (`:64`) is O(limit) from the end for a bidirectional collection, not a second
  full O(n) pass. The memory-pressure claim (full output held before
  truncation) is correct. Not materially wrong overall; the "iterates again
  from the end" phrasing slightly overstates `suffix` cost.
- **Combined stdout+stderr tail loses stdout context (P2):** Confirmed.
  `:50` — `result.stdout + (result.stderr.isEmpty ? "" : "\n" + result.stderr)`
  concatenates stdout then stderr; `tail` (`:61-65`) takes the last 4096 chars,
  so large stderr displaces the stdout failure line. Materially correct.

## False-alarm rulings (spot-checked, all hold)
- `passed` requires `!skipped` (`:18`), so `exitCode: 0, skipped: true` does not
  bypass `passed`. Correct.
- Empty/whitespace `check.command` is guarded (`:39-41`) and never reaches
  `/bin/sh`. Correct.
- `String.suffix(_:)` is grapheme-cluster-correct; no UTF-8 split. Correct.
- `CheckRunner` is `Sendable`, holds an immutable `CommandRunner`, `run` is
  async with no shared mutable state. No race. Correct.
- `defaultTimeout` (`:23`) is a tunable; 300s is a product choice, not a defect.
  Correct.
- The `check.method` switch (`:37-58`) covers `.command`, `.guiFixture`,
  `.userObservation` with no `default`; Swift enum exhaustiveness is
  compile-time. Not a silent-bypass bug. Correct.

## Greps avoided
Confirmed: no repo exploration. Adjudication is based solely on the inlined
`Packages/AllnighterCore/Sources/AllnighterEngine/CheckRunner.swift` source.
Did not read `WorkSlicePacket`, `CommandRunner`, `Unified_Run_Model.md`,
`Work_Order_Team_Model.md`, or any other file. Line numbers cited above follow
a 1-indexed count of the inlined block and may differ by one from the finding's
resolved-symbol offset convention (`run` at :31, `tail` at :60); content at
cited locations was verified against the inlined source.