# Project Spine And Project Manager

Status: Code red implementation spec - blocks Project Manager queue/autopropose
work
Owner: AllnighterCore + Mac app + CLI/MCP contracts + agent-first clients
Updated: 2026-06-18

## Authority

This doc owns the Project and Project Manager product contract.

Read with:

- `docs/strategy/Allnighter-Agent-Control-Loop-Strategy.md`
- `docs/phases/Work_Order_Team_Model.md`
- `docs/phases/CLI_Product_Spine.md`
- `docs/phases/CLI_Implementation_Contract.md` (shared error envelope, exit codes,
  contract registry)
- `docs/phases/Persistent_Work_Threads.md`
- `docs/phases/Pending_Work_And_Drain.md` (Pending lifecycle + always-active
  execution-lane gate)
- `docs/phases/Team_Catalog.md` + `docs/phases/Team_And_Skill_Catalogs.md`
  (teams/skills the Project Manager dispatches and runs)
- `docs/phases/Agent_First_MCP_And_Messaging_Workflows.md` (MCP tool surface)
- `docs/phases/Stalled_Work_Watchdog.md` (stalled-work detection over Project truth)
- `docs/operations/Execution-Playbook.md`

Durable semantics start here or in the named owning Core/CLI docs. SwiftUI,
prompt prose, generated output, local fixtures, and worker replies may render or
derive this truth; they do not own it.

## Founder Intent

Raw request:

```text
Allnighter is useless without the floor. When I start a new agent, it should be
inside a Project: the local folder / git repo, like Cursor. Regular chat should
be chat with the Project Manager for that Project. It does not always need to
become a work order. The Project Manager should know what project it is managing,
what is current, what is safe, and what to propose next.
```

Dogfood hardening:

```text
Double down on the Project Manager and make that insanely great. The product
only survives if a serious Cursor + Claude power user starts in Allnighter
because the Project Manager lowers the cognitive load before and after execution.
```

Product value:

```text
Projects give workers a floor. The Project Manager keeps that floor moving.
```

Trusted workflow slice:

```text
open/add Project
-> ask Project Manager
-> answer or orient from Project truth
-> propose one bounded next move
-> approve/edit/postpone
-> reveal or dispatch an exact work order
-> capture the return
-> verify proof before done
-> recommend the next move
```

## Product Claim

Allnighter is the local Project Manager for the agents the user already uses.

It should feel like:

```text
This thing knows my repo, remembers the work, asks the right agents, turns
ambiguity into a bounded next move, dispatches it, and tells me whether it
actually landed.
```

It must not feel like:

```text
A worse IDE, a second issue tracker, a terminal viewer, or a new process tax.
```

The Project Manager is the star. Team runs, pending work, dispatch,
verification, and mobile control are capabilities of the Project Manager loop.

## Product Unit

The first dogfoodable product unit is:

```text
Project
  -> Project Manager chat
  -> Project context packet
  -> proposal
  -> editable work order
  -> dispatch or reveal
  -> return review
  -> verified next move
```

Do not ship a "Project Manager queue" that cannot also answer normal chat and
verify returned work. Do not ship Project chat that cannot grow into proposal,
dispatch, and return review.

## Decision

Public noun: **Project**.

Allnighter may use "workspace" internally if code needs a local filesystem term,
but the product surface says Project.

The Project is the durable container above threads, runs, pending items,
attachments, approvals, proposals, work orders, and verification records. A
Project usually maps to one local git repo. v1 may also represent a non-git
folder with reduced execution guarantees.

The Project Manager is not a separate lane, button, or layer above chat. The
default chat in a Project is chat with that Project's Manager.

```text
Project
  -> Project Manager thread
  -> work threads
  -> team runs
  -> proposals
  -> approved work orders
  -> pending/running work
  -> returns
  -> verification records
```

A chat message only becomes a work order when the user asks for work or approves
a proposed work order.

## Why This Is Code Red

Without Projects, Allnighter cannot reliably answer:

- which repo/folder a worker is allowed to touch;
- which installed CLIs are actually ready inside that repo/folder;
- which docs and commits define current truth;
- which threads belong together;
- which Pending items are allowed to drain;
- where attachments should stage for invocation;
- where proof commands should run;
- whether a proposed next item is safe;
- which dirty files are relevant versus unrelated;
- what "new agent in Allnighter" actually means;
- whether returned work landed or merely claimed completion.

Threads without Projects become floating conversations. Project Manager without
Projects becomes generic PM chat. Execute without Projects becomes unsafe.

## Product Model

### Project

Project is the product-owned representation of a local work floor.

Minimum Core model:

```text
Project
  id
  displayName
  localRootPath
  normalizedRootPath
  kind: gitRepo | folder
  rootState: available | missing | permissionDenied
  gitRemoteURL?
  gitBranch?
  gitHead?
  gitDirtySummary?
  createdAt
  lastOpenedAt
  pinned
  archived
  docsEntrypoints[]
  proofCommands[]
  workerReadinessSummary?
  defaultCodeTeamId?
  defaultDesignTeamId?
  defaultCopyTeamId?
  managerThreadId?
  managerModelId?
```

Rules:

- `localRootPath` is required for mutating Build/Execute work.
- `normalizedRootPath` is the duplicate-detection key.
- The same normalized local root must not create duplicate active Projects.
- Git metadata is observed, not invented. If unavailable, fields are null and
  the reason is visible.
- `rootState != available` blocks mutating dispatch.
- A Project can be archived without deleting local files.
- Project archive hides the Project from the active rail; it does not delete
  threads, runs, attachments, proposals, returns, verification records, or
  commits.
- Non-git folder Projects may support chat, team runs, reveal, and manual handoff.
  Mutating dispatch requires an explicit proof waiver and can never be marked
  commit-verified.

### Root Normalization

Root normalization is Core-owned and tested.

Rules:

- expand `~`;
- resolve symlinks where the platform can do so safely;
- collapse `.` and `..`;
- preserve the user-facing display path separately from the normalized key;
- detect missing roots without deleting the Project;
- never infer two Projects from nested paths unless the user explicitly adds
  both as separate Projects.

### Project Worker Readiness

Global setup is not Project readiness.

Global setup answers:

```text
Is Claude Code installed?
Is Codex installed?
Is Grok installed?
Is the user authenticated somewhere?
```

Project worker readiness answers:

```text
Can this worker safely run inside this Project root right now?
```

V1 decision:

