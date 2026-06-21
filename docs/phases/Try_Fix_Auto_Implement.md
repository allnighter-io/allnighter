# Try Fix: Auto-Implement After Bug Hunt

Status: Draft feature packet
Owner: AllnighterCore + CLI/MCP + Mac app
Updated: 2026-06-21

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

Reject:

- Treating any plausible Bug Hunt prose as executable intent.
- Auto-starting a fix from medium/low confidence packets in v1.
- Running more than one mutating worker.
- Hiding two disconnected runs behind optimistic UI; the user must be able to
  inspect diagnosis -> fix attempt -> proof.
- Adding a new user-facing workflow noun. This is a run follow-up policy.

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
3. If `Try Fix` was requested and the answer run returns a high-confidence safe
   `FixPacket`, Allnighter starts exactly one child execution run with the
   selected executor team.
4. If `Try Fix` was not requested, a safe packet still produces a typed
   `tryFix` next action so a past Bug Hunt can be acted on later.
5. If the packet is missing required fields, has medium/low confidence, or hits
   a high-risk stop, Allnighter does not execute. It returns an actionable
   blocked result.
6. The mutating child run uses the same repo root and takes the repo write lock.
7. The parent and child runs are linked durably so the Floor can show:
   diagnosis -> fix attempt -> proof.
8. Proof failure does not trigger an automatic loop. V1 may expose one explicit
   repair next action that feeds the proof failure back into the same packet.

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
  confidence: low | medium | high
  tier: T0 Fast | T1 Boundary | T2 SSOT | T3 Critical
  symptom
  repro
  bugFingerprint
  truthOwner
  lieProneLayer
  recommendedFix
  fixBoundary
  filesLikelyTouched[]
  proofCommand
  proofExpectation
  guiProofFixture?
  requiresLayoutWatcher: Bool
  riskFlags[]
  stopReason?
```

Required for automatic execution in v1:

- answer run status is terminal success, not partial/failed
- final writer stage is produced by the Bug Packet writer
- fenced `fix-packet` block parses and validates
- `confidence == high`
- `tier != T3 Critical`
- `truthOwner` non-empty
- `recommendedFix` non-empty
- `fixBoundary` non-empty
- `proofCommand` non-empty
- no high-risk `riskFlags`
- selected executor team is mutating, runnable, and resolves to exactly one
  worker/source

High-risk stops:

- privacy or session data leaving the user's machines
- credentials, Keychain items, API keys, or auth state
- Full Disk Access or permission posture changes
- destructive process kill, deletion, or git history rewrite
- App Store, notarization, distribution identity, TestFlight release
- billing, entitlement, quota-spend behavior, or production deploy

Medium confidence behavior:

```text
Packet ready, no child run started.
Reason: confidence is medium.
Next actions: run deeper Bug Hunt, save packet, or manually inspect.
```

Low confidence behavior:

```text
Blocked. No fix attempt.
```

## Execution Prompt Contract

The child run must receive a fix-attempt prompt, not a generic plan/build prompt.
The prompt assembler should include:

```text
Original user bug report
Typed FixPacket
Strict instructions:
  Apply only the recommendedFix within fixBoundary.
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
must expose a typed `runProof` or `retryFixWithProofFailure` next action rather
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
    kind: tryFix
    command
    mutating: true
    disabledReason?
```

Error codes:

| Code | Meaning |
| --- | --- |
| `TRY_FIX_PACKET_MISSING` | Answer run did not produce a typed fix packet. |
| `TRY_FIX_PACKET_UNSAFE` | Packet had missing proof, low confidence, T3 tier, or high-risk flags. |
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
- The running state must show two honest phases:
  `Bug Hunt running` then `Fix attempt running`.
- If blocked, the user sees the missing field or stop reason, not a vague failure.
- A completed Bug Hunt Floor should expose `Try Fix` as a next action even when
  the original send did not check the box, provided the packet is safe.

Floor next actions:

```text
Try Fix
Run fix with Execution Playbook
Change executor
Save packet to Pending
Send packet to another team
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
| Risk flags -> proceed | Follow-up gate | Model confidence overrides high-risk stop | High-risk flags block execution | Packet with credentials flag returns `TRY_FIX_PACKET_UNSAFE` |
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
  confidence, T3, invalid executor, and write-lock cases.

### TFX-S01 - Request, Links, Projections

- Add `tryFix` follow-up policy shape to run request contracts.
- Add parent/child run links.
- Add `tryFix`, `runProof`, and `retryFixWithProofFailure` next-action kinds as
  needed.
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

### TFX-S05 - Proof Failure Recovery

- If the child proof fails, show the failure and expose a typed next action:
  `Retry fix with proof failure`.
- Do not auto-loop indefinitely. V1 may allow one explicit repair attempt.

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
- medium-confidence packet does not start a child run;
- unsafe packet does not start a child run;
- missing fenced packet does not start a child run;
- child records proof command, exit status, and output/artifact reference;
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
- Is one explicit repair attempt enough for proof failures, or should that wait
  for a later workflow/loop product?
