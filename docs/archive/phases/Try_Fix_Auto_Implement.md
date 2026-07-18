# Try Fix: Auto-Implement After Bug Hunt

Status: Draft feature packet — ELIMINATION-LOOP model (confidence gate removed)
Owner: AllnighterCore + CLI/MCP + Mac app
Updated: 2026-06-20

> **Model change (2026-06-20).** This packet was rebuilt around the scientific method.
> The old "auto-execute only at `confidence == high`" gate is DELETED: real bugs — and
> the people Try Fix is for, who can't read code — are rarely fixed in one confident shot.
> They're fixed by trying the best hypothesis, observing what happens, eliminating a
> failure point, and narrowing. Try Fix is an **elimination loop**, not a one-shot patch.
> Confidence is an *ordering* signal (which hypothesis first, how many rounds to expect),
> never a gate. The user's only judgment is "is it fixed?" — which is observable.
>
> **Allnighter does no git.** It sends orders to one CLI worker in the repo root under the
> write lock; the repo and the CLI own all git. Safety = one mutating worker + a small
> bounded order + danger hard-stops + the proof/observation surface + the user's own undo.

## Why

Bug Hunt is valuable only if the user can act on it. The founder is not trying
to become the human compiler for several model opinions. The product win is:

```text
Find the bug -> choose the best fix packet -> try the fix with one trusted worker.
```

Today the founder can manually run Bug Hunt, read the output, then tell the
default worker to run the Debugger and fix it. If Allnighter stops at diagnosis,
it is not faster for non-developers. The missing capability is an explicit,
safe follow-up from a read-only answer team into a single mutating execution run.

## First-Principles Verdict

Accept:

- Diagnosis and implementation are different run shapes. Bug Hunt stays an
  answer team; the fix attempt is a child execution run.
- The handoff must be typed. Markdown can be the human view, but Core needs a
  parseable `FixPacket` before it can decide whether a child run may start.
- The chain belongs in Core run policy, not in SwiftUI state or caller-specific
  glue.
- The executor prompt must be engineered for "apply this fix and prove it," not
  a generic implementation prompt with extra context.

Accept (added with the loop model):

- A fix attempt is an EXPERIMENT, not a commitment. Try the top surviving hypothesis,
  run the proof/repro, and let the result eliminate a failure point and narrow the next
  round. Bug Hunter supplies a ranked hypothesis ladder + the experiments; Auto Fix runs
  them. The loop carries a growing "ruled out" list so a round never repeats a dead path.
- The user judges only "is it fixed?" (observable), never "is this fix correct?".
- When the bug is at a seam and the honest proof can't be written in the app, the loop
  escalates to a minimal isolation harness run (the proven "change the haystack" move).

Reject:

- Treating any plausible Bug Hunt prose as executable intent.
- Gating execution on self-reported confidence. Confidence orders hypotheses and sets
  expectations; it does not decide whether to try. (Danger is the hard gate, not doubt.)
- Running more than one mutating worker.
- Hiding two disconnected runs behind optimistic UI; the user must be able to
  inspect diagnosis -> fix attempt -> proof, round by round.
- Adding a new user-facing workflow noun. This is a run follow-up policy.
- Allnighter touching git (commit/branch/worktree/revert). The repo and CLI own that.

## Founder Intent

- Raw request: add an option on Bug Hunt-style teams so the team can diagnose the
  bug and then the default model immediately tries the recommended fix.
- Product value: turn team diagnosis into working code without asking a
  non-developer to judge the packet manually.
- Trusted workflow slice: `bug report -> Send to team -> Code / Bug Hunt ->
  Try Fix -> one execution worker applies/proves the fix`.
- Non-goals: no parallel writers, no hidden approval ceremony, no prompt-only
  safety, no automatic high-risk changes, no new workflow product noun.

## Product Language

Working feature name: **Auto-Implement**.

Recommended checkbox label: **Try Fix**.

Why `Try Fix`: it is short, honest, and does not overclaim. It says Allnighter
will attempt the team's recommended fix, not guarantee a repair.

Label candidates:

| Candidate | Verdict |
| --- | --- |
| Try Fix | Recommended short label. |
| Fix It | Good button/action copy, slightly bossier as a checkbox. |
| Auto-fix | Familiar, but can sound magical or unsafe. |
| Apply Fix | Too certain unless the packet is already a patch. |
| Auto-Implement | Accurate internal phrase, long for primary UI. |

Suggested UI copy:

```text
[ ] Try Fix
```

Tooltip / accessible description:

```text
After this team returns a safe fix packet, run one execution worker in the repo
to try the recommended fix.
```

## Current State

- `code_bug_hunt` and `code_gui_bug_hunt` already exist as Code answer teams with
  `outputKind == bugPacket`.
- `default_chat` ("Auto") and `execution_playbook` already exist as mutating
  one-worker teams.
- `RunService` already enforces answer vs execution shape through
  `TeamPreset.mutating`, `RunShape`, and `RunWriteLock`.
- `TeamRunJSON.nextActions` and `FloorRun.nextActions` already expose typed
  follow-up actions, but they do not yet include a mutating fix attempt.
- `StagePayload` is already the closed Core union for typed stage truth, but
  Bug Hunt currently lands as generic plan markdown from `bug_packet_writer`.
- `SignalInsightParser` already proves the fenced structured-block pattern for
  extracting typed output from writer markdown; Try Fix should reuse that pattern
  as an ingestion bridge, not as long-term durable truth.
- The Debugger operation doc already defines the fix-quality packet:
  tier, symptom/repro, fingerprint, truth owner, lie-prone layer, regression
  considered, missing proof, fix boundary, and proof command.

## SSOT

Truth owner:

```text
AllnighterCore follow-up run policy:
  source answer run
  typed FixPacket
  TryFixGate decision
  chosen executor team
  fix-attempt prompt assembly
  parent/child run link
  proof result projection
```

Lie-prone layers:

- SwiftUI checkbox state that starts a mutating run without a Core policy.
- Prompt prose that says "fix it" without a typed packet and deterministic gate.
- Markdown-only Bug Hunt output that cannot be validated before execution.
- A multi-worker Bug Hunt result silently becoming multiple mutating writers.

New semantic rules:

1. `Try Fix` is selected per run, and may later be saved as a team default only
   through the same CLI/MCP/Core contract.
2. `Try Fix` never changes the answer team into a writer. The answer team remains
   mechanically read-only.
3. If `Try Fix` was requested and the answer run returns a `FixPacket` that meets the
   entry conditions (a top hypothesis with a fix + boundary, a named proof method, and no
   danger flags), Allnighter starts exactly one child execution run that tries the TOP
   hypothesis. Confidence does not gate this — it only ordered the ladder.
4. If `Try Fix` was not requested, a valid packet still produces a typed `tryFix` next
   action so a past Bug Hunt can be acted on later.
5. If the packet has no actionable hypothesis, names no proof method, or hits a danger
   stop, Allnighter does not execute; it returns an actionable blocked result. Low
   confidence is NOT a block — it expects more rounds.
6. The mutating child run uses the same repo root and takes the repo write lock.
7. The parent and child runs are linked durably so the Floor can show:
   diagnosis -> fix attempt -> proof, round by round.
8. A failed proof does not auto-loop. It records a `ruledOut` entry and exposes one
   explicit "keep going" next action that narrows to the next hypothesis with the updated
   ruled-out memory. The user drives the cadence.

Duplicate truth to delete:

- Any GUI-local "auto implement" bool not reflected in the run request.
- Any output parser that treats arbitrary markdown as safe-to-execute intent.
- Any separate JSON shape for the GUI; CLI, MCP, GUI, and iOS must project the
  same follow-up contract.

## Fix Packet

Bug Hunt and GUI Bug Hunt need to produce a structured packet, not just prose.
The writer should append a fenced JSON block:

````text
```fix-packet
{ ... }
```
````

Core parses that block, validates it, and stores/projects the result as typed
truth. The fenced block is an ingestion bridge for model output. Durable truth
should live as a `StagePayload` case or an attached typed return, not as "the plan
markdown happens to contain a JSON blob."