```text
Auto-readiness detection: yes.
Auto-configuration / auto-authorization: no.
```

Minimum model:

```text
ProjectWorkerReadiness
  projectId
  sourceId
  workerId?
  status: ready | notInstalled | authRequired | needsProjectAuthorization |
          interactiveRequired | unsafeToProbe | blocked | unknown
  checkedAt
  probeKind: silent | explicitRecheck | userInitiatedRun
  probeCommandLabel?
  lastError?
  setupHint?
```

Canonical status meanings:

| Status | Meaning |
| --- | --- |
| `ready` | The worker can run in this Project root now. |
| `notInstalled` | The CLI/source is not installed or cannot be resolved. |
| `authRequired` | The CLI/source exists but needs provider sign-in. |
| `needsProjectAuthorization` | The CLI/source needs this Project/folder trusted or authorized by the user. |
| `interactiveRequired` | The next meaningful check requires an interactive prompt; do not run silently. |
| `unsafeToProbe` | The driver has no declared non-mutating Project probe. |
| `blocked` | A non-auth, non-install, non-root blocker prevents this worker in this Project, such as policy, unsupported Project kind, missing local dependency, or denied capability. |
| `unknown` | Allnighter lacks enough evidence; do not treat as ready. |

Rules:

- Adding or opening a Project may run safe, non-mutating readiness probes in the
  background.
- A Project is usable when at least one worker is ready in that Project root.
- Dispatch to a specific worker requires that worker to be ready in that
  Project root.
- A ready worker for one Project does not imply readiness in another Project.
- A ready worker from one CLI does not authorize or configure another CLI.
- Readiness probes are driver-owned. There is no universal "can this CLI work
  here?" command.
- A silent probe is allowed only when the driver declares it non-mutating and
  bounded by timeout.
- The safe probe declaration lives on the driver manifest / `DriverRegistry`
  contract, alongside setup detection metadata. S05 must extend that contract;
  see `docs/phases/setup/01_CLI_Detection_Auth_And_Bench.md` and
  `docs/phases/CLI_Implementation_Contract.md`.
- Probes must not accept trust prompts, log in, write vendor authorization,
  approve terms, change permissions, or configure a Project for a CLI.
- If a driver cannot prove a safe silent probe, report `unsafeToProbe` or
  `unknown`, not `ready`.
- If a probe would require an interactive trust prompt, report
  `needsProjectAuthorization` or `interactiveRequired`.
- Allnighter may write its own readiness cache; it must not write vendor config
  as part of readiness detection.
- A user-initiated run/check may update readiness from the observed result. It
  is an explicit observation path, not a silent probe and not permission to
  accept prompts on the user's behalf.
- Cached readiness invalidates on explicit recheck, Project root change,
  `rootState` change, driver manifest/probe declaration change, global setup
  status change, observed auth/trust failure, or TTL expiry. S05 owns the exact
  TTL, but it must be short enough that readiness does not become stale product
  truth.

Driver manifest addition:

```text
DriverManifest.projectProbe?
  mode: safeCommand | none
  command / args or invocation reference
  timeoutSeconds
  readyExpectation
  authErrorPatterns[]
  projectAuthorizationPatterns[]
  blockedPatterns[]
  declaredNonMutating: true
```

Rules:

- A missing `projectProbe` means `unsafeToProbe`, unless readiness is observed by
  an explicit user-initiated run/check.
- `declaredNonMutating` must be true for silent background detection.
- Probe output classification maps only to the canonical
  `ProjectWorkerReadiness.status` list above.
- Driver manifests may use CLI-specific safe flags. Example: Codex-style probes
  may use flags equivalent to "do not require git repo" only when those flags are
  safe for the target command.

Simple empty-state copy:

```text
No workers are ready for this project yet.

Open Claude Code, Codex, Grok, Gemini, or Antigravity in:
<project folder>

Complete any trust or login prompts, then recheck workers.
```

Buttons:

```text
Open Folder
Recheck Workers
```

`Open Folder` reveals the Project root in Finder. If a future GUI adds "open a
terminal/editor here," that must be a separately labeled action. `Recheck
Workers` reruns only declared safe probes.

This is a detection contract, not a setup wizard. Setup remains the user's
relationship with each CLI/vendor.

### Thread Binding

Every durable thread should belong to one Project once this phase lands.

```text
WorkThread
  projectId
  localRootPathSnapshot?
```

`localRootPathSnapshot` is a historical receipt. It is not the owner of current
Project scope.

Rules:

- New durable threads require `projectId`.
- Existing threads migrate from `workingDir` / run root by a deterministic rule
  (the same rule Pending migration uses): normalize the snapshot path, then bind
  to the existing Project whose `normalizedRootPath` exactly equals it; else to the
  existing Project that is the nearest ancestor root of it; else, if exactly one
  git repo root contains the path, create/reuse a Project at that repo root; else
  leave the thread Unassigned. Ambiguous matches (two candidate Project roots,
  neither an ancestor of the other) resolve to Unassigned, not a guess.
- Threads with no reliable root migrate to an explicit Unassigned state and are
  blocked from mutating dispatch until assigned.
- A thread may reference runs, pending items, proposals, and returns, but Project
  remains the parent context.
- Existing `alln thread ...` commands may infer Project from a thread id when
  the binding is unambiguous. New public Project commands should prefer
  `alln project ...`.

### Project Manager Thread

The Project Manager thread is ordinary thread truth with a reserved target.

Rules:

- `managerThreadId` points to the default Project Manager thread.
- The Mac UI should pin it in the Project rail.
- If the thread record is missing, Core may recreate it and keep the same
  Project identity.
- v1 should not expose destructive deletion of the Manager thread. Archiving or
  hiding ordinary work threads is separate.

### Project Context Packet

The Project Context Packet is the input summary the Project Manager uses for
chat, proposals, dispatch, and verification. It is generated on demand from
owned truth.

It is not a new source of truth.

Minimum shape:

```text
ProjectContextPacket
  projectId
  generatedAt
  root
    localRootPath
    kind
    rootState
  git
    branch?
    head?
    remote?
    dirtySummary?
    recentCommits[]
  docs
    entrypoints[]
    recentlyChanged[]
    staleCandidates[]
  threads
    managerThreadId?
    recentThreadSummaries[]
    unresolvedQuestions[]
  work
    activeRuns[]
    pendingItems[]
    openProposals[]
    recentReturns[]
    verificationFindings[]
  workers
    readinessSummary
    readyWorkerIds[]
    blockedWorkerSummaries[]
  proof
    commands[]
    lastResults[]
  warnings[]
