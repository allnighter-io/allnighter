# Floor Manager Execution Queue

Status: Founder review packet - PM Advisory Mode first
Owner: AllnighterCore + Mac app + CLI/MCP contracts + agent-first clients
Updated: 2026-06-17

## Founder Intent

Raw request:

```text
Stop making me be the copy-paste monkey and project manager for my own agents.
Allnighter should keep the project moving: know what is next, what is safe,
which worker should do it, what proof is required, and when to stop for me.
If an area is not execution-ready, Allnighter should propose the prep step:
fanout, audit, docs reconciliation, or a product question.
```

Product value:

```text
Allnighter keeps the factory moving. The user approves bounded work orders; the
specialist workers do the work; the Floor Manager keeps truth from rotting.
```

Trusted workflow slice:

```text
repo/docs/git/current workers -> Floor Manager assesses maturity ->
Floor Manager proposes the next bounded move -> user approves/edits/postpones ->
approved move enters queue -> Fanout/Execute/Audit/Docs lane runs ->
completion evidence is verified or summarized for human judgment ->
Floor Manager proposes the next move
```

## Decision

Build this as an **approval-based execution queue**, not as an autonomous project
manager.

The Floor Manager does not only consume execution-ready work. It manufactures
readiness by proposing the cheapest safe move that advances an item up the
maturity ladder:

```text
vague intent -> explored -> spec-ready -> execution-ready -> executing ->
verified -> done
```

The first wedge is **PM Advisory Mode**:

- Read current truth.
- Detect drift and completion lies.
- Assess readiness.
- Propose the next bounded move.
- Generate the handoff packet.
- Let the user approve, edit, or postpone.
- Verify claimed proof/commit before marking done.

PM Advisory Mode does **not** auto-execute unapproved work. It removes the
low-judgment overhead: re-reading docs, checking git, finding the next safe
slice, writing handoffs, tracking proof, and noticing drift.

## Product Model

Allnighter has lanes and workers:

```text
Build / Design / Copy / GUI / Audit / Docs / Fanout / Execute
```

The Floor Manager sits above those lanes:

```text
Floor Manager
  -> reads truth
  -> assesses maturity/readiness
  -> proposes / ranks next bounded move
  -> asks for approval
  -> feeds approved work to the right lane
  -> verifies proof, commit, or discovery artifact
  -> updates queue state
```

Execute is narrow:

```text
Execute consumes approved queue items and dispatches them to the selected worker.
```

The Floor Manager is not "Execute plus smarts." It owns orientation, queue state,
handoff quality, safety gates, proof verification, and drift detection.

The Floor Manager is also the main agent door. A human in the app, Hermes,
OpenClaw, MCP, or another agent should talk to the Floor Manager, not directly
to raw lanes. The lanes are the engine room; the Floor Manager is the trust
boundary.

Caller, proposer, and approver are separate:

```text
caller   = who asked Allnighter to consider work
proposer = Floor Manager proposal engine
approver = human or explicit policy envelope allowed to sign the work order
```

External agents may be callers. They do not automatically become approvers.

## Non-Goals

- No auto-execution of unapproved work.
- No broad "run the project" mode in v1.
- No external agent self-approval.
- No queue item as primary project truth.
- No silent phase-doc rewriting after commits.
- No worker self-attestation as "done."
- No "safe" label based only on LLM judgment.
- No forcing Execute on fuzzy docs just because implementation is the visible
  next button.
- No treating fanout discovery as machine-proofed truth.
- No giant task manager or backlog UI.
- No iOS-first implementation. The phone later becomes an approval/oversight
  surface, after the Mac loop works.
- No bypass around existing high-risk stops: credentials, permissions,
  destructive git, production deploys, billing/quota posture, privacy posture,
  or app distribution identity.

## First Principles

### 1. Human Judgment Is The Scarce Resource

The high-value judgment is human:

```text
What matters next?
Is this fanout synthesis convincing?
Which contradiction matters?
Is this work order worth signing?
```

The Floor Manager should not try to replace that judgment. It should reduce the
low-judgment overhead around it: collecting facts, making options scannable,
preparing handoffs, and enforcing gates.

### 2. Readiness Is A State, Not A Vibe

The Floor Manager should ask:

```text
What maturity level is this item at?
What is the cheapest safe move that advances it one level?
```