```text
FixPacket
  schemaVersion
  sourceRunId
  seam?                      // the boundary the bug crosses (e.g. AppKit↔SwiftUI), when one
  symptom
  repro
  bugFingerprint
  truthOwner
  lieProneLayer
  hypotheses[]               // RANKED ladder, most-likely first
    id
    cause
    experiment              // cheapest confirm/refute
    fix                     // smallest change to try if this is the cause
    fixBoundary             // apply only here; no opportunistic refactor
  ruledOut[]                // failure points already eliminated (loop memory)
  proofMethod: command | guiFixture | userObservation
  proofCommand?             // when proofMethod == command
  guiProofFixture?          // when proofMethod == guiFixture
  requiresLayoutWatcher: Bool
  harnessNeeded: Bool       // true when the honest proof can't be written in this codebase
  harnessSketch?            // the minimal isolation target to build (same seam/stack)
  confidenceOrdering: low | medium | high   // ORDERING hint only — never a gate
  expectedRounds?           // honest "this is a few-round bug" signal
  tier: T0 Fast | T1 Boundary | T2 SSOT | T3 Critical
  dangerFlags[]             // hard stops (see below) — block regardless of confidence
```

Entry conditions for an automatic fix attempt (the loop may START):

- answer run status is terminal success, not partial/failed
- final writer stage is produced by the Bug Packet writer
- fenced `fix-packet` block parses and validates
- at least one hypothesis with a non-empty `fix` + `fixBoundary`
- a `proofMethod` is named (command, GUI fixture, or — honestly — user observation)
- `truthOwner` non-empty
- no `dangerFlags`
- selected executor team is mutating, runnable, and resolves to exactly one worker/source

Note what is NOT here: there is no confidence threshold and no `tier != T3` block. A T3 or
low-confidence bug is still tried — it just expects more rounds and a tighter boundary.
What blocks is **danger**, never **doubt**.

Danger hard-stops (block the attempt regardless of confidence — these are about harm, not
uncertainty):

- privacy or session data leaving the user's machines
- credentials, Keychain items, API keys, or auth state
- Full Disk Access or permission posture changes
- destructive process kill or deletion outside the fix boundary
- App Store, notarization, distribution identity, TestFlight release
- billing, entitlement, quota-spend behavior, or production deploy

