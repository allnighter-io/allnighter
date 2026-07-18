# CR-03 — SliceGate scope and danger enforcement

## Summary
`SliceGate.evaluate` is a clean, fail-closed structural gate: nil packet, any
danger flag, missing sliceId/intent, missing executor facts, and non-single-worker
executors all block. Danger handling is robust against whitespace/empty entries
because it tests array emptiness, not string content. The real weaknesses are on
the *scope* side: the `touchAllowlist` check only verifies the array is non-empty
(so `[""]` or whitespace-only entries pass), the `check.method` switch silently
allows any non-`.command`/non-`.guiFixture` method through with no check, and the
gate never inspects allowlist *content* or confirms runtime enforcement — it is a
presence check, not a confinement check. No P0 invariant/security bypass found.

## Findings

### P0 — None
No invariant or security bypass found. The gate is fail-closed on every path that
could be verified from the inlined source. The scope weaknesses below are real
wins, not silent bypasses of a stated invariant.

### P1 — `touchAllowlist` emptiness check is array-level only; `[""]` passes
- **Invariant:** A mutating unit must declare at least one real (non-empty,
  non-whitespace) touch path. The gate's own doc comment ties the allowlist to
  mutating-unit safety (`SliceGate.swift:4`), and `sliceId`/`intent` are trimmed
  before their emptiness check (`SliceGate.swift:27`, `SliceGate.swift:30`).
- **Evidence:** `SliceGate.swift:33` — `guard !packet.touchAllowlist.isEmpty`
  tests the collection, not its contents. A packet with `touchAllowlist = [""]`,
  `["   "]`, or `["\t"]` has a non-empty array, so the guard passes and the slice
  proceeds to executor validation. This is inconsistent with the trimming applied
  to `sliceId` and `intent` two lines above.
- **Suggested fix:** Require at least one entry that survives trimming, e.g.
  `guard packet.touchAllowlist.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { ... }`
  and reuse the same trimming helper used for `sliceId`/`intent`.
- **Suggested slice:** SliceGate: validate touchAllowlist entry content, not just array presence

### P1 — `check.method` switch's `default: break` allows unhandled methods with no check
- **Invariant:** A mutating slice must carry a usable verification check, or an
  explicit waiver (AGENTS.md: "Every feature slice needs one owner-visible Works
  Test or an explicit waiver"). The gate enforces a non-empty payload for
  `.command` and `.guiFixture` (`SliceGate.swift:37`, `SliceGate.swift:39`), which
  implies a check is expected.
- **Evidence:** `SliceGate.swift:41-42` — `default: break`. The presence of a
  `default` arm means the enum has cases beyond `.command`/`.guiFixture`; any such
  case (e.g. a `.none`/`.skip`/`.manual`) falls through and the slice is allowed
  with no check payload validated at all. The gate cannot distinguish "method that
  needs no payload" from "method that forgot its payload."
- **Suggested fix:** Switch exhaustively over `check.method` cases; for any
  "no-check" case, require an explicit waiver field on the packet rather than
  silently allowing it. At minimum, replace `default: break` with a case that
  blocks unknown methods (`PAIR_SLICE_UNSAFE` — "unsupported check.method").
- **Suggested slice:** SliceGate: exhaustive check.method handling, no silent default

### P1 — Gate vs runtime allowlist enforcement gap (presence ≠ confinement)
- **Invariant:** The touch allowlist is the scope contract that confines a
  mutating worker's writes (Unified_Run_Model: one worker under the per-root write
  lock). The gate is named the "scope gate" and the doc comment frames
  `touchAllowlist` as the mutating-unit safety control (`SliceGate.swift:4`).
- **Evidence:** `SliceGate.swift:33` only checks the allowlist is non-empty. It
  never inspects content: `touchAllowlist = ["/"]` (whole repo), `["/etc/..."]`
  (out-of-repo), or paths outside the packet's declared root all pass. Nor does
  the gate confirm the executor/runtime will actually enforce the allowlist at
  dispatch — it trusts the packet's declaration. If the runtime does not confine
  writes to these paths, the gate is structural theater.
