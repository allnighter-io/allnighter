# Project Spine And Project Manager

Status: Code red specification - blocks Project Manager queue/autopropose work
Owner: AllnighterCore + Mac app + CLI/MCP contracts + agent-first clients
Updated: 2026-06-17

## Founder Intent

Raw request:

```text
Allnighter is useless without the floor. When I start a new agent, it should be
inside a Project: the local folder / git repo, like Cursor. Regular chat should
be chat with the Project Manager for that Project. It does not always need to
become a work order. The Project Manager should know what project it is managing,
what is current, what is safe, and what to propose next.
```

Product value:

```text
Projects give workers a floor. The Project Manager keeps that floor moving.
```

Trusted workflow slice:

```text
user opens/adds Project -> Project binds to local root / git repo ->
new agent/chat belongs to that Project -> Project Manager answers or proposes
bounded work -> user approves/edits/postpones work orders ->
approved work runs inside the Project root -> proof/commit returns to the
Project thread
```

## Decision

Public noun: **Project**.

Allnighter may use "workspace" internally if code needs a local filesystem term,
but the product surface says Project.

The Project is the durable container above threads, runs, pending items,
attachments, approvals, and Project Manager proposals. A Project usually maps to
one local git repo, but v1 should allow a non-git folder too.

The Project Manager is not a new lane, button, or layer above chat. The default
chat in a Project is a chat with that Project's Manager.

```text
Project
  -> Project Manager chat
  -> work threads
  -> runs
  -> pending items
  -> approved work orders
  -> proof/commit history
```

The Project Manager may simply answer a question. A chat message only becomes a
work order when the user asks for work or approves a proposed work order.

## Why This Is Code Red

Without Projects, Allnighter cannot reliably answer:

- which repo/folder a worker is allowed to touch;
- which docs and commits define current truth;
- which threads belong together;
- where attachments should stage for invocation;
- where proof commands should run;
- whether a proposed next item is safe;
- which dirty files are relevant vs unrelated;
- what "new agent in Allnighter" actually means.

Threads without Projects become floating conversations. Project Manager without
Projects becomes generic PM chat. Execute without Projects becomes unsafe.

## Product Model

### Project

Project is the product-owned representation of a local work floor.

Minimum model:

```text
Project
  id
  displayName
  localRootPath
  kind: gitRepo | folder
  gitRemoteURL?
  gitBranch?
  createdAt
  lastOpenedAt
  pinned
  archived
  docsEntrypoints[]
  defaultBuildTeamId?
  defaultDesignTeamId?
  defaultCopyTeamId?
  managerThreadId?
```

Rules:

- `localRootPath` is required for mutating Build/Execute work.
- Git metadata is observed, not invented.
- The same normalized local root must not create duplicate active Projects.
- A Project can be archived without deleting local files.
- Project archive hides the Project from the active rail; it does not delete
  threads, runs, attachments, or commits.

### Thread Binding

Every durable thread should belong to one Project once this phase lands.

```text
WorkThread
  projectId
  localRootPathSnapshot?
```

`localRootPathSnapshot` is a historical receipt. It is not the owner of current
project scope.

Rules:

- New threads require `projectId`.
- Existing threads migrate from `workingDir` / run root when possible.
- Threads with no reliable root migrate to an explicit "Unassigned" Project
  or remain blocked from mutating Execute until assigned.
- A thread may reference runs and pending items, but Project remains the parent
  context.

### Project Manager

The Project Manager is the default agent identity inside a Project.

It can:

- answer normal chat questions;
- summarize the Project state;
- find stale docs;
- propose the next bounded move;
- propose fanout when a spec is fuzzy;
- synthesize fanout for human judgment;
- verify a worker completion claim;
- prepare a handoff prompt;
- route approved work to Build, Design, Copy, GUI, Audit, Docs, Fanout, or
  Execute lanes.

It must not:

- auto-execute unapproved work;
- mark worker claims done without proof + commit or waiver;
- silently rewrite phase docs;
- treat fanout discovery as machine proof;
- self-approve because an external agent asked.

## Chat Law

Regular chat in a Project is Project Manager chat.

This is intentionally boring:

```text
User: "Where are we on image attachments?"
Project Manager: answers from project docs/git/thread truth.

User: "What should we do next?"
Project Manager: proposes one bounded next move.

User: "Run it."
Project Manager: creates or uses an approved work order, then dispatches only
if gates are green.
```