(Git history rewrite is the repo/CLI's domain; Allnighter neither performs nor blocks it.)

## The Elimination Loop

Try Fix is the back half of one scientific-method loop. Bug Hunter generates the ranked
hypotheses and designs the experiments; Auto Fix runs them and narrows.

```text
take the top SURVIVING hypothesis from the packet
  -> assemble a disciplined fix-attempt order (one worker, only within fixBoundary,
     run the proof / reproduce, report exactly what changed)
  -> start ONE execution run
  -> read the result
        proof passes / user confirms "fixed"   -> done. Fixed.
        not fixed                               -> the result ELIMINATES that hypothesis;
                                                   append a `ruledOut` entry with what the
                                                   attempt changed and what it disproved
  -> narrow to the next hypothesis, carrying the growing ruledOut list into its order
  -> repeat
```

Rules:

1. Each round is DIFFERENT because it is informed by the last result. The `ruledOut` list
   is the loop's memory and the anti-paralysis engine: a round never re-runs a dead path.
2. The user answers exactly one question between rounds: "is it fixed?" — observable (does
   it still crash / still look wrong?). They never judge code or packets. A round surfaces
   `Tried -> Observed -> Ruled out` in plain language, then `[Keep going]` or `[Stop]`.
3. When `harnessNeeded == true`, or after K in-app rounds fail, the loop ESCALATES to an
   isolation-harness run: build the minimal target that reproduces only the failing
   capability with the same seam/stack, get it green, port the known-good pattern back, then
   resume. (The codebase's own debug process owns the harness protocol;
   `docs/operations/debugger/ISOLATION_HARNESS.md`.)
4. The loop terminates honestly. Either FIXED (proof/observation), or STUCK — and stuck
   means a SPECIFIC ask ("I've ruled out A, B, C; to go further tell me the exact steps that
   trigger it" / "this needs a human decision about X"), never a vague failure.
5. V1 does not auto-loop forever. It runs one round at a time gated by the user's "keep
   going", with the danger hard-stops always in force. A later workflow product may automate
   the rounds.

## Execution Prompt Contract

The child run must receive a fix-attempt prompt, not a generic plan/build prompt.
The prompt assembler should include:

```text
Original user bug report
Typed FixPacket
Strict instructions:
  Apply only the top hypothesis's fix within its fixBoundary.
  Inspect the repo before editing.
  If evidence contradicts the packet, stop and report the conflict.
  Do not do broad cleanup or opportunistic refactors.
  Run proofCommand exactly after editing.
  Record proof output and exit status.
  If proof fails, stop with the failure output and smallest next theory.
```

Default executor decision:

- First release should default to `execution_playbook`, because the child needs
  discipline, proof, and commit behavior.
- Raw `Auto` may be offered later only if it resolves through a proof-aware
  execution preset. A raw chat/default route is too weak for this chain.
- The UI may still present this simply as the user's default fixer once the
  underlying executor is unambiguous.

## Proof Surface

The fix attempt is not done because files changed. The child run must surface:

- proof command;
- whether it ran;
- exit status;
- relevant stdout/stderr excerpt or artifact reference;
- GUI fixture and layout-watcher verdict when `requiresLayoutWatcher == true`;
- files changed / diff artifact when available;
- commit id when the executor successfully commits.

If the executor cannot run the proof command, the child run is not proven. It
must expose a typed `runProof` or `keepGoing` (try the next hypothesis) next action rather
than asking the user to infer success.

## CLI/MCP Surface

This must land in the command registry before the GUI checkbox ships.

Preferred forward CLI shape:

```bash
alln run "The history view loses finished runs after restart." \
  --team code_bug_hunt \
  --try-fix \
  --executor execution_playbook \
  --json
```

Equivalent MCP `team_run` arguments:

```json
{
  "message": "The history view loses finished runs after restart.",
  "team": "code_bug_hunt",
  "tryFix": true,
  "executorTeamId": "execution_playbook"
}
```

JSON additions:

```text
TeamRunJSON / FloorRun
  followUpPolicy?
    tryFixRequested: Bool
    executorTeamId
    gateStatus: allowed | blocked | notRequested
    blockedReason?
  links[]
    kind: diagnosisOf | fixAttemptFor | proofFor | retryOf
    runId
  nextActions[]
    kind: tryFix | keepGoing | runProof    // keepGoing narrows to the next hypothesis
    command
    mutating: true
    disabledReason?
    ruledOut[]?                            // loop memory carried into the next round
```

Error codes:

| Code | Meaning |
| --- | --- |
| `TRY_FIX_PACKET_MISSING` | Answer run did not produce a typed fix packet. |
| `TRY_FIX_PACKET_UNSAFE` | Packet hit a danger hard-stop, named no proof method, or had no actionable hypothesis. (Low confidence / T3 alone do NOT trigger this.) |
| `TRY_FIX_EXECUTOR_INVALID` | Executor team is unknown, non-mutating when mutating is required, or not runnable. |
| `TRY_FIX_PROOF_FAILED` | Child run edited but the required proof command failed. |
| `TRY_FIX_PROOF_NOT_RUN` | Child run completed without running the required proof command. |
| `RUN_WRITE_LOCK_BUSY` | Another mutating run is already editing this repo root. |

Minimal durable model support:

```text
TeamRun
  followUpPolicy?
  parentRunId?
  relatedRuns[] or links[]

RunLink
  kind
  runId
```

The parent Bug Hunt run records that Try Fix was requested and, when a child
starts, links to the child. The child records `parentRunId` and links back to the
diagnosis. `nextActions` are not enough by themselves because they describe what
can happen, not what did happen.

## Mac App Impact

Primary entry:

```text
Send to team -> Code / Bug Hunt
[ ] Try Fix
Executor: Execution Playbook
```

Rules:

- Show the checkbox only for teams that can return `FixPacket` or explicitly
  advertise `supportsTryFix`.
- Default unchecked until the follow-up contract is proven. Later, custom teams
  may save a default through `TeamPreset` / catalog state, not GUI-only state.
- Show the executor picker only when `Try Fix` is checked.
- Executor defaults to `Execution Playbook`; advanced users can change it to a
  source-scoped implementation team that still satisfies the gate.
- The running state must show honest phases per round:
  `Bug Hunt running` -> `Fix attempt (round N) running` -> result.
- The result surface is the hero. Each round shows `Tried -> Observed -> Ruled out` in
  plain language; the terminal card reads `Fixed ✓`, `Still working (round N)`, or
  `Stuck` with a SPECIFIC ask — never a vague failure or a missing-field dump.
- If blocked at the gate (danger flag / no hypothesis / no proof method), say which, plainly.
- A completed Bug Hunt Floor should expose `Try Fix` as a next action even when the original
  send did not check the box, provided the packet has an actionable hypothesis.

Floor next actions (consistent with the Floor card's two-action rule — no Save-to-Pending):

```text
Try Fix                         // first attempt
Keep going (try next hypothesis) // after a failed round, carries the ruled-out memory
Change executor
Ask another team                 // hand the packet + ruled-out to a fresh team
```

## iOS Impact

iOS presents the same contract later:

- show whether `Try Fix` was requested;
- show parent/child run status;
- allow starting the typed next action only when the Mac has the same gate result;
- never create a mobile-only auto-execute rule.

## Driver / Protocol Impact

- No driver runs multiple mutating workers for this feature.
- The executor receives one assembled fix-attempt prompt containing the typed fix
  packet plus the user's original bug report and must run in the repo root.
- Driver permission prompts remain owned by the underlying CLI. Allnighter adds
  the repo write lock and typed follow-up gate, not a second permission layer.
- Streaming callers must see honest lifecycle for both phases. If answer-run
  streaming is enabled, the child run may stream as a second phase or at minimum
  emit sourced terminal child status; it must not fake activity between phases.

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Checkbox -> run request | Core command registry | GUI-selected checkbox implies execution | Only `tryFix: true` in the run request can start the chain | Toggle UI state without request field; no child run starts |
| Markdown -> execution | FixPacket parser/stage payload | Any markdown recommendation is safe | Require typed `FixPacket` and gate pass | Bug Hunt markdown with no packet returns `TRY_FIX_PACKET_MISSING` |
| Answer team -> writer | RunService | All Bug Hunt workers may patch | Child execution run has exactly one worker | `--try-fix` with mixed-source executor is rejected |
| Danger flags -> proceed | Follow-up gate | Confidence/usefulness overrides a danger stop | Danger flags block execution regardless of confidence | Packet with credentials flag returns `TRY_FIX_PACKET_UNSAFE` |
| Low confidence -> block | Follow-up gate | Low confidence means "do not try" | Low confidence still tries (expects more rounds); only danger/no-proof/no-hypothesis blocks | Low-confidence packet with a hypothesis + proof still starts a child run |
| Parent -> child root | RunService | Child can pick a different cwd | Child run uses parent repo root | Test parent/child `repoRoot` equality |
| Generic execution prompt -> fix attempt | Prompt assembler | Normal implementation prompt is enough | Use fix-attempt prompt contract | Child prompt lacks `proofCommand`; test fails |
| Changed files -> proof | Child run projection | A diff means fixed | Require proof command outcome | Child edits without proof returns `TRY_FIX_PROOF_NOT_RUN` |

## Implementation Slices

### TFX-S00 - Packet, Parser, Gate

- Add `FixPacket` Core type.
- Add fenced `fix-packet` parser, preferably by extracting a shared fenced-block
  helper from the existing Signal Insight path.
- Update Bug Packet writer skills to emit the exact structured block.
- Add deterministic `TryFixGate` with missing packet, unsafe packet,
  no-hypothesis, no-proof-method, danger-flag, invalid-executor, and write-lock cases
  (NOT a confidence threshold).

### TFX-S01 - Request, Links, Projections

- Add `tryFix` follow-up policy shape to run request contracts.
- Add parent/child run links.
- Add `tryFix`, `keepGoing`, and `runProof` next-action kinds as needed (keepGoing carries
  the ruled-out memory to the next hypothesis).
- Add error codes to the registry and regenerate `docs/generated/alln/*`.
- Project packet, policy, gate, links, and proof state into `TeamRunJSON` and
  `FloorRun`.

### TFX-S02 - Core Chain And Prompt

- Wire the chain inside `RunService` or a narrow `FollowUpCoordinator` it owns.
- Run parent answer team, gate the final writer packet, then start the child
  execution run when allowed.
- Assemble the fix-attempt prompt.
- Record proof command output / status when the executor reports it.

### TFX-S03 - CLI/MCP Execution

- Add `alln run --try-fix --executor <team>` and MCP `team_run.tryFix`.
- Return parent run id, child run id when started, gate status, blocked reason,
  and proof status in JSON.
- Stream or terminally report both phases without fake progress.

### TFX-S04 - Mac Checkbox

- Add the `Try Fix` checkbox to eligible team sends.
- Add progressive executor selection with `Execution Playbook` as the simple
  default.
- Render parent/child progress and Floor next actions.

### TFX-S05 - Keep Going (the elimination round)

- If the proof fails, record a `ruledOut` entry (what was tried, what it disproved) and
  expose `keepGoing` — narrow to the next hypothesis, carrying the ruled-out memory into
  its order so the round never repeats a dead path.
- Surface `Tried -> Observed -> Ruled out` plainly each round; terminal states are
  `Fixed`, `Still working (round N)`, or `Stuck` with a specific ask.
- When `harnessNeeded` or after K failed rounds, escalate to an isolation-harness run.
- V1 runs one round per user "keep going" — no unattended auto-loop yet.

## Works Test

Scenario:

```text
Fixture repo has one failing test and one small known bug.
User runs Code / Bug Hunt with Try Fix enabled.
Bug Hunt returns a typed FixPacket.
Allnighter starts one mutating child run with Execution Playbook.
The child changes the file, runs the proof command, and records the result.
```

Exact command target:

```bash
alln run "Fix the failing parser test." \
  --team code_bug_hunt \
  --try-fix \
  --executor execution_playbook \
  --json
```

Assertions:

- parent run is non-mutating and has `teamPresetId == code_bug_hunt`;
- child run is mutating and has exactly one worker;
- parent and child share the same repo root;
- child run is blocked when `RunWriteLock` is held;
- a LOW/medium-confidence packet with a hypothesis + proof method DOES start a child run
  (confidence is not a gate);
- a packet with a danger flag does NOT start a child run;
- a packet with no actionable hypothesis or no proof method does NOT start a child run;
- missing fenced packet does not start a child run;
- a failed proof appends a `ruledOut` entry and exposes a "keep going" next action that
  carries the updated ruled-out memory to the next hypothesis;
- child records proof command/observation, exit status, and output/artifact reference;
- final JSON exposes parent/child links, gate state, proof state, and exact next
  actions.

Missing proof / waiver:

- No proof exists yet. This doc is a planning artifact only.

## Done When

- `Try Fix` is available through CLI/MCP before the Mac checkbox.
- Bug Hunt-style teams emit a typed `FixPacket` through a validated structured
  block and Core stores/projects it as typed truth.
- Unsafe or incomplete packets block without starting a mutating run.
- Safe packets start exactly one child execution run under the repo write lock.
- The child prompt is a fix-attempt prompt with proof instructions, not generic
  implementation prose.
- The Floor shows diagnosis, fix attempt, proof command/output, parent/child
  links, and failure recovery.
- Generated contracts and fixture round-trips are updated.
- Works Test passes locally.

## Open Questions

- Should `FixPacket` be a new `StagePayload` case, a typed attachment on
  `FloorReturn`, or both?
- Should built-in Bug Hunt default `Try Fix` off forever, or allow the user to
  save it on for custom duplicates?
- Can `execution_playbook` resolve through the user's default execution worker,
  or do we need a dedicated `fix_attempt` execution preset?
- (Resolved by the loop model) Proof failure is not a one-shot "repair" — it records a
  ruled-out entry and offers `keepGoing` to the next hypothesis. Open: what is K (failed
  in-app rounds) before auto-escalating to an isolation harness, and should the rounds ever
  run unattended or always wait for the user's "keep going"?
- How does `ruledOut` memory persist across child runs — on the parent run record, or a
  dedicated session object the chain owns?
