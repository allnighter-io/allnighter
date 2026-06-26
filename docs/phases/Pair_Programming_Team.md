# Pair Programming Team (Supervisor + Hammer)

Status: **Draft — learning from OC-S01 sprint experiments**
Owner: AllnighterCore + CLI + Mac GUI
Updated: 2026-06-26

## Why

Featherless + small-context models (e.g. GLM 5.2 on OpenCode) can perform at
frontier level on **narrow implementation slices** when a larger-context supervisor
decomposes work and reviews output. The economics are inverted: unlimited hammer
compute, expensive planner only when needed.

Allnighter already has most of the **run substrate** (teams, workers, write lock,
parent/child runs, typed handoffs). What is missing is a **slice queue loop** with
stall detection — the pattern we are proving manually with
`docs/phases/sprint/` work orders + OpenCode GLM.

## Product shape (founder vision)

```text
Composer / Cursor (supervisor)  →  decompose backlog into sprint work orders
Allnighter (orchestrator)       →  queue, spawn, proof, stall/nudge, retry
OpenCode + GLM (hammer)         →  one slice, autonomous, small context
```

User-visible name candidates: **Pair Team**, **Supervisor + Hammer**, **Build Pair**.
Internal: `pair_programming` team preset + `WorkSlicePacket` handoff.

## First experiment (in progress)

| Piece | Status |
| --- | --- |
| Sprint work orders (`docs/phases/sprint/`) | **Built** — 32K-safe packets |
| OpenCode BYOK (Featherless Qwen/GLM) | **Built** — global `opencode.json` |
| OpenCode driver OC-S01 | **Partial** — manifest/catalog/extractor; wiring in flight |
| Manual supervisor (Cursor) feeding GLM | **Learning** — stalls on ambiguity, fixed by inline skeletons |
| Automated slice queue in Core | **Not built** |

**Lesson from OC-S01a:** GLM burned ~16K tokens researching `Bundle.module` instead
of writing two files. Fix: **zero-fork packets** (inline code skeleton, explicit
“do not read X”), plus **stall nudge** from supervisor.

## Relationship to Try Fix (reuse heavily)

[`Try_Fix_Auto_Implement.md`](Try_Fix_Auto_Implement.md) is the closest shipped
pattern: **read-only answer run → typed packet → gate → one mutating child run**.

| Try Fix | Pair Programming |
| --- | --- |
| Parent: Bug Hunt (answer team) | Parent: Supervisor plan / slice planner (answer or chat) |
| Packet: `FixPacket` (hypothesis + fix + proof) | Packet: `WorkSlicePacket` (sprint doc path + steps + proof) |
| Child: `execution_playbook` / one worker | Child: OpenCode GLM (one worker, mutating) |
| Gate: `TryFixGate` (danger, not confidence) | Gate: `SliceGate` (danger + scope allowlist) |
| Coordinator: `FollowUpCoordinator` | Coordinator: `PairProgrammingCoordinator` (proposed) |
| Loop: elimination rounds (`keepGoing`) | Loop: next slice / retry same slice / escalate |

### What Try Fix already has (wired in Core/CLI)

| Component | Location | Notes |
| --- | --- | --- |
| `FollowUpCoordinator` | `AllnighterEngine/FollowUpCoordinator.swift` | Parent run → parse packet → gate → child run → link runs |
| `TryFixGate` | `AllnighterCore/TryFixGate.swift` | Danger blocks; confidence orders only |
| `FixPacket` + parser | `FixPacket.swift`, `FixPacketParser` | Typed handoff from writer markdown |
| `FixAttemptPrompt` | `FixAttemptPrompt.swift` | **Engineered executor prompt** — “one round, proof, stop” |
| CLI | `RunCLI.runTryFix` | `alln run --try-fix` path exists |
| Tests | `FollowUpCoordinatorTests`, `TryFixGateTests` | Chain behavior proven in unit tests |

### What Try Fix does not have yet (per its own doc)