No new top-level "Consult Project Manager" surface is needed. The Project
Manager is present because the user is inside a Project.

Chat does not have to produce a proposal. The Project Manager can just answer.

## UI Contract

Primary left rail:

```text
Projects
  Allnighter        [+]
    Project Manager
    Review thread image specs
    Fix team setup UX
  websitemd.studio  [+]
    First page POC implementation
  FareWellDoulaPage [+]
```

The `+` action is:

```text
New agent in <Project>
```

The selected Project should be visible in the main surface before the user sends
work. A minimal top context bar can show:

```text
Project name / branch / local
```

Composer behavior:

- default target is the Project Manager for the selected Project;
- route controls may still choose Build / Design / Copy / Fan out / Execute;
- any mutating route runs against the selected Project root;
- no mutating route is allowed with no Project selected;
- "New work order" creates a Project-scoped thread or proposal, not a global
  floating thread.

Do not add a separate "Consult Project Manager" button to v1. The chat is the
consult surface.

## CLI Contract

Initial CLI should be project-first and boring:

```text
alln project list --json
alln project add <path> [--name <name>] --json
alln project show <project-id-or-name> --json
alln project archive <project-id-or-name> --json
alln project threads <project-id-or-name> --json
alln project chat <project-id-or-name> [message] --json
alln project propose <project-id-or-name> --json
```

Legacy thread commands may keep accepting `--working-dir` during migration, but
new public surfaces should prefer `--project`.

## MCP / Agent-First Contract

External agents such as Hermes/OpenClaw should call project-scoped tools:

```text
project_list
project_get
project_chat
project_propose
project_verify
project_handoff
```

Caller, proposer, and approver remain separate:

```text
caller   = who asked Allnighter to consider work
proposer = Project Manager proposal engine
approver = human or explicit policy envelope allowed to sign the work order
```

External agents may be callers. They do not automatically become approvers.

## Queue / Proposal Law

The earlier approval-queue concept folds into Project Manager.

The Project Manager owns orientation, queue state, handoff quality, safety gates,
proof verification, and drift detection for one Project at a time.

Queue state is derived from:

- git status/log/diff for the Project root;
- phase docs and project docs;
- active worker runs;
- proof artifacts;
- commit handoff state;
- user approvals/postponements;
- Project Manager chat/proposal history.

Queue state must not become another source of product truth. If it disagrees
with git or proof, git/proof wins.

## Readiness Moves

The Project Manager does not only consume execution-ready work. It manufactures
readiness by proposing the cheapest safe move that advances an item:

```text
vague intent -> explored -> spec-ready -> execution-ready -> executing ->
verified -> done
```

Legal proposal kinds:

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

Fanout is discovery, not proof. Its output is synthesized so the human can judge
agreement, contradiction, assumptions, and candidate work orders.

## Non-Goals

- No global floating work threads in new surfaces.
- No Project Manager for "all repos at once" in v1.
- No auto-execution of unapproved work.
- No external agent self-approval.
- No queue item as primary project truth.
- No silent phase-doc rewriting after commits.
- No worker self-attestation as "done."
- No fanout output promoted to execution truth without human approval.
- No iOS-first implementation. iOS remains parked until Mac Project truth works.
- No branch/worktree manager in this phase.
- No GitHub project-board integration in v1.

## Implementation Impact

Core:

- Add `Project` model and `ProjectStore`.
- Normalize local root paths and prevent duplicate active Projects.
- Observe git metadata for Project roots.
- Add `projectId` to threads, runs, pending items, and approval/proposal records
  where they mutate or report Project-scoped truth.
- Migrate existing `workingDir` data into Projects.
- Keep `workingDir` / root snapshots only as historical receipts.

ThreadStore:

- New thread creation requires Project context.
- Manager thread is ordinary thread truth with a Project Manager target.
- Mutating send/execute flows resolve root from Project, not ad hoc thread state.

Attachments:

- Canonical attachment truth remains in Application Support.
- Project-root mirrors remain delivery cache only.
- Mirror paths derive from the Project root when invocation needs local files.

CLI/MCP:

- Add project-scoped commands/tools before exposing Project Manager queue.
- Preserve legacy compatibility only where needed for migration.

Mac:

