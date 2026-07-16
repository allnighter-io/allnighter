# Unified Run Model — Chat, Execute, and Teams as One

Status: **In progress — core + CLI/MCP shipped; GUI proof pending; Default Team override packet routed**
surface, the work-order/proposal loop, the three-mode composer, and the user-facing
execution lane. This is not a refinement of those; it replaces them.
Owner: AllnighterCore + Mac app + CLI/MCP
Updated: 2026-06-21

## Why this doc

First dogfood on the Allnighter repo failed and exposed that we over-built:

1. We invented a **"Project Manager"** as a separate surface (its own view, sidebar
   row, composer, service, cards, stores, CLI/MCP verbs). It is not a thing. "Where
   are we / what's next" is just **chat**, answered by an agent that can see the repo.
2. Chat/PM ran in a **scratch dir with a hand-built ~10-line context packet** — no
   filesystem access. The model was blind and answered "I don't have ground truth."
3. We added **gates** — Chat vs Execute modes, propose → approve → dispatch → verify,
   an execution lane the user clicks through. Cursor/Claude/Codex never ask "do you
   want to execute?" A gate between "I see a tiny bug" and "fix it" sends users back
   to their CLI in seconds.

The bar is Cursor/Claude/Codex: open a repo, chat, the agent reads and writes as the
message implies. Allnighter's value is not ceremony on top — it's the CLIs you already
pay for on one bench, in your repo, with reusable presets.

## The model — one primitive

```text
A run = your message + (optional preset) + a worker selection, executed in the repo root.
```

There is no "Chat mode" and no "Execute mode." There is a worker and an optional
preset. The agent runs in the repo with full access and does what the message asks —
answer, explain, fix, build, run. Read vs write is the agent's call, not a user toggle.

### `RunRecord` is the only durable primitive

Delete `ProjectManagerTurn`, `ProjectProposal`, `WorkOrder`, `WorkReturn`, and
`VerificationRecord`. Replace them with one durable record — this is the **existing
`TeamRun` substrate, trimmed**, not a new system:

```text
RunRecord
  id
  projectId / repoRoot        (canonical normalized root = the cwd for every worker)
  message                     (the user's prompt)
  presetId?                   (nil ⇒ the Default Team)
  shape                       (answer | execution — derived from the preset)
  writePolicy                 (readOnly | mutating)
  workers[]                   (execution = exactly 1; answer = N)
    driverId, modelId, effort, spawn/invocation, status, output, transcriptRef
  artifacts[]                 (diff refs, proof output, files touched)
  status                      (queued | running | done | failed | cancelled)
  createdAt / finishedAt
```

A default-chat turn is just a one-worker `RunRecord`. The answer board is an N-worker
`RunRecord`. One representation, everywhere (`TeamRunJSON` covers both).

### One recipe noun: `TeamPreset` (UI: "Team")

A worker is a prompt + a worker selection. A **`TeamPreset`** is the saved recipe for a
run. There is no competing "Preset" noun in code — the recipe is `TeamPreset`, the run
instance is `RunRecord`. "Team" is the UI word. Two shapes, by intent:

| Shape | Workers | Direction | Writes repo | Use |
| --- | --- | --- | --- | --- |
| **Answer team** | many | parallel | **no — mechanically read-only** | breadth: N models answer the same prompt → a board to compare & pick. |
| **Execution team** | exactly one | single agent | yes (mutating) | depth/discipline: one prompt + one model runs in the repo and makes the change. |

When a preset's shape is **execution** (the existing **Mutating team** flag), the
model + editor + resolver **enforce exactly one worker** — the lead + N-worker
machinery disappears. The single worker is the source; the `ExecutionTeamSourceGate`
"single CLI" rule is satisfied by construction, with no source-resolution UI.

### "Model" really means a worker selection

Core cannot run "a model." A worker selection is **driver (CLI/source) + model label +
effort + spawn/invocation config**. Wherever this doc says "model," read "worker
selection." The Default Team stores a worker selection, not a bare model id.

### Default Team

The one genuinely missing feature: the user picks their **go-to worker** — and it needs
no special case, because default chat is **just a Default Team**:

- A team of one (the user's go-to driver + model).
- Carries an optional preset prompt the user customizes, **or leaves blank**.
- Mutating-allowed (talk *or* build — same object as any execution team).

Default chat, an execution team, and an answer team are the **same object** with
different settings. There is **no special-case chat code**: default chat = run the
Default Team (message + its preset + its worker) in the project root. The Default Team
appears in the same picker as every other team.

Default Team editing has one special catalog rule: the bundled `default_chat`
team is an immutable seed, and the user's active Default Team is an optional
same-id override on disk. There is still only one effective `default_chat` in
lists, pickers, CLI, MCP, and run resolution. Restore deletes the override and
reveals the seed. The implementation packet is `Default_Team_Override.md`.

### Repo-root execution — kill the blind paths

Every project-scoped run spawns with `cwd = canonical repo root`. Delete all scratch-dir
and thin-packet construction from chat/PM/default paths (`ensuredProbeScratchPath` for
normal runs, `ProjectContextPacket`/`ThreadContextPacket` as a source of truth, the
packet builder). Neutral scratch survives **only** for setup probes / doctor — never for
a repo-aware run. A context packet, if it survives at all, is a hint the agent may
ignore; the agent reads the real files.

## Safety — the honest version

The simplification does **not** make safety free. Two real guarantees must hold
mechanically, and neither is user-facing ceremony.

1. **Answer runs are read-only by mechanism, not by prompt.** Telling a model "don't
   write" is not safety. An answer team must be unable to mutate the tree. Candidate
   mechanisms, decided per driver: a driver's own read-only/sandbox flag where it
   exists; otherwise run answer workers in an **ephemeral git worktree or copy** so any
   write is discarded; otherwise exclude drivers that cannot be made non-mutating from
   answer teams. **Open implementation decision — until it ships, we do not claim
   answer teams are safe.**

   Confirmed headless read-only mechanisms (2026-07-16): `claude_code`
   `--permission-mode plan`; `codex` `--sandbox read-only --ask-for-approval never`.
   `cursor_agent` headless documents full write+shell access (no plan enforcement);
   `grok`/`antigravity`/`opencode` expose no read-only/plan flag. (Salvaged from the
   removed relay `--pm-read-only` toggle — see `Relay_ReadOnly_Removal.md`; that
   mechanism was the wrong home since the relay is sequential-by-construction, not
   concurrent answer-team fan-out.)
2. **At most one mutating run per repo root.** Default chat can mutate, so two chats in
   one repo = two writers = corruption. A minimal internal **`RunWriteLock` keyed by the
   canonical repo root**: read/answer runs never take it; a mutating run takes it; a
   second mutating run on the same root is refused with one honest line ("an agent is
   already editing this repo — wait or stop it"), not an approval gate, not a "lane
   busy" ceremony, no queue UI. The lock is invisible until a genuine collision.

No approval gates. No second permission layer — Allnighter inherits each CLI's own
permission/diff/undo model and adds none of its own. If the message implies a write, the
one agent writes.

## The Execution Playbook as a built-in preset

`docs/operations/Execution-Playbook.md` is a sophisticated prompt that makes a raw agent
work like a disciplined senior engineer (slice → narrow edits → proof → deslop → audit →
commit). Ship it as the **built-in default execution preset** — editable,
bring-your-own-`AGENTS.md`, clearable for raw mode. A CLI agent is already an agentic
loop, so **one worker + a rich preset does the whole disciplined sequence itself, in
order** — no multiple agents needed for multi-step execution.

The preset is **behavior guidance only**. The app owns run mechanics: status, cwd, the
write lock, transcript capture, artifact/diff paths. A preset never owns durable run
semantics.

## Crafts demoted to tags

`Code / Design / Copy / Signal` are no longer scheduler concepts, postures, or lanes.
They survive — if at all — as **preset tags / filters** for organizing answer-team
presets. The Default/execution path never forces a craft choice. Remove `TeamPosture`
and lane-driven codepaths from the product surface (internal/derived only, or gone).

## CLI / MCP — collapse brutally

One run entrypoint. Replace `project chat`, `project propose`, `project approve`,
`project edit`, `project postpone`, `project handoff`, `project dispatch`,
`project verify` with **one** verb (`alln run` / MCP `team.run`): message + optional
preset + worker, against a project root; answer shape returns the board, execution shape
returns the run + diff/proof. No deprecated commands, no compatibility readers, no hidden
aliases. `project add/list/show/archive/threads/pending/context/workers/recheck-workers`
survive only as far as they support repo binding + readiness; everything that carried the
propose→dispatch ceremony is deleted. Regenerate all `docs/generated/alln/*` after Core
changes.

## Deletion manifest (without remainder)

No stubs, no shims, no "for compatibility," no aliases. Target end-state:

- **Mac app:** delete `ProjectManagerView.swift`, `ProjectManagerViewModel.swift`,
  `ProjectManagerCards.swift`, `ProjectManagerCardsSample.swift`. Remove the sidebar
  "Project Manager" row, `onOpenManager`, the `managerProject` mainPane branch, the
  "What's next?" button, and the `pm-cards` / `pm-live` fixtures. Collapse
  `RoutingComposer`: delete `ComposeMode` (chat/sendToTeam/exec), the ⌘1/⌘2/⌘3 mode
  pills, `defaultMode`, `ComposeRoutingDefaults`, and all mode branching. Composer
  becomes message + (optional team) + worker; default send runs the Default Team.
- **Engine:** delete `ProjectManagerService.swift`, `ProjectManagerTurnStore.swift`,
  `ProjectProposalStore.swift`, `ProjectWorkOrderStore.swift`, `WorkReturnStore.swift`,
  `VerificationStore.swift`, `ProjectVerificationService.swift`,
  `ProjectDispatchService.swift`, `ProjectContextPacketBuilder.swift`,
  `ProjectWorkerReadinessStore` only if readiness drops the project path, `ExecutionLane`
  + `ExecutionLaneRegistry`, the heavy `ProjectMutatingDispatchEvaluator`. Make
  `WorkerChatCoordinator` delegate to the single-worker repo-root run path (or delete it).
- **Core:** delete `ProjectManagerTurn`, `ProjectProposal`, `WorkOrder`, `WorkReturn`,
  `VerificationRecord`, `ProofResult`-as-gate, `WorkOrderBuilder`, the `Project*JSON`
  projections tied to propose/approve/dispatch/verify, `ProjectNextAction` read-kinds
  added for the loop, `TeamPosture`, `EXECUTION_LANE_BUSY` + the `PROJECT_*` /
  `PROPOSAL_*` / `DISPATCH_*` / `BASE_HEAD_CHANGED` / `DIRTY_*` error codes that only
  served the ceremony. Keep the minimal `Project` (repo root binding) and `TeamRun` →
  `RunRecord`.
- **CLI/MCP:** delete `runPropose/runApprove/runEdit/runPostpone/runHandoff/runDispatch/
  runVerify` in `ProjectCLI.swift` and the matching `MCPProjectHandlers` paths +
  `MCPToolSpec`s; remove their `OutputSchema` cases and command specs.
- **Pending:** delete the execution-lane / mutating-serialization special cases; mutating
  pending kinds collapse to ordinary pending (or are removed).
- **Tests/fixtures:** delete `ProjectManagerServiceTests`, `ProjectDispatchServiceTests`,
  `ProjectVerificationServiceTests`, `WorkOrderBuilderTests`, and every test asserting the
  three modes / PM flow / lane-busy / proposal stores / packet builder. Delete persisted
  fixtures encoding old shapes.

## Build order — deletion-first, always runnable

Each slice leaves the product building and runnable, with no dead paths:

1. **Remove the PM surface + stores + CLI/MCP project ceremony verbs + their tests.**
2. **Introduce `RunRecord`** (trim `TeamRun`), force **repo-root cwd** for every run,
   add the **`RunWriteLock`**.
3. **Collapse the composer + send paths** to message + (optional team) + worker; delete
   the mode state machine; unify chat into one-worker runs.
4. **Simplify `TeamPreset`** to the two shapes; enforce the **mutating → one-worker
   collapse**; demote crafts to tags; remove postures/gates as user concepts.
5. **Wire the Default Team** (go-to worker + optional preset) and **ship the Execution
   Playbook as the default execution preset**.
6. **Re-add the answer board** on top of the same run primitive.
7. **Sweep docs / AGENTS.md / contracts / generated**; run the green wall.

## Closeout proof

- `swift test --package-path Packages/AllnighterCore` + `bash scripts/check.sh` green.
- GUI Visual Proof Gate green for surviving surfaces; new captures for the collapsed
  composer + default-team chat.
- **Banned-term sweep** over active code + docs (archive exempt) returns nothing:
  `Project Manager` (except colloquial "the chat that knows the repo"), `propose`,
  `approve`, `dispatch`, `verify`, `Execute mode`, `execution lane`, `WorkOrder`,
  `ProjectProposal`, `VerificationRecord`, and the retired JSON contract names.

## Data reset (zero users)

There are no users, so there is no migration. Delete old persisted PM/proposal/
work-order formats and fixtures outright. It is acceptable for "chat" turns to become
ordinary one-worker runs. Provide at most a one-time local wipe script for your own
dogfood state; write no migration readers.

## Non-goals / inference bans

| Ban | Why |
| --- | --- |
| No gate between intent and action. | If the user asks an in-repo agent to change something, it changes it. We never insert an approval step for what was already asked. |
| No second permission layer. | Allnighter inherits each CLI's own permission/diff/undo. It adds none. |
| No agent runs blind. | Every run's cwd is the repo root; the agent reads real files, not a summary. |
| No parallel writers; answer teams never write. | Read-only is mechanical; at most one mutating run per root (the write lock). |
| No "Project Manager" as a surface. | It was chat answering a planning question. |
| No Chat/Execute mode, no execution-lane ceremony, no propose→dispatch→verify clicks. | Friction that sends users back to Cursor. |
| No aliases / shims / dual paths. | One model, fully replaced. |

## Future / parked

- **Multi-step chains** (different worker per step — implement with Codex, audit with
  Claude): a clean later extension — an execution preset that is an **ordered list of
  single-executor steps**, run one after another. Not v1; one worker + a rich preset
  covers ~95%.
- **iOS** stays parked and must not re-introduce the deleted surfaces, modes, or gates
  when it wakes.

## Done when

- No "Project Manager" surface, service, stores, CLI/MCP verbs, or tests remain.
- A run is `message + optional preset + worker`, executed in the repo root, recorded as
  one `RunRecord` (`TeamRunJSON`).
- "Teams" are presets: **answer** (many, parallel, mechanically read-only, → board) or
  **execution** (one worker, may write, under the write lock).
- The Default Team carries the user's go-to worker + an optional editable preset; default
  chat runs it with no special-case code.
- The Execution Playbook ships as the built-in default execution preset.
- No approval gates, no Execute mode, no execution-lane ceremony, no blind runs.
- Banned-term sweep is clean; green wall + GUI gate pass.