Legal move examples:

| Current maturity | Likely next move |
| --- | --- |
| vague intent | propose `spec_fanout` or `ask_user` |
| explored but contradictory | propose `synthesis_review` |
| spec-ready but not sliced | propose `docs_reconcile` or `spec_fanout` to produce slices |
| execution-ready | propose `execute_slice` |
| worker claims done | propose `verify_completion` |
| built and promoted | propose `archive_docs` |
| unsafe/dirty | propose `wait` or `resolve_conflict` |

This is the difference between a dispatcher and a floor manager.

### 3. Verification Is The Product

The proposal demos well, but the trust is built when the Floor Manager says:

```text
The worker claims done, but the cited proof did not run.
The diff touched files outside the approved slice.
The commit hash is missing.
The next item was approved earlier, but the repo changed underneath it.
```

The first implementation should build the verifier before the proposer. A bad
proposal is easy for the user to catch; a false "done" silently poisons every
next step.

### 4. Fanout Is Discovery, Not Proof

Fanout is allowed to have no machine proof. Its output is competing judgment:

```text
where workers agree
where they contradict
what assumptions they made
what work orders they imply
what the human should decide
```

That means the human belongs in the loop after fanout. The Floor Manager may
synthesize fanout results and propose follow-up work orders, but it must not
silently promote a fanout document to execution truth. Discovery output becomes
active input only after human approval or an explicit policy.

### 5. Safe Does Not Mean Useful

Safety gates answer: "May this run?"

Proposal quality answers: "Was this the right thing to suggest?"

Track both. Advisory Mode is useful only if the approve-without-edit rate is
high enough that the user saves real time. A safe-but-useless PM still makes the
user do the work.

### 6. Approval Is Perishable

Approval is a conditional grant against the repo state at the time of approval.

Every approved item must re-run gates at dispatch time. If item 1 changes files
or docs that item 2 depended on, item 2 must pause and return to the user instead
of running on stale approval.

### 7. Close Before Opening

The ranking prior is:

```text
close/prove/commit/archive in-flight work before opening a new front
```

Continuing committed work is usually lower risk and higher leverage than
starting another lane. The Floor Manager must ask "what is still open to close?"
before proposing a new feature.

### 8. The Queue Is Derived

The queue is a projection over:

- git status/log/diff
- phase docs
- active worker runs
- proof artifacts
- commit handoff state
- user approvals/postponements

The queue must not become another truth source that drifts from the repo. If it
disagrees with git or proof, git/proof wins.

## Trust Kernel

LLM proposes. Deterministic gates decide whether the proposal can be offered or
dispatched.

Hard facts:

| Gate | Source | Failure behavior |
| --- | --- | --- |
| Working tree state | `git status --short` | Warn or block if target overlaps dirty files. |
| Recent truth | `git log --oneline` + cited commits | Refuse stale "done" claims with no commit/proof. |
| Proposal kind legality | maturity assessment | Do not offer Execute when the item needs discovery/spec/human decision first. |
| Slice boundary | source docs + proposed deliverables | Warn/block if handoff is vague or too broad. |
| In-flight overlap | active queue/workers + declared paths | Do not dispatch two items into the same files/lane without approval. |
| Completion evidence | proposal kind + source doc | Execute needs proof/commit; fanout needs synthesis artifact + human review; docs cleanup needs diff/proof. |
| Proof result | process exit code + artifacts | Worker claim alone never marks execution done. |
| Commit result | git commit hash | No commit hash means "needs landing," not "done." |
| High-risk path | path/rule allowlist | Force explicit user approval or block. |

The LLM may explain a red gate. It may not override it.

## Queue Item Shape

Each item should be small enough to approve in seconds:

```text
id
title
kind: execute_slice | spec_fanout | synthesis_review | docs_reconcile |
      verify_completion | audit | deslop | ask_user | wait
status: proposed | approved | dispatch_ready | running | needs_verification |
        done | blocked | postponed
maturityBefore
maturityAfterTarget
sourceDocs[]
exactSlices[]
workerRole
suggestedWorkerTool
lane
declaredPaths[]
doNotTouch[]
dependencies[]
intendedUnblocks[]
risk: low | medium | high
riskReasons[]
proofCommands[]
proofArtifacts[]
discoveryArtifacts[]
commitRequired: true
approval:
  approvedBy
  approvedAt
  approvalBaseCommit
  approvalAuthority: human | policy
  editsApplied[]
result:
  commitHash?
  proofSummary?
  synthesisSummary?
  humanJudgment?
  driftFindings[]
```