- Add Projects rail/grouping.
- Add `+` per Project for "New agent in <Project>".
- Show selected Project before send.
- Default chat target is Project Manager for selected Project.
- Disable mutating sends when no Project is selected.

iOS:

- No blocking work. Future iOS reads Project snapshots from Mac after Mac is done.

## Ordered Slices

- [ ] PRJ-S00 - Contract packet: `Project` schema, root normalization,
  duplicate-root law, Project/thread/run/pending/proposal relationships, and
  migration rules. No GUI.
- [ ] PRJ-S01 - ProjectStore: add/list/show/archive Projects with atomic local
  persistence and git metadata observation.
- [ ] PRJ-S02 - Thread binding migration: add `projectId` to `WorkThread`, migrate
  existing threads from `workingDir` / run root, and block mutating unassigned
  threads until assigned.
- [ ] PRJ-S03 - Project-scoped send/execute: route worker invocation,
  attachment staging, proof command roots, and dirty-file checks through Project
  root instead of ad hoc `workingDir`.
- [ ] PRJ-S04 - CLI project surface: `alln project list/add/show/archive/threads`
  plus JSON fixtures and generated contract docs.
- [ ] PRJ-S05 - Project Manager chat v1: default Project chat can answer and
  summarize from project docs/git/thread truth; it does not auto-create work.
- [ ] PRJ-S06 - Project Manager proposals: verifier-first proposal engine for
  one Project, with approve/edit/postpone records and dispatch-time revalidation.
- [ ] PRJ-S07 - MCP project tools: external agents can list Projects, chat with
  Project Manager, request proposals/status/handoffs, and cannot self-approve.
- [ ] PRJ-S08 - Mac Projects rail: project grouping, selected Project context,
  `New agent in <Project>`, Project Manager row/thread, no global floating sends.
- [ ] PRJ-S09 - GUI proof seal: project switching, new agent in Project,
  mutating send blocked without Project, and Project Manager chat fixture.

Backend slices PRJ-S00 through PRJ-S07 come first. GUI slices PRJ-S08 and
PRJ-S09 wait for the Core/CLI contract.

## Works Test

Project Core:

```text
Create two temporary git repos and one non-git folder.
Add all three as Projects.
Expected:
- each has one stable Project id;
- duplicate add of the same normalized root returns the existing Project;
- git Projects report observed branch/remote when available;
- folder Project is allowed but reports kind = folder.
```

Thread migration:

```text
Given legacy threads with workingDir values in two different repos,
run migration.
Expected:
- Projects are created or reused for each root;
- threads receive projectId;
- localRootPathSnapshot preserves the old path;
- unresolvable threads do not allow mutating Execute until assigned.
```

Project-scoped execute:

```text
Create Project A and Project B.
Start a thread in Project A.
Attempt mutating send/execute.
Expected:
- worker cwd / proof cwd / attachment mirror derive from Project A root;
- dirty files in Project B do not block Project A work;
- dirty files in Project A are reported before dispatch.
```

Project Manager chat:

```text
Open Project A and send: "Where are we?"
Expected:
- response is scoped to Project A docs/git/thread truth;
- no work order is created unless the user asks or approves;
- "What next?" returns one proposal with approve/edit/postpone, not execution.
```

Green wall:

```text
swift test --package-path Packages/AllnighterCore
bash scripts/check.sh
```

## Done When

- Projects are first-class durable truth.
- New threads and mutating sends are Project-scoped.
- Existing `workingDir` threads are migrated or explicitly blocked from mutate.
- Project Manager chat is the default chat for a selected Project.
- The Project Manager can answer without producing work.
- The Project Manager can propose one bounded next move from Project git/docs
  truth.
- The user can approve, edit, or postpone proposals.
- Approved items store base commit and re-run gates at dispatch time.
- Worker completion claims are verified before done.
- Fanout outputs are synthesized for human judgment and are not silently
  promoted to execution truth.
- External agents can call Project Manager tools without approval authority.

## Open Questions

- Should non-git folder Projects support Execute, or only chat/fanout until a git
  root exists?
- Should the Project Manager thread be pinned and undeletable, or just recreated
  if missing?
- How should a Project move/rename on disk be detected and repaired?
- Should a Project have multiple local roots later, or is that a separate future
  Project group concept?
- Should `alln thread send` require `--project` after migration, or infer from
  thread id forever?