```

Rules:

- Packets should be compact and source-labeled.
- Packets may be persisted as receipts on turns/proposals for audit, but the
  next turn regenerates from current truth.
- A packet must never hide a failed worker, missing root, dirty Project, failed
  proof, stale-doc warning, or Project worker readiness blocker.
- `blockedWorkerSummaries[]` is the compact Project-context projection of
  `ProjectWorkerReadiness` entries whose status is not `ready`; it is not a
  separate durable status system.
- Prompt assembly may quote from the packet; semantic rules remain in Core.

### Project-Scoped Pending

Pending belongs to a Project.

`Pending_Work_And_Drain.md` owns the detailed Pending lifecycle. Native
scheduling/drain is parked; CLI/MCP/user/external-agent triggers may run Pending
items. This spec owns the Project binding rule:

```text
PendingItem
  projectId
  threadId?
  workOrderId?
  localRootPathSnapshot?
```

Rules:

- New Pending items require `projectId`.
- Existing Pending items migrate from thread/run/workingDir when possible.
- Unassigned Pending items are visible in a migration/repair bucket and cannot
  run until assigned to a Project.
- Global Pending views are aggregate floor views grouped by Project. They are
  not a global durable queue.
- Reorder is scoped to one Project plus one execution lane. A reorder action must
  not move work across Projects.
- Execution attempts derived from Project-scoped Pending items must copy
  `projectId` from the Pending item and never invent a different Project.
- The execution-lane serialization gate (one Running Execute per lane, FIFO,
  head-only) is **always active in v1** per `Pending_Work_And_Drain.md` and is
  evaluated per Project — not only if native drain is revived. Every explicit
  Project dispatch/run trigger passes it; a non-head Execute item is refused with
  `executionLaneBusy`.
- If native drain is ever revived, admission, dirty-state checks, proof roots, and
  attachment mirrors are additionally evaluated per Project (the execution-lane
  gate above is already always-on).
- A Project archive blocks new Pending runs for that Project unless the user
  explicitly unarchives or moves the item.
- A missing Project root keeps that Project's Pending items Pending with a
  sourced blocker; it does not block unrelated Projects.
- Pending must not use raw `workingDir` as its scope owner after migration.
  Working-directory snapshots are receipts only.

### Project Manager Turn

Every Manager response is a typed turn projected into chat.

Minimum machine shape:

```text
ProjectManagerTurn
  id
  projectId
  threadId
  userMessageId
  createdAt
  mode: answer | orient | propose | delegate | handoff | dispatch | verify | wait
  contextPacketId?
  answerMarkdown?
  proposals[]
  handoff?
  verification?
  warnings[]
  nextActions[]
```

Rules:

- A turn may answer without proposals.
- A turn may propose without dispatching.
- A dispatch turn must link to an approved work order.
- A verify turn must link to a return or explicit worker completion claim.
- `nextActions` are typed actions, not prose-only suggestions.

### Project Manager Execution

The Project Manager is the star, so its execution substrate is explicit: a Manager
turn is produced by a **model invocation**, not by hand-written logic and not by a
shell subprocess in the repo. It reuses the same worker runner and model resolution
as team runs — there is no new execution path.

```text
ProjectManagerExecution
  input: ProjectContextPacket + user message + thread history excerpt
  engine: the resolved manager model (a planner-capable model)
  output: one ProjectManagerTurn (typed)
```

Rules:

- Manager model resolution: `Project.managerModelId` if set, else the strongest
  ready planner-capable model from `ModelCatalog`/Bench (see
  `Team_Catalog.md`/`Model_Catalog_And_Bench_Roster.md`). If no model is
  ready, the turn is `mode: wait` with a sourced readiness blocker — never a
  fabricated answer.
- The manager model honors reasoning effort where its source supports it (the
  per-worker model reasoning level; never a team-shape control).
- `answer`/`orient` are a single manager-model call over the packet. `propose`
  is the manager model producing one bounded `ProjectProposal`. `delegate`
  delegates to a real team run (`Team_Catalog.md`); the Manager does not
  fake a team.s breadth itself. `verify` runs proof + git observation (see Return
  And Verification) and uses the manager model only to interpret results.
- The manager prompt/skill is built-in catalog content snapshotted into the turn
  for audit; it is not editable prompt prose that can redefine semantics.
- Chat/propose calls give the model the packet, not raw shell or filesystem
  access. Only verification executes declared commands, under its own contract.
- The Manager call is itself a worker run and is recorded as run truth (id,
  model, transcript ref) so a Manager answer is as auditable as any worker output.

### Proposal

A Proposal is one bounded next move for one Project.

Minimum model:

```text
ProjectProposal
  id
  projectId
  threadId
  createdFromTurnId
  kind
  status: proposed | approved | postponed | running | returned | verified |
          blocked | cancelled
  title
  whyNow
  userGoal
  currentTruth[]
  scope
  nonGoals[]
  likelyFilesOrAreas[]
  risks[]
  blockingQuestions[]
  suggestedLane?
  suggestedTeamId?
  suggestedEffort?
  workOrderId?
  approval?
  baseGitHead?
  expiresWhen?
  createdAt
  updatedAt
```

Rules:

- A proposal is not Project truth. It is a proposed move derived from Project
  truth.
- Proposals must be editable before approval.
- Approval stores who approved, when, and the approved content hash.
- Approved proposals store the observed base git head when available.
- Dispatch revalidates root, approval, base head, dirty state, and worker
  readiness.
- Postponed proposals remain visible but should not block new proposals unless
  they conflict.
- Cancelled proposals remain historical receipts.
- `kind` is one of the Legal Proposal Kinds enum (see Readiness And Proposal Law):
  `spec_explore | synthesis_review | execute_slice | docs_reconcile |
  verify_completion | audit | deslop | ask_user | wait`.
- `suggestedTeamId` carries team shape (axis 2). `suggestedEffort` is the optional
  per-worker model reasoning level (axis 1: `low | med | high`) where the chosen
  source supports it; it is never a team-depth dial. Either may be null when the
  Manager has no preference.

### Work Order

A Work Order is the dispatchable payload derived from an approved Proposal.

Minimum model:

```text
WorkOrder
  id
  proposalId
  projectId
  title
  lane: code | design | copy | none
  mode: reveal | dispatch
  targetWorkerId?
  targetAgent?
  promptBody
  scope
  nonGoals[]
  constraints[]
  expectedReturn
  proofCommands[]
  proofWaiver?
  baseGitHead?
  localRootPathSnapshot
  attachmentIds[]
  createdAt