The proposal card shown to the user should be even smaller:

```text
Next proposed item
Kind / maturity move
Why this is next
Assigned role
Read
Deliver
Do not touch
Proof or discovery output
Risk
Approve / Edit / Postpone
```

Proposal kinds:

| Kind | Purpose | Completion evidence |
| --- | --- | --- |
| `execute_slice` | Implement an execution-ready bounded slice. | Tests/proof + commit. |
| `spec_fanout` | Explore a fuzzy area and create candidate work orders. | Fanout synthesis + human review. |
| `synthesis_review` | Interpret fanout agreement/contradiction. | Human-approved decision or follow-up proposal. |
| `docs_reconcile` | Make docs match committed truth. | Diff + stale-reference scan + commit. |
| `verify_completion` | Check a worker's done claim. | Verified proof + commit or red finding. |
| `audit` | Review code/spec for risks. | Findings or explicit no-findings report. |
| `deslop` | Clean a completed slice. | Scoped diff + behavior-preserving proof. |
| `ask_user` | Request judgment where facts do not decide. | Human answer. |
| `wait` | Pause because gates are red or another worker is active. | Red gate remains visible. |

## Proposal Quality Metrics

Track these from day one:

- Approve without edit.
- Approve after edit.
- Postpone.
- Reject/wrong next item.
- Proposal required clarification.
- Worker touched files outside scope.
- Claimed proof failed verification.
- Commit missing after claimed done.
- Stale approval caught at dispatch.
- Fanout synthesis approved as-is.
- Fanout synthesis edited by human.
- Proposal kind changed by human.
- Fuzzy intent correctly classified as not execution-ready.

Edits are the highest-signal training data. When the user narrows a slice,
changes worker role, adds "do not touch," or postpones a lane, the Floor Manager
should record that delta.

## Current State

Manual existence proof:

- Codex has been acting as PM: reading docs/git, choosing next work, preparing
  copy-paste handoffs, catching stale docs, routing GUI vs backend, asking for
  commits, and archiving built phases.
- The user has been the clipboard bus and final safety gate.
- This already saved orientation time but created a new pain: the user still had
  to manually shuttle exact prompts between tools.

Existing foundations:

- Phase docs and `docs/phases/README.md` define current work and status.
- `docs/operations/Execution-Playbook.md` defines Task -> Deslop -> Code Audit
  execution.
- Commit handoff queue exists for hookless Codex save boundaries.
- GUI Visual Proof Gate exists for visible SwiftUI work.
- ThreadStore caller/proof gates show the pattern of hard wall checks.
- iOS is parked until the macOS app is done, so the first approval surface is Mac
  / CLI, not phone.
- Agent-first MCP docs already define the idea that external agents should use
  Allnighter through shared contracts, not direct private machinery.

## Truth Owner

Durable truth belongs to:

```text
git commit history
git working tree
source phase docs
proof artifacts / process exit codes
worker run records
queue approval records
human approvals / edits / postponements
fanout synthesis artifacts after human approval
```

The Floor Manager may maintain queue state, but queue state is derived. It must
re-ground from git/docs/proof every loop.

## Lie-Prone Layers

- Worker "done" summaries.
- LLM memory of previous turns.
- Phase docs after code moved but docs did not.
- Queue items approved before the repo changed.
- Broad prompts that hide file/slice boundaries.
- GUI proof screenshots that are stale or unrelated.
- Fanout summaries that flatten contradictions into false consensus.
- Spec documents that look authoritative before human review.
- External agents acting as both caller and approver.
- Uncommitted dirty work by another worker.
- PM-written summaries that silently become future truth.

## New Semantic Rules

1. The Floor Manager proposes work; it does not auto-execute unapproved work.
2. The Floor Manager may propose prep work (`spec_fanout`, audit, docs reconcile,
   ask-user) when an item is not execution-ready.
3. Done for execution means proof + commit, or an explicit human waiver. Worker
   claims are not enough.
4. Done for fanout means discovery was synthesized and presented for human
   judgment; it is not machine proof.