- Mac **Try Fix** checkbox on team send (CLI-first today)
- `keepGoing` / multi-round elimination UI on Floor
- GUI proof fixture integration for fix attempts

**Pair Programming should copy the coordinator shape, not reinvent it.**

## Relationship to sprint work orders

Sprint docs (`docs/phases/sprint/<topic>/OC-S01a-….md`) are the **human + agent
readable packet format** for the hammer. Long term:

```text
WorkSlicePacket.sprintDocPath → docs/phases/sprint/opencode/OC-S01b-….md
WorkSlicePacket.copyPastePrompt → embedded in doc (or hash of file at queue time)
WorkSlicePacket.proofCommand → swift test --filter …
WorkSlicePacket.touchAllowlist → [WorkerRunner.swift]
```

The supervisor (Composer) **authors or selects** the sprint doc; Core **feeds the
copy-paste block** to OpenCode without the hammer reading the whole repo.

## Architecture (proposed)

### Team preset: `pair_build` (example)

| Seat | Role | Source | Posture |
| --- | --- | --- | --- |
| 1 | Supervisor | `cursor_agent` or `default_chat` | Answer / plan (read-only) |
| 2 | Hammer | `opencode` + `featherless/zai-org/GLM-5.2` | Execute (mutating, write lock) |

**Not parallel fan-out.** Sequential loop:

1. Supervisor emits `WorkSlicePlan` (ordered slice IDs or inline packets).
2. Core runs hammer on slice *N* only.
3. Core runs `proofCommand`; records pass/fail/stall.
4. On pass → slice *N+1*. On stall → nudge (same slice, max 2). On fail → supervisor replan.

### `WorkSlicePacket` (typed handoff — mirror `FixPacket`)

```text
WorkSlicePacket
  schemaVersion
  sliceId                    // e.g. OC-S01b
  sprintDocPath?             // repo-relative path
  copyPastePrompt            // full hammer instruction (required)
  readOnlyPaths[]            // optional audit
  touchAllowlist[]           // required for mutating slices
  proofCommand               // shell command, exit 0 = pass
  maxRetries                 // default 2 (stall + same slice)
  stallTimeoutSeconds        // default 300
  dangerFlags[]              // same hard-stop idea as TryFixGate
```

### `PairProgrammingCoordinator` (mirror `FollowUpCoordinator`)

```text
runPair(request, plan: WorkSlicePlan) async -> PairOutcome
  for slice in plan.slices:
    ensure OpenCodeServeCoordinator running
    spawn opencode run --attach … (hammer worker)
    detect stall (timeout | no diff | think-without-write from logs)
    retry with NudgePrompt if retries remain
    run proofCommand
  link all child runs to parent plan run on Floor
```

### Stall detection (V1 heuristics)

| Signal | Action |
| --- | --- |
| Process timeout | stall → nudge |
| Exit 0, empty extracted stdout | stall → nudge |
| No file changes in `touchAllowlist` after mutating slice | stall → nudge |
| `proofCommand` fails | fail → supervisor (not auto-retry same code) |
| Featherless `model is busy` | backoff retry (infra, not nudge) |

**Nudge prompt** (supervisor template, not LLM-generated):

```text
NUDGE — same slice {sliceId}. Write files now. No research.
Use the skeleton in {sprintDocPath}. Run {proofCommand}. Nothing else.
```

## What Allnighter already has (reuse)

| Capability | Where |
| --- | --- |
| Answer vs execute posture | `TeamPreset.mutating`, `RunWriteLock` |
| One mutating worker | `Unified_Run_Model.md` |
| Parent/child run links | `RunLink`, `FollowUpCoordinator` |
| Typed follow-up actions | `TeamRunJSON.nextActions` |
| Executor prompt assembly | `FixAttemptPrompt` pattern |
| OpenCode driver (partial) | `OpenCode_CLI_Support.md`, OC-S01 sprints |
| Sprint work orders | `docs/phases/sprint/` |
| Project Manager vocabulary | `Work_Order_Team_Model.md` |

## What we still need to build