```

Rules:

- The user can reveal a work order without invoking a worker.
- Direct dispatch is an explicit send mode. Do not add a second confirmation
  ceremony after the user chooses dispatch from an approved work order.
- Normal dispatch targets the selected Project root.
- A work order must include proof commands or an explicit waiver.
- A work order must name the expected return format.

### Return And Verification

Worker output is a return. It is not proof by itself.

Minimum model:

```text
WorkReturn
  id
  projectId
  workOrderId
  runId?
  targetWorkerId?
  transcriptRef?
  summary?
  reportedFiles[]
  reportedProof[]
  status: returned | failed | interrupted | cancelled
  createdAt
```

```text
VerificationRecord
  id
  projectId
  workOrderId
  returnId?
  outcome: verified | notVerified | needsHuman | waived
  proofResults[]
  gitObservation?
  scopeFindings[]
  docsDriftFindings[]
  missingProof[]
  recommendation
  createdAt
```

Rules:

- "Done" requires `verified` or an explicit human waiver.
- A worker's "done" claim can trigger verification; it cannot complete it.
- If proof cannot run, the verification outcome is `needsHuman` or `waived`, not
  `verified`.
- If no commit exists, the record can still verify proof and scope, but it must
  not claim commit verification.

Proof execution:

- Verification runs the Work Order's declared `proofCommands` as bounded
  subprocesses at the Project root (`localRootPathSnapshot`). This is a real
  capability: Allnighter executes the user-declared commands as the user's own
  shell — it adds no implicit network access, privilege escalation, or commands
  the user did not declare.
- Each proof command has a timeout and captured exit code, stdout/stderr tail, and
  duration, recorded in `VerificationRecord.proofResults[]`.
- A non-zero exit, a timeout, or a missing command yields `notVerified` or
  `needsHuman` (with the failure sourced), never `verified`.
- If the user prefers not to let Allnighter run commands, proof is reveal-only and
  the outcome is `needsHuman` or `waived` — the user runs proof themselves.
- Proof commands never mutate git state (no commit/reset/checkout) and never clean
  the working tree; that remains out of scope (see Non-Goals).
- Expanding proof execution beyond declared per-Project commands (e.g. arbitrary
  Manager-authored commands) routes through the high-risk stop policy first.

## Project Manager Responsibilities

The Project Manager can:

- answer normal Project questions;
- summarize current Project state;
- find stale docs and contradictions;
- propose the next bounded move;
- propose sending a team when a spec is fuzzy;
- synthesize the team.s output for human judgment;
- shape an editable work order;
- reveal or dispatch an approved work order;
- verify a worker completion claim;
- prepare a handoff prompt;
- route approved work to Code, Design, Copy, GUI, Audit, Docs, or
  Execute paths.

It must not:

- auto-execute unapproved work;
- mark worker claims done without proof, commit observation, or waiver;
- silently rewrite phase docs;
- treat team-run discovery as machine proof;
- self-approve because an external agent asked;
- invent Project truth from prompt prose;
- hide dirty state, failed workers, missing roots, blocked proof, or Project
  worker readiness blockers;
- manage branches/worktrees/commits as a v1 product promise.

## Chat Law

Regular chat in a Project is Project Manager chat.

Decision tree:

| User intent | Manager behavior |
| --- | --- |
| "Where are we?" | Answer from Project context. No proposal unless useful and clearly separated. |
| "What should we do next?" | Return one bounded proposal or one visible blocker. |
| "Explore this fuzzy idea." | Propose or send a team, then synthesize for human judgment. |
| "Make this a work order." | Create/edit a dispatchable work order. Do not dispatch yet unless the user chooses dispatch. |
| "Run it." with approved work order | Revalidate gates, then dispatch or reveal based on send mode. |
| "Run it." without approved work order | Create a proposal/work order draft and ask for approval/edit. |
| Worker says "done." | Run verification before advancing state. |

No new top-level "Consult Project Manager" surface is needed. The Project
Manager is present because the user is inside a Project.

Chat does not have to produce a proposal. The Project Manager can just answer.

## Readiness And Proposal Law

The Project Manager manufactures readiness by proposing the cheapest safe move
that advances an item.

Readiness path:

```text
vague intent
-> explored
-> spec-ready
-> approved
-> dispatch-ready
-> running
-> returned
-> verified
-> done
```

Legal proposal kinds:

| Kind | Purpose | Completion evidence |
| --- | --- | --- |
| `spec_explore` | Explore a fuzzy area and create candidate work orders. | Fanout synthesis + human decision. |
| `synthesis_review` | Interpret team agreement/contradiction. | Human-approved decision or follow-up proposal. |
| `execute_slice` | Implement an execution-ready bounded slice. | Return + proof + commit observation or waiver. |
| `docs_reconcile` | Make docs match committed truth. | Diff + stale-reference scan + proof. |
| `verify_completion` | Check a worker's done claim. | Verification record. |
| `audit` | Review code/spec for risks. | Findings or explicit no-findings report. |
| `deslop` | Clean a completed slice. | Scoped behavior-preserving proof. |
| `ask_user` | Request judgment where facts do not decide. | Human answer. |
| `wait` | Pause because gates are red or another worker is active. | Visible blocker remains. |

Fanout is discovery, not proof. Its output is synthesized so the human can judge
agreement, contradiction, assumptions, and candidate work orders.

## Dispatch Gates

Dispatch may proceed only when all required gates pass:

| Gate | Rule |
| --- | --- |
| Project selected | Mutating work requires a selected Project. |
| Root available | `rootState` must be `available`. |
| Approval present | Work order must link to an approved Proposal or an explicit user dispatch action that records approval. |
| Base head checked | If `baseGitHead` exists and current head differs, revalidate or block. |
| Dirty state reviewed | Dirty Project files are visible before dispatch. |
| Scope bounded | Work order names scope and non-goals. |
| Worker ready in Project | Target worker/agent has `ProjectWorkerReadiness.status == ready` for this Project root; otherwise dispatch falls back to reveal or shows setup copy. |
| Proof named | Proof commands exist or waiver is explicit. |
| Privacy unchanged | Dispatch must not change privacy, credentials, permissions, or external data policy. |

Dirty state policy for v1:

- "Overlapping likely scope" is a deterministic match, not a judgment call: a
  dirty file overlaps when its Project-root-relative path matches an entry in the
  proposal's `likelyFilesOrAreas[]` by exact path, directory-prefix
  (`area/` matches `area/...`), or declared glob. Matching is on normalized,
  root-relative paths.
- Dirty files outside the likely scope are warnings, not automatic blockers.
- Dirty files inside or overlapping likely scope block dispatch until the user
  approves including them as preexisting context or cleans them up.
- When `likelyFilesOrAreas[]` is empty, no overlap can be computed: all dirty files
  are surfaced as warnings (not blockers), and the user must explicitly acknowledge
  the dirty tree before dispatch.
- Allnighter never cleans, resets, stashes, or deletes user changes in this
  phase.

## Queue / Proposal State

The earlier approval-queue concept folds into Project Manager.

The Project Manager owns orientation, proposal state, handoff quality, safety
gates, proof verification, and drift detection for one Project at a time.

Derived state may read:

- git status/log/diff for the Project root;
- phase docs and project docs;
- active worker runs;
- Project-scoped Pending items and queue attempts;
- proof artifacts;
- commit handoff state;
- user approvals/postponements;
- Project Manager chat/proposal history.

Derived queue/proposal state must not become another source of product truth. If
it disagrees with Project, git, or proof truth, Project/git/proof wins.

## UI Contract

Primary left rail:

```text
Projects
  Allnighter        [+]
    Project Manager
    Review thread image specs
    Fix team setup UX
  websitemd.studio  [+]
    Project Manager
    First page POC implementation
  FareWellMarket    [+]
    Project Manager