5. Approval is conditional and must be re-validated at dispatch time.
6. The queue is derived from repo truth; it is not the source of product truth.
7. Close before opening: land/prove/archive in-flight work before starting new
   fronts.
8. The PM may propose doc updates, but unattended doc writes are not allowed in
   v1.
9. High-risk stops remain human gates.
10. The user can always edit or postpone a proposal; those edits are product data.
11. Caller identity does not grant approval authority. Hermes/OpenClaw-style
    agents can ask; humans or explicit policy envelopes approve.

## Modes

### Mode 1 - PM Advisory Mode

Default first version.

Capabilities:

- Inspect repo/docs/git.
- Detect stale statuses and dirty-file conflicts.
- Assess maturity/readiness.
- Propose one next move: execute, fanout/spec, audit, docs reconcile,
  verify-completion, ask-user, or wait.
- Generate exact handoff text.
- Verify worker completion claims.
- Synthesize fanout outputs for human judgment.
- Produce doc-update proposals.

Does not:

- Dispatch work automatically.
- Commit automatically.
- Rewrite phase docs without approval.
- Promote fanout output to execution truth without human approval.

### Mode 2 - Approved Queue Mode

Future, only after Advisory Mode proves proposal quality.

Capabilities:

- User approves 3-5 items.
- Execute runs one item at a time.
- Gates re-fire before each dispatch.
- Any red gate pauses the queue.

### Mode 3 - Low-Risk Auto Mode

Future, narrow only.

Possible scope:

- docs-only cleanup with clean file ownership;
- mechanical archive/index updates;
- proof commands are deterministic and cheap;
- rollback unit is one commit.

Never default for code, permissions, credentials, schema migrations, production
deploys, or broad refactors.

## Implementation Impact

Core/Engine:

- Add queue item model and gate result model.
- Add proposal kind and maturity assessment.
- Add a deterministic gate runner that reads git/proof facts.
- Add approval records with base commit.
- Add dispatch-time revalidation.
- Add caller/proposer/approver separation.

CLI:

- `alln floor propose`
- `alln floor verify`
- `alln floor status`
- `alln floor handoff`
- `alln queue propose`
- `alln queue approve <id>`
- `alln queue edit <id>`
- `alln queue postpone <id>`
- `alln queue status`
- `alln queue verify <id>`

Mac app:

- First surface can be plain:
  - Next proposed item
  - Needs human judgment
  - Running
  - Needs verification
  - Blocked
  - Done today
- Approval UX is `Approve / Edit / Postpone`, not a giant task board.

MCP:

- Hermes/OpenClaw-style clients call the Floor Manager, not raw lanes.
- Expose proposal/status/handoff tools after CLI contract is stable.
- Approval tools must distinguish human approval from policy-bounded approval.

iOS:

- Later approval/oversight surface:
  - "Approve this next item?"
  - "Fanout found three contradictions; choose the direction."
  - "This item went red at dispatch."
  - "Done today."
- Not v1.

## Ordered Slices

- [ ] FMQ-S00 - Contract packet: define queue item schema, proposal kinds,
  maturity states, gate result schema, caller/proposer/approver, statuses, and
  high-risk stop list. No dispatch.
- [ ] FMQ-S01 - Truth scanner: git status/log/diff, active dirty paths, recent
  commits, phase board read, proof artifact existence.
- [ ] FMQ-S02 - Verifier first: given a worker completion summary, verify claimed
  proof commands/artifacts, commit hash, doc updates, and out-of-scope files.
- [ ] FMQ-S03 - Readiness assessor: classify vague/explored/spec-ready/
  execution-ready/running/needs-verification/done and choose legal move kinds.
- [ ] FMQ-S04 - Proposal generator: produce one compact next-move proposal with
  kind, maturity move, why-next, read/deliver/do-not-touch/evidence/risk.
- [ ] FMQ-S05 - Fanout proposal packet: generate bounded `spec_fanout` proposals
  with team, prompt, source docs, intended execution item, and synthesis shape.
- [ ] FMQ-S06 - Approval records: approve/edit/postpone with base commit and
  edit-delta logging.
- [ ] FMQ-S07 - Dispatch-time revalidation: approved item becomes
  `dispatch_ready` only if gates are still green at current HEAD.