### Phase PPT-0 — Manual pair (current learning mode)

- [x] Sprint doc standard
- [ ] OpenCode driver OC-S01 complete
- [ ] Document stall/nudge playbook (in sprint README) **done partially**
- [ ] Founder runs Composer → GLM loop manually; capture failure modes

### Phase PPT-1 — Core slice handoff (CLI)

| Slice | Deliverable |
| --- | --- |
| PPT-S01 | `WorkSlicePacket` + parser + tests |
| PPT-S02 | `SliceGate` (allowlist + danger flags) |
| PPT-S03 | `SliceAttemptPrompt.assemble` (from packet, like `FixAttemptPrompt`) |
| PPT-S04 | `PairProgrammingCoordinator` — one slice, one child run |
| PPT-S05 | `alln run --pair --slice <path>` or MCP equivalent |

Reuse: copy structure from `FollowUpCoordinator` + `TryFixGate` almost verbatim.

### Phase PPT-2 — Queue + stall loop

| Slice | Deliverable |
| --- | --- |
| PPT-S06 | Multi-slice plan in one parent run |
| PPT-S07 | Stall detection + nudge injection |
| PPT-S08 | Proof runner integration (`proofCommand` in Core) |
| PPT-S09 | Floor: parent → slice attempts → proof results |

### Phase PPT-3 — Supervisor seat

| Slice | Deliverable |
| --- | --- |
| PPT-S10 | Team preset `pair_build` in `BuiltInTeams` |
| PPT-S11 | Supervisor emits `WorkSlicePlan` (structured output from Cursor seat) |
| PPT-S12 | Mac GUI: “Pair build” team + slice progress rail |

### Phase PPT-4 — OpenCode serve lifecycle

| Slice | Deliverable |
| --- | --- |
| PPT-S13 | `OpenCodeServeCoordinator` in Mac background coordinator |
| PPT-S14 | Health in Doctor / setup card |

Depends on [OC-S01c](sprint/opencode/OC-S01c-serve-coordinator.md).

## Non-goals (V1)

- Parallel hammers (one write lock, one mutating worker).
- Hammer reads full repo / AGENTS.md / phase boards.
- Streaming UI for hammer output (final-output Antigravity posture).
- Allnighter doing git (same as Try Fix).
- Replacing Cursor as supervisor — V1 can be manual supervisor + automated hammer feed.

## Safety (same laws as Try Fix)

- One mutating worker under `RunWriteLock`.
- `touchAllowlist` enforced in gate (danger if slice touches outside list).
- Danger flags: credentials, distribution, destructive git, sandbox/TCC, etc.
- User can stop queue; each slice is inspectable on Floor.
- Failed proof does not auto-infinite-loop — max retries per slice, then escalate.

## Open questions

- Supervisor seat: always `cursor_agent`, or any large-context answer worker?
- Store queue in parent run JSON vs thread-local `PairSession` store?
- Prove stall via OpenCode session export vs process signals only?
- Team Lab: is GLM hammer worth a dedicated necessity suite?

## Routing

| Work | Read |
| --- | --- |
| Implement OpenCode driver | `setup/OpenCode_CLI_Support.md` + `sprint/opencode/` |
| Try Fix chain (template) | `Try_Fix_Auto_Implement.md` + `FollowUpCoordinator.swift` |
| Sprint packet format | `sprint/README.md` |
| Run model / write lock | `Unified_Run_Model.md` |
| Vocabulary | `Work_Order_Team_Model.md` |

## Works Test (V1 manual)

```text
1. opencode serve running; Featherless GLM configured
2. Composer writes OC-S01b sprint doc / prompt
3. Paste to OpenCode; on stall, send NUDGE from sprint README
4. Composer runs proofCommand from doc
5. Repeat until OC-S01d done
```

Automated Works Test (PPT-S04+):

```bash
alln run --pair --slice docs/phases/sprint/opencode/OC-S01b-worker-runner.md --json
```

(Wire when PPT-S01–S05 land.)