```

The `+` action is:

```text
New agent in <Project>
```

Selected Project context must be visible before send:

```text
Project name / branch / local
```

Project worker readiness should be visible but quiet:

```text
2 workers ready
Claude needs project authorization
Grok sign-in required
```

If no worker is ready:

```text
No workers are ready for this project yet.

Open Claude Code, Codex, Grok, Gemini, or Antigravity in:
<project folder>

Complete any trust or login prompts, then recheck workers.
```

Buttons:

```text
Open Folder
Recheck Workers
```

Composer behavior:

- default target is the Project Manager for the selected Project;
- route controls may choose Send to team (Code / Design / Copy) or Execute; Chat is the default;
- Enter sends chat, not Build/Execute;
- any mutating route runs against the selected Project root;
- no mutating route is allowed with no Project selected;
- "New work order" creates a Project-scoped proposal/work thread, not a global
  floating thread.

Proposal card minimum:

```text
title
kind
why now
scope
non-goals
risks/blockers
proof expectation
Approve / Edit / Postpone
```

Work order card minimum:

```text
target agent/worker
Project root
base head if available
prompt preview
proof commands or waiver
Reveal / Dispatch
```

Verification card minimum:

```text
return status
proof result
scope finding
docs drift finding
verified / not verified / needs human / waived
recommended next action
```

Do not add a separate "Consult Project Manager" button to v1. The chat is the
consult surface.

## CLI Contract

Initial CLI should be Project-first and boring.

Core Project commands:

```text
alln project list --json
alln project add <path> [--name <name>] --json
alln project show <project-id-or-name> --json
alln project archive <project-id-or-name> --json
alln project threads <project-id-or-name> --json
alln project context <project-id-or-name> --json
alln project pending <project-id-or-name> --json
alln project workers <project-id-or-name> --json
alln project recheck-workers <project-id-or-name> --json
```

Manager commands:

```text
alln project chat <project-id-or-name> [message] --json
alln project propose <project-id-or-name> [--from-thread <thread-id>] --json
alln project proposals <project-id-or-name> --json
alln project approve <proposal-id> --json
alln project edit <proposal-id> --json
alln project postpone <proposal-id> --json
alln project handoff <proposal-id> [--to <worker-or-agent>] --json
alln project dispatch <work-order-id> --json
alln project verify <project-id-or-name> [--work-order <id>] [--return <id>] --json
```

Rules:

- JSON output must include `schemaVersion`, `projectId`, and typed
  `nextActions` where relevant.
- Human output may be concise prose.
- `chat` may return only an answer.
- `propose` returns at most one primary proposal plus optional alternates.
- `project pending` is a Project-filtered view over the same Core Pending store;
  it is not a second Pending store.
- `project workers` reports Project-specific readiness, not only global setup.
- `project recheck-workers` may run only driver-declared safe probes unless the
  user explicitly starts that CLI outside Allnighter.
- `handoff` creates/reveals the work order; `dispatch` invokes a worker.
- `verify` never marks done without a `VerificationRecord`.
- Legacy thread commands may keep accepting `--working-dir` during migration,
  but new public surfaces should prefer `--project`.

Errors and exit codes:

Project commands use the shared error envelope and process exit-code contract from
`CLI_Implementation_Contract.md` (`0` success / `1` operational / `2` usage). Every
code below is registered in the shared error catalog with
`agentAction`/`remedyTier`/`whoCanFix`/doctor text before it can be emitted:

| Code | Class | Meaning |
| --- | --- | --- |
| `PROJECT_NOT_FOUND` | 1 | No Project matches the id/name. |
| `NO_PROJECT_SELECTED` | 2 | A mutating action was attempted with no Project selected. |
| `DUPLICATE_PROJECT_ROOT` | 1 | Add resolves to an existing Project's normalized root; the existing Project is returned. |
| `PROJECT_ROOT_UNAVAILABLE` | 1 | `rootState != available` (missing/permissionDenied); mutating dispatch blocked. |
| `PROJECT_ARCHIVED` | 1 | The Project is archived; unarchive before new runs. |
| `THREAD_UNASSIGNED` | 1 | The thread/Pending item has no Project; assign before mutating dispatch. |
| `WORKER_NOT_READY_IN_PROJECT` | 1 | Target worker's `ProjectWorkerReadiness.status != ready`; falls back to reveal/setup copy. |
| `MANAGER_MODEL_UNAVAILABLE` | 1 | No ready manager model; the Manager turn is `wait` with a readiness blocker. |
| `PROPOSAL_NOT_FOUND` | 1 | No proposal matches the id. |
| `PROPOSAL_NOT_APPROVED` | 1 | Dispatch attempted on an unapproved proposal/work order. |
| `BASE_HEAD_CHANGED` | 1 | Approved `baseGitHead` differs from current head; revalidate. |
| `DIRTY_SCOPE_CONFLICT` | 1 | Dirty files overlap the proposal's likely scope; acknowledge or clean first. |
| `DISPATCH_GATE_FAILED` | 1 | One or more dispatch gates failed; the failing gate(s) are named. |
| `VERIFICATION_REQUIRED` | 1 | A completion claim was advanced to done without a `VerificationRecord`. |

Generated artifacts for Project contracts should be added under the same
`docs/generated/alln/` contract system named by `CLI_Implementation_Contract.md`.

## MCP / Agent-First Contract

External agents such as Hermes/OpenClaw should call Project-scoped tools:

```text
project_list
project_get
project_context
project_workers
project_recheck_workers
project_chat
project_propose
project_proposals
project_handoff
project_dispatch
project_verify
```

Caller, proposer, and approver remain separate:

```text
caller   = who asked Allnighter to consider work
proposer = Project Manager proposal engine
approver = human or explicit policy envelope allowed to sign the work order
```

Rules:

- External agents may be callers.
- External agents do not automatically become approvers.
- Agent-originated proposals should be labeled with caller identity.
- Agent-originated dispatch must satisfy the same approval and gate rules.
- Agent-originated readiness checks may not configure, authorize, or accept
  prompts for a CLI.
- MCP tools project the same Core contracts as CLI; no MCP-only semantics.

## Privacy / Permissions

Project Manager v1 is local-first.

Rules:

- Project context remains on the Mac unless the user dispatches to a configured
  agent/source that sends data elsewhere.
- Dispatch uses the selected agent's existing permission/auth posture.
- Project worker readiness detection observes existing CLI readiness. It does
  not create, approve, or modify vendor trust/auth state.
- Adding Project Manager does not justify new Full Disk Access, Keychain, or
  network permissions.
- Any future privacy, credentials, permission, billing, entitlement, or remote
  relay change routes through the high-risk stop policy before implementation.

## Non-Goals

- No global floating work threads in new surfaces.
- No Project Manager for "all repos at once" in v1.
- No auto-execution of unapproved work.
- No external agent self-approval.
- No queue item as primary Project truth.
- No global Pending queue as durable product truth.
- No auto-configuration or auto-authorization of Claude Code, Codex, Grok,
  Gemini, Antigravity, or any other CLI inside a Project.
- No silent phase-doc rewriting after commits.
- No worker self-attestation as "done."
- No team-run output promoted to execution truth without human approval.
- No iOS-first implementation. iOS remains parked until Mac Project truth works.
- No branch/worktree manager in this phase.
- No Allnighter-managed commits in this phase.
- No terminal viewer in this phase.
- No code editor or diff surface in this phase.
- No GitHub project-board integration in v1.

## Implementation Impact

Core:

- Add `Project`, `ProjectStore`, `ProjectContextPacket`,
  `ProjectWorkerReadiness`, `ProjectManagerTurn`, `ProjectProposal`,
  `WorkOrder`, `WorkReturn`, and `VerificationRecord` models.
- Normalize local root paths and prevent duplicate active Projects.
- Observe git metadata for Project roots.
- Add `projectId` to threads, runs, pending items, proposals, work orders, and
  verification records where they mutate or report Project-scoped truth.
- Migrate Pending items into Project scope and block unassigned Pending from
  drain.
- Migrate existing `workingDir` data into Projects.
- Keep `workingDir` / root snapshots only as historical receipts.
- Add driver-owned, non-mutating Project readiness probes where safe; report
  `unsafeToProbe`/`unknown` instead of guessing readiness.
- Extend `DriverManifest` / `DriverRegistry` with an additive safe
  `projectProbe` declaration and update shipped driver manifests only where a
  non-mutating Project probe is known.
- Add deterministic gate evaluators for dispatch readiness.

ThreadStore:

- New thread creation requires Project context.
- Manager thread is ordinary thread truth with a Project Manager target.
- Mutating send/execute flows resolve root from Project, not ad hoc thread
  state.

Attachments:

- Canonical attachment truth remains in Application Support.
- Project-root mirrors remain delivery cache only.
- Mirror paths derive from the Project root when invocation needs local files.

CLI/MCP:

- Add project-scoped commands/tools before exposing Project Manager queue.
- Preserve legacy compatibility only where needed for migration.
- Generate Project schemas/help from the contract registry.

Mac:

- Add Projects rail/grouping.
- Add `+` per Project for "New agent in <Project>".
- Show selected Project before send.
- Default chat target is Project Manager for selected Project.
- Disable mutating sends when no Project is selected.
- Render proposal/work-order/verification cards from Core state.

iOS:

- No blocking work. Future iOS reads Project snapshots from Mac after Mac is
  done.

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Chat -> work order | Core Project Manager turn router | Every chat needs a proposal. | Chat may answer only; proposal creation is explicit by intent or Manager mode. | "Where are we?" creates no proposal. |
| Proposal -> dispatch | Core gate evaluator | Approved once means always dispatchable. | Dispatch revalidates root, base head, dirty state, worker readiness, and proof. | Change git head after approval; dispatch blocks or asks revalidation. |
| Global setup -> Project readiness | Project worker readiness detector | Installed/authenticated CLI can work in every Project. | Worker readiness is per Project root and driver-probed; global setup is not enough. | Claude installed globally but untrusted in Project root; dispatch blocks with setup copy. |
| Worker return -> done | Verification engine | Worker says done, so done. | Done requires verification or waiver. | Return text says done with no proof; outcome is not verified. |
| Project context -> truth | ProjectStore + source owners | Cached packet becomes authority. | Context packets are receipts; regenerate from git/docs/thread/pending truth. | Stale packet disagrees with git head; current git wins. |
| Manager turn -> truth | ProjectStore + source owners | The manager model's answer is durable Project truth. | Manager turns are model outputs recorded as run truth, not Project truth; Project/git/proof win on conflict. | A Manager answer contradicting the current git head is overridden by git. |
| Pending -> global queue | Pending store + ProjectStore | One queue owns all Projects. | Pending items require `projectId`; global views are aggregates only. | Reorder across two Projects is rejected. |
| External agent -> approver | Approval policy | MCP caller can self-approve. | Caller, proposer, and approver are separate fields. | Agent-originated approve without policy is rejected. |
| Non-git folder -> commit proof | Verification engine | Folder work can be commit-verified. | Non-git Projects cannot claim commit verification. | Verify folder work with no git root; outcome may be proof-only or waived, never commit-verified. |

## Ordered Slices

- [x] PRJ-S00 - Contract packet (DONE 2026-06-18): Core models (`ProjectSpine.swift`),
  Codable round-trip = the JSON schema, root-normalization law (`RootNormalization.swift`),
  proposal state machine, and model-level inference-ban tests (`ProjectSpineTests.swift`).
  No GUI. Green wall. (Public string-date JSON projection + contract-registry artifacts
  land with the CLI in PRJ-S07.)
- [x] PRJ-S01 - ProjectStore (DONE 2026-06-18): add/list/show/archive Projects with atomic local
  persistence, duplicate-root detection, rootState observation, and git metadata
  observation.
- [x] PRJ-S02 - Project context packet (DONE 2026-06-18): generate compact source-labeled packets
  from ProjectStore, git, docs entrypoints, threads, pending, runs, proposals,
  returns, and proof records.
- [x] PRJ-S03 - Thread binding migration (DONE 2026-06-18): add `projectId` to `WorkThread`,
  migrate existing threads from `workingDir` / run root, preserve snapshots, and
  block mutating unassigned threads until assigned.
- [x] PRJ-S04 - Pending binding migration (Core DONE 2026-06-18; alln project pending in S07): add `projectId` to Pending items and
  queue attempts, migrate from thread/run/workingDir where possible, add
  `alln project pending`, and block unassigned Pending from drain.
- [ ] PRJ-S05 - Project worker readiness detection: auto-detect which installed
  CLIs are already usable in this Project root via driver-declared
  non-mutating probes; report only the canonical statuses (`ready`,
  `notInstalled`, `authRequired`, `needsProjectAuthorization`,
  `interactiveRequired`, `unsafeToProbe`, `blocked`, `unknown`); add the
  additive driver-manifest `projectProbe` declaration; no auto-config or
  auto-authorization.
- [ ] PRJ-S06 - Project-scoped send/execute: route worker invocation,
  attachment staging, proof command roots, dirty-file checks, and readiness
  gates through Project root instead of ad hoc `workingDir`.
- [ ] PRJ-S07 - CLI Project foundation: `alln project list/add/show/archive/
  threads/context/pending/workers/recheck-workers` plus JSON fixtures,
  generated schemas, and contract docs.
- [ ] PRJ-S08 - Project Manager chat v1: default Project chat can answer and
  summarize from Project context via the resolved manager model (`managerModelId`
  or strongest ready planner); the Manager call is recorded as run truth; no ready
  model yields a `wait` turn; it does not auto-create work.
- [ ] PRJ-S09 - Proposal engine v1: "what next?" returns one bounded proposal or
  one visible blocker, with source-labeled rationale and no dispatch.
- [ ] PRJ-S10 - Approval/edit/postpone + WorkOrder: proposal edits produce an
  approved work order with base head, scope, non-goals, proof commands/waiver,
  target agent, and expected return format.
- [ ] PRJ-S11 - Handoff/reveal/dispatch: reveal exact handoff or dispatch to a
  healthy worker after gate revalidation. Capture run/return linkage.
- [ ] PRJ-S12 - Return review and verification: create `WorkReturn` and
  `VerificationRecord`; worker claims never mark done without verification or
  waiver.
- [ ] PRJ-S13 - MCP Project tools: external agents can list Projects, get
  context, read/recheck Project worker readiness, chat, propose, hand off,
  dispatch with approval, and verify. They cannot self-approve.
- [ ] PRJ-S14 - Mac Projects rail: project grouping, selected Project context,
  `New agent in <Project>`, Project Manager row/thread, proposal/work-order/
  verification cards, Project worker readiness status, no global floating sends.
- [ ] PRJ-S15 - GUI proof seal + dogfood loop: project switching, Project
  Manager answer, what-next proposal, approve/edit/postpone, reveal/dispatch,
  return review, worker-ready/none-ready states, and mutating send blocked
  without Project.

Backend slices PRJ-S00 through PRJ-S13 come first. GUI slices PRJ-S14 and
PRJ-S15 wait for the Core/CLI contract unless a throwaway mock is explicitly
waived as non-authoritative.

## Works Tests

Project Core:

```text
Create two temporary git repos and one non-git folder.
Add all three as Projects.
Expected:
- each has one stable Project id;
- duplicate add of the same normalized root returns the existing Project;
- git Projects report observed branch/head/remote when available;
- folder Project is allowed but reports kind = folder;
- missing root changes rootState and blocks mutating dispatch.
```

Project worker readiness:

```text
Add a new Project root where Codex is already usable, Claude Code requires a
folder trust prompt, and Grok is not authenticated.
Run project worker readiness detection.
Expected:
- Codex reports ready for this Project;
- Claude Code reports needsProjectAuthorization or interactiveRequired;
- Grok reports authRequired;
- no vendor config, trust prompt, login, or authorization file is changed;
- drivers with no declared safe projectProbe report unsafeToProbe or unknown;
- Project is usable because at least one worker is ready;
- dispatch to Claude Code blocks with setup copy until the user authorizes it
  outside Allnighter and rechecks.
- explicit recheck, rootState change, driver manifest change, or observed
  auth/trust failure invalidates cached readiness.
```

Project context packet:

```text
Create a Project with one docs entrypoint, one recent thread, one pending item,
one open proposal, and one failed proof result.
Run project context.
Expected:
- packet is source-labeled and compact;
- failed proof is visible;
- dirty/git state is visible;
- worker readiness summary is visible;
- packet id can be stored as a receipt;
- regenerating after a commit reports the new git head.
```

Thread migration:

```text
Given legacy threads with workingDir values in two different repos,
run migration.
Expected:
- Projects are created or reused for each root;
- threads receive projectId;
- localRootPathSnapshot preserves the old path;
- unresolvable threads cannot mutating-dispatch until assigned.
```

Project-scoped execute:

```text
Create Project A and Project B.
Start a thread in Project A.
Attempt mutating send/execute.
Expected:
- worker cwd / proof cwd / attachment mirror derive from Project A root;
- dirty files in Project B do not block Project A work;
- dirty files overlapping Project A proposal scope block until acknowledged;
- no root means no mutating dispatch.
```

Project-scoped Pending:

```text
Create Project A and Project B.
Add two Pending items to Project A and one Pending item to Project B.
Run global Pending list and Project-specific Pending list.
Expected:
- every item has projectId;
- global list groups by Project;
- Project A list excludes Project B;
- reorder within Project A works;
- reorder across Project A and Project B is rejected;
- missing Project A root blocks only Project A drain.
```

Project Manager chat:

```text
Open Project A and send: "Where are we?"
Expected:
- response is scoped to Project A docs/git/thread truth;
- response names important uncertainty;
- no work order is created unless the user asks or approves;
- nextActions are typed.
```

Project Manager proposal:

```text
Open Project A and send: "What should we do next?"
Expected:
- exactly one primary proposal is returned, or one visible blocker;
- proposal includes kind, whyNow, scope, non-goals, risks, proof expectation,
  and approve/edit/postpone actions;
- proposal does not dispatch until approved.
```

Project Manager execution:

```text
Open Project A with no ready manager model and send a chat message.
Expected:
- the turn is mode = wait with a sourced manager-model readiness blocker;
- no answer is fabricated.
Set a ready manager model and resend.
Expected:
- a typed turn is produced by a recorded manager-model run (id/model/transcript);
- the answer is scoped to Project A truth.
```

Proof execution:

```text
Approve and dispatch a work order whose proofCommands include one passing command
and one command that exits non-zero (and one that exceeds its timeout).
Run verification.
Expected:
- proofResults capture each command's exit code, output tail, and duration;
- the timed-out command is recorded as a timeout, not a pass;
- outcome is notVerified or needsHuman, never verified;
- no git mutation (commit/reset/checkout) and no working-tree cleaning occurred.
```

Dispatch gate:

```text
Approve a proposal at git head H1.
Create a new commit, dirty overlapping file, or target-worker readiness block
before dispatch.
Attempt dispatch.
Expected:
- dispatch blocks or asks for explicit revalidation;
- gate output names the changed head, dirty file, or worker readiness blocker;
- no worker starts until gate result is accepted.
```

Return review:

```text
Create a return whose transcript says "done" but no proof command ran.
Run verification.
Expected:
- outcome is notVerified or needsHuman;
- missing proof is named;
- proposal/work order is not marked done.
```

CLI wall:

```text
alln project add <tmp-repo> --json
alln project workers <project> --json
alln project recheck-workers <project> --json
alln project context <project> --json
alln project chat <project> "Where are we?" --json
alln project propose <project> --json
alln project handoff <proposal-id> --json
```

Green wall:

```text
swift test --package-path Packages/AllnighterCore
bash scripts/check.sh
```

Dogfood loop:

```text
Add/open the Allnighter repo as a Project.
Ask: "What should we do next to make the Project Manager dogfoodable?"
Expected:
- Project Manager answers from current docs/git/thread truth;
- it returns one bounded proposal;
- user can approve/edit/postpone;
- approved work order can be revealed or dispatched;
- return review refuses "done" without proof or waiver;
- Project Manager recommends the next move.
```

## Done When

- Projects are first-class durable truth.
- New threads and mutating sends are Project-scoped.
- Existing `workingDir` threads are migrated or explicitly blocked from mutate.
- Project context packets are generated from source-labeled truth.
- Project worker readiness is auto-detected with safe probes; no auto-config or
  auto-authorization occurs.
- Pending items and queue attempts are Project-scoped; global Pending is an
  aggregate view only.
- Project Manager chat is the default chat for a selected Project.
- The Project Manager can answer without producing work.
- The Project Manager can propose one bounded next move from Project git/docs/
  thread truth.
- The user can approve, edit, or postpone proposals.
- Approved items store base commit/head when available and re-run gates at
  dispatch time.
- Handoff/reveal works before direct dispatch.
- Direct dispatch targets the selected Project root and selected worker/agent.
- Direct dispatch requires target worker readiness in the selected Project.
- Worker returns are captured.
- Worker completion claims are verified before done.
- Project Manager turns are produced by a resolved manager model and recorded as
  run truth; with no ready model the turn is `wait`, never a fabricated answer.
- Verification runs declared proof commands as bounded subprocesses at the Project
  root and never claims `verified` on failure, timeout, or missing proof.
- Fanout outputs are synthesized for human judgment and are not silently
  promoted to execution truth.
- External agents can call Project Manager tools without approval authority.
- The dogfood loop can run on the Allnighter repo.

## Closed Decisions

- Non-git folder Projects are allowed for chat, team runs, reveal, and manual
  handoff. Mutating dispatch requires explicit proof waiver and cannot be
  commit-verified.
- The Project Manager thread is pinned/reserved in v1 and recreated if missing.
- Missing/moved roots set `rootState` and block mutating dispatch until repaired.
- Multiple local roots per Project are out of scope for v1.
- New Project commands prefer `alln project ...`; legacy thread commands may
  infer Project from thread id only when unambiguous.
- Project worker readiness detection is allowed; automatic CLI configuration,
  folder authorization, trust-prompt acceptance, and login are out of scope.
- `alln project edit <proposal-id>` accepts a JSON patch (stdin or `--patch`) for
  deterministic agent/CLI editing. An interactive `$EDITOR` is a Mac-GUI affordance
  only, never the agent path.
- Dispatch to Cursor is reveal-only in v1; CLI agents (Claude Code, Codex, Grok,
  Gemini) support direct subprocess dispatch.
- Project Manager turns are produced by a resolved manager model
  (`Project.managerModelId` or strongest ready planner), recorded as run truth; no
  ready model yields a `wait` turn.
- Verification executes the Work Order's declared proof commands as bounded
  subprocesses at the Project root; it never mutates git or cleans the tree.

## Open Questions

- What is the smallest useful stale-doc detector for PRJ-S02 without turning it
  into broad semantic search?
- Which proof commands should ProjectStore learn automatically from common repo
  files versus requiring user/project docs?
- Should the manager model default to a specific planner tier, and may a Project
  pin a cheaper manager model for routine chat versus proposals?

## Next Items (deferred; do not block this phase)

- **Assignable floor manager / default PM.** Add a UI + setting to choose the
  default Project Manager you talk to. v1: one global go-to PM for all of Allnighter
  (a single default `managerModelId` + persona/skill). Later: per-Project override
  (the `Project.managerModelId` field already exists for this). The team-level
  Team Lead already exists; this is specifically *who you talk to by default*. This
  is additive and does not affect the locked Chat/Delegate/Execute model.