- [ ] FMQ-S08 - Handoff emitter: generate copy-paste worker prompt, fanout
  packet, or direct handoff packet from approved item.
- [ ] FMQ-S09 - Mac/CLI Advisory surface: show proposed/running/blocked/needs
  verification/needs-human-judgment/done-today without auto-running.
- [ ] FMQ-S10 - Agent-first caller surface: Hermes/OpenClaw/MCP clients can ask
  for proposals/status, but cannot self-approve outside explicit policy.
- [ ] FMQ-S11 - Approved Queue Mode spike: serial dispatch for 3-5 approved
  low/medium-risk items, halted by any red gate. Not enabled by default.

## Works Test

Advisory Mode:

```text
Start with a repo that has:
- one committed completed slice;
- one stale phase doc;
- one unrelated dirty GUI file;
- one active backend-ready phase doc;
- one fuzzy founder idea with no slices or done criteria;
- one worker summary claiming done with a missing commit hash.

Run proposal.

Expected:
- The missing commit is flagged as "needs landing", not done.
- The stale doc is flagged as drift.
- The unrelated dirty GUI file is included as a conflict warning only if the
  proposed item touches the same files/lane.
- The proposed next item is one bounded backend item with exact docs, slices,
  proof commands, and do-not-touch list.
- The user can edit the proposal; the edit delta is recorded.
- Approval stores the base commit.
- If HEAD changes before dispatch, gates re-run and the item pauses if unsafe.
```

Readiness / fanout mode:

```text
Start with a phase README that describes a product idea but has no truth owner,
no implementation slices, no proof, and conflicting mentor notes.

Run proposal.

Expected:
- The Floor Manager does not propose Execute.
- It proposes `spec_fanout` or `ask_user`.
- The fanout proposal names the team, source docs, exact prompt, intended output
  artifact, contradictions to surface, and what execution item it should unblock.
- Completion evidence is "fanout synthesis presented for human judgment", not
  "tests passed."
- No resulting work order enters the execution queue until the human approves
  the synthesis or an explicit policy allows it.
```

Verifier Mode:

```text
Worker says:
"Done, tests passed, commit abc123."

Expected:
- Verify commit exists on current branch.
- Verify touched files are within approved scope or flagged.
- Verify named proof command ran, or mark as unverified.
- Mark done only when proof + commit are real.
```

## Proof Command

Initial implementation should include deterministic unit tests for:

```text
queue item Codable round trip
gate red/green results
dirty path overlap
approval base-commit invalidation
worker completion verification
proposal edit-delta logging
readiness classification
proposal kind legality
fanout completion evidence
caller/proposer/approver separation
high-risk path stop
```

Green wall:

```text
swift test --package-path Packages/AllnighterCore
bash scripts/check.sh
```

## Done When

- The Floor Manager can propose one next useful bounded move from repo/docs/git
  truth.
- The proposal names kind, maturity move, exact docs, slices or intended
  discovery output, worker role, do-not-touch scope, evidence, risk, and
  why-next.
- The user can approve, edit, or postpone.
- Approved items store the base commit and re-run gates at dispatch time.
- Worker completion claims are verified before `done`.
- Fanout outputs are synthesized for human judgment and are not silently promoted
  to execution truth.
- External agents can call the Floor Manager for proposals/status without gaining
  approval authority.
- The PM never marks done on a worker's word alone.
- Queue state never overrides git/proof truth.
- Advisory Mode tracks approve/edit/postpone metrics.

## Open Questions

- What is the minimal persisted queue store: JSON under Application Support, or
  thread turns inside a project thread?
- Should the queue be project-root scoped, repo scoped, or Allnighter workspace
  scoped?
- How should active external tools be represented when Allnighter did not launch
  them?
- What is the first UI: Mac panel, CLI-only, or thread turn proposal?
- What proposal latency is acceptable before the tool feels slower than doing it
  manually?
- Which high-risk path rules are global vs repo-specific?
- What is the smallest fanout synthesis format that surfaces agreement,
  contradiction, assumptions, and candidate work orders without becoming a new
  docs swamp?
- Are any policy-bounded approvals allowed in v1, or is every approval human?
- Can Hermes/OpenClaw provide a good Floor Manager chat surface before the Mac
  panel exists, or should they wait for the CLI contract?