- **Suggested fix:** This is partly by design (the gate is structural), so the fix
  is a documented contract: either (a) the gate validates allowlist entries
  against the packet's declared root and rejects over-broad/sensitive paths, or
  (b) the runtime enforcement point is named in the gate's doc comment so readers
  know the gate only checks *presence* and the executor enforces *confinement*.
  Today the comment over-promises.
- **Suggested slice:** SliceGate: name runtime allowlist enforcer, or validate entry scope

### P2 — Doc comment implies conditional `touchAllowlist`; code requires it unconditionally
- **Invariant:** Comments must match behavior. `SliceGate.swift:4` says
  "`touchAllowlist` is required for mutating units," implying non-mutating/review
  packets may omit it.
- **Evidence:** `SliceGate.swift:33` requires `!touchAllowlist.isEmpty` for every
  packet, before `executor.isMutating` is checked (`SliceGate.swift:47`). A
  read-only/review packet that reached this gate would be blocked with
  "touchAllowlist is required for mutating units" — a misleading reason — rather
  than "executor is not mutating." If the gate is mutating-only by construction,
  the comment's "for mutating units" qualifier is dead; if review packets can
  reach it, the check is wrong.
- **Suggested fix:** Either drop "for mutating units" from the comment, or move
  the `touchAllowlist` check below `executor.isMutating` and gate it on
  `executor.isMutating`.

### P2 — Check ordering produces misleading block reasons
- **Evidence:** `touchAllowlist` (`SliceGate.swift:33`) and `check.method`
  (`SliceGate.swift:36`) are validated before `executor.exists`/`isMutating`
  (`SliceGate.swift:44`, `SliceGate.swift:47`). A packet with a bad executor AND
  an empty allowlist reports the allowlist problem first, hiding the executor
  problem. Not a safety issue (still blocks), just diagnostics.
- **Suggested fix:** Validate executor facts before packet scope, or accept the
  current order and document it as "packet-shape first, executor second."

### P2 — `dangerFlags` reason string can be confusing for whitespace-only flags
- **Evidence:** `SliceGate.swift:25` joins flags with `", "`. If an entry is `""`
  or `"  "`, the reason reads `danger flag(s):  ,  ` but still blocks (array is
  non-empty, `SliceGate.swift:22`). Safe, just ugly.
- **Suggested fix:** Filter empty/whitespace entries before joining for the
  reason string; the block decision itself is correct and should not change.

## False alarms ruled out
- **`dangerFlags = [""]` does NOT bypass the gate.** `SliceGate.swift:22` tests
  `!packet.dangerFlags.isEmpty` (array-level), so any non-empty array — including
  one holding empty/whitespace strings — blocks. The gate over-blocks here, which
  is the safe direction. No bypass.
- **Nil `packet` is handled.** `SliceGate.swift:19` returns
  `PAIR_SLICE_PACKET_MISSING` before any field access. No force-unwrap path.
- **Nil `check.command` / `check.fixture` are handled.** `SliceGate.swift:37` and
  `SliceGate.swift:39` coalesce nil to `""` via `?? ""` before trimming, so a nil
  payload on a `.command`/`.guiFixture` method blocks as expected.
- **`workerCount` of 0 or negative is blocked.** `SliceGate.swift:53` requires
  `== 1` exactly; `0`, `-1`, and `2+` all block.
- **Non-mutating executor is blocked.** `SliceGate.swift:47` rejects
  `executor.isMutating == false` before `.allowed` is reachable.
- **Block-code reuse (`PAIR_SLICE_UNSAFE`) is not a bypass.** The `reason` string
  disambiguates; `Decision.isAllowed` only returns true for `.allowed`
  (`SliceGate.swift:12-14`).

## Greps avoided
Confirmed: no repo exploration. Did not read `WorkSlicePacket`, `TryFixGate` /
`ExecutorFacts`, the `check.method` enum definition, or any other source. All
evidence is drawn from the inlined `SliceGate.swift` with line numbers counted
from the top of the inlined block. The only filesystem touch was confirming the
findings directory exists and writing this file.