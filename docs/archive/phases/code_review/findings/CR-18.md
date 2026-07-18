# CR-18 — SliceGate allowlist normalization and check.method proof gap

## Summary
`SliceGate.evaluate` is fail-closed on the high-risk paths: missing packet,
danger flags, unknown `check.method`, and executor cardinality are all blocked
correctly, and the prior CR-03 `[""]`-passes case is now fixed (a single
empty entry is blocked). Two real gaps remain. (1) The `touchAllowlist` check
uses `contains(where:)`, so it only requires *one* non-empty entry — mixed
lists like `["", "  ", "src/Foo.swift"]` pass and the empty/whitespace entries
are not trimmed out of the packet that travels downstream. (2) `decisionForCheckMethod`
returns nil (pass) for `.userObservation` unconditionally, so a mutating unit
under the write lock can be dispatched with no executable proof — only "user
will observe." The check.method validation also runs before executor
validation, so the gate cannot currently condition proof-method on
`executor.isMutating`.

## Findings

### P0 — None
No P0 (invariant/security) finding. The gate is fail-closed on missing packet
(SliceGate.swift:18-20), danger flags (SliceGate.swift:21-24), unknown
`check.method` rawValue (SliceGate.swift:63-65), non-mutating executor
(SliceGate.swift:44-46), and multi-worker executor (SliceGate.swift:47-49).

### P1 — touchAllowlist only requires one non-empty entry; list is not normalized
- **Invariant:** A mutating unit's `touchAllowlist` should be a clean list of
  real paths. The gate should either reject empty/whitespace entries or filter
  them before the packet travels downstream.
- **Evidence:** SliceGate.swift:33-36 — `packet.touchAllowlist.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })`.
  `contains(where:)` returns true if *any* single entry is non-empty, so
  `["", "  ", "src/Foo.swift"]` passes. The entries themselves are never
  trimmed/filtered on `packet.touchAllowlist`, so the empty strings persist
  into the dispatched packet. The specific CR-03 case `[""]` (single empty
  entry) is now blocked, but the broader mixed-list case is not.
- **Suggested fix:** Normalize before checking: map-trim, drop empties, require
  the filtered list to be non-empty (and ideally carry the filtered list on the
  packet). Alternatively, reject if *any* entry is empty/whitespace-only.
- **Suggested slice:** SliceGate: normalize touchAllowlist entries

### P1 — Mutating units can pass with check.method = .userObservation (no executable proof)
- **Invariant:** A mutating run under the per-root write lock should carry an
  executable proof method (`.command` or `.guiFixture`), not just
  `.userObservation`. The gate requires `touchAllowlist` for mutating units but
  does not require an executable check method for them.
- **Evidence:** SliceGate.swift:75 — `case .command, .guiFixture, .userObservation: return nil`
  returns nil (pass) for `.userObservation` with no command/fixture. The call
  site at SliceGate.swift:37-41 runs `decisionForCheckMethod` *before* the
  executor is validated at SliceGate.swift:42-49, so the proof-method decision
  cannot depend on `executor.isMutating`. A mutating slice with
  `check.method = .userObservation` therefore passes the gate with no automated
  proof.
- **Suggested fix:** After executor validation, when `executor.isMutating` is
  true, require `check.method ∈ {.command, .guiFixture}` (and the existing
  command/fixture pairing). This likely means moving or duplicating the
  check.method restriction to after the executor block.
- **Suggested slice:** SliceGate: require executable proof for mutating units

### P2 — touchAllowlist reason text says "for mutating units" but the check is unconditional
- **Invariant:** Block reason text should match the actual invariant enforced.
- **Evidence:** SliceGate.swift:35 — reason `"touchAllowlist is required for mutating units"`,
  but the guard at SliceGate.swift:33-36 runs for *every* packet, before
  `executor.isMutating` is known (checked later at SliceGate.swift:44-46). So
  the requirement is applied to non-mutating slices too, contradicting the
  reason text.
- **Suggested fix:** Either drop "for mutating units" from the reason, or move
  the touchAllowlist requirement to after the executor block and gate it on
  `executor.isMutating` (consistent with the P1 fix above).
- **Suggested slice:** (optional, fold into the P1 slice)

## False alarms ruled out
- **CR-03 `[""]` passes:** Fixed. `[""]` → `contains(where: { !"".trim.isEmpty })`
  → `contains(where: { false })` → false → blocked at SliceGate.swift:33-36.
  The remaining issue is mixed lists with empties (see P1 #1), not the single-empty case.
- **Exhaustive switch:** `decisionForCheckMethod` switches over all three
  `ProofMethod` cases (`.command`, `.guiFixture`, `.userObservation`) with a
  final `case .command, .guiFixture, .userObservation: return nil` catch-all
  (SliceGate.swift:66-76). Adding a new case is a compile error. No finding.
- **Danger flags:** `!packet.dangerFlags.isEmpty` blocks first with
  `PAIR_SLICE_UNSAFE` (SliceGate.swift:21-24). Fail-closed. No finding.
- **Executor cardinality:** `executor.workerCount == 1` is enforced
  (SliceGate.swift:47-49), plus `exists`, `isMutating`, `isRunnable`. No finding.
- **Unknown check.method rawValue:** `guard let method = FixPacket.ProofMethod(rawValue:)`
  else blocks with `PAIR_SLICE_UNSAFE` (SliceGate.swift:63-65). Fail-closed. No finding.
- **Nil command/fixture for command/guiFixture methods:** `(command ?? "").trim.isEmpty`
  treats nil as empty → blocked (SliceGate.swift:67, 69). Fail-closed. No finding.

## Greps avoided
Confirmed: no repo exploration. Review based solely on the inlined
`SliceGate.swift` source and the resolved symbols provided in the prompt. No
grep, glob, or file reads outside the single findings file written here.