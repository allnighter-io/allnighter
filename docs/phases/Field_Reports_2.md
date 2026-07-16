# Field Reports 2 — one-glance run outcome + trailer wiring truth

Status: SHIPPED — FR5 + FR6 (piloted delivery #8)
Owner: AllnighterCore + CLI
Updated: 2026-07-16

Source: a successful founder pilot run on Ikiro (`alln run` → model_grok,
execution_playbook, commit `2c07ad43`, PM-gated and verified). Two small friction
points from an otherwise clean report.

## FR5 — one-glance outcome (honest, mechanical — never a correctness claim)

Observed: the PM had to infer success from `repoDelta.changed` + reading
`workerAnswers`. Wanted: a top-level verdict for fast gating.

Law check: Allnighter does NOT own correctness — so `outcome` must be purely
mechanical, derived from facts Allnighter already holds, never a judgment of the
work: worker terminal status, write policy, repoDelta. The PM still gates.

**Acceptance:** `TeamRunJSON` gains a top-level `outcome` block:
`{ status: completed | partial | failed | timedOut, committed: Bool,
headline: String }` where `status` derives from worker terminal states (all
done → completed; some done → partial; none → failed/timedOut), `committed` =
`repoDelta.changed == true`, and `headline` reuses the FR2 identity + FR3 delta
summary ("worker model_grok · lane code · mutating · committed 2c07ad43: 11
files"). Human output prints the headline. Additive field; schema regenerated;
mapper tests for all four statuses; the docs/help for `run` name it and state
plainly it is mechanical, not a correctness verdict.

## FR6 — provenance trailer: why was this commit plain?

Observed: the Ikiro run's commit (`2c07ad43`) carries no
`Co-Authored-By: … via Allnighter` trailer, though FR4 (`10fd73a4`) wired the
trailer ask into RelayDevPrompt AND claimed "bare mutating runs: RunService
appends the same trailer once." Meanwhile the trailer DID appear on the memory
seed commit (a relay dev turn). So either (a) the founder's run predated FR4,
(b) the `alln run` path misses the append, or (c) the ask was present and the
worker ignored it (convention is best-effort).

**Finding (2026-07-16, verified): (a) timing.** The Ikiro commit `2c07ad43` is from
the same 2026-07-16 dogfood session that produced Field Reports 1 finding #7 (plain
commits, no trailer) — documented in `Field_Reports_1.md` as predating the FR4
fix. FR4 landed at `10fd73a4` on **2026-07-16 13:48:19 +0200**. The field run used a
binary built before that commit. **Not (b):** code trace confirms `alln run`
→ `RunCLI` → `RunService.run` → `runExecution` (execution teams use
`runShape == .execution`) appends `ProvenanceConvention.commitTrailerAsk` when the
assembled prompt lacks `Co-Authored-By:` (`RunService.swift` ~460–461). Pinned by
`RunRepoDeltaTests.testBareMutatingRunDispatchIncludesCommitTrailerAskExactlyOnce`.

**Acceptance:** investigate and NAME which of a/b/c it was (git dates + the
actual dispatch path for `alln run` mutating runs). If (b): fix the wiring +
a test pinning the bare-run prompt contains the ask exactly once. If (c):
strengthen the wording ONE notch (e.g. move the ask adjacent to the commit
instruction rather than the preamble tail) and record in the doc that the
convention is best-effort by design — no enforcement, Allnighter does no git.
If (a): add the pin test anyway (cheap) and close as timing. Either way the
delivery report states the finding as fact, not guess.

## Works test

A mutating run through the real dispatch-capture seam shows `outcome`
(completed/committed/headline) in TeamRunJSON + the headline on human output;
the bare-run prompt contains the trailer ask exactly once (test); filters
`Run|Relay|Pilot` green; contracts regenerated.
