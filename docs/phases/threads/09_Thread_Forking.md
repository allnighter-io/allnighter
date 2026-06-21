# 09 - Thread Forking

Status: Draft feature packet - MCP/CLI-first
Owner: AllnighterCore + AllnighterEngine + CLI/MCP + Mac app
Created: 2026-06-21
Updated: 2026-06-21
Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` ->
`docs/workflows/SSOT_Feature_Workflow.md`
Depends on: [`../Persistent_Work_Threads.md`](../Persistent_Work_Threads.md),
[`../CLI_Implementation_Contract.md`](../CLI_Implementation_Contract.md),
[`../Agent_First_MCP_And_Messaging_Workflows.md`](../Agent_First_MCP_And_Messaging_Workflows.md),
[`../Composer_Image_Attachments.md`](../Composer_Image_Attachments.md),
[`../Composer_File_References.md`](../Composer_File_References.md)

## Founder Intent

Raw request:

```text
Missing feature: you should be able to fork a chat / thread. Given how we are
set up on the backend with JSON files for threads, this should be pretty simple.
It has to work MCP first.
```

Product value:

```text
The user can branch a useful conversation at the exact moment it becomes a new
line of thought, then continue in a fresh thread without re-explaining context or
mutating the source thread.
```

Trusted workflow slice:

```text
open a thread
-> pick Fork from a message/result action
-> Allnighter creates a new active thread from the source prefix
-> the new thread records where it forked from
-> MCP/CLI can fetch and continue the child thread immediately
-> the parent thread remains unchanged
```

Non-goals for v1:

- no merge-back or branch comparison;
- no vendor-native chat session fork;
- no git branch, worktree, commit, or file-system fork;
- no duplication of `RunStore` run truth;
- no hidden GUI-only fork state;
- no automatic summarization, pruning, or rewriting of copied turns;
- no forking of draft/queued/running turn prefixes;
- no iOS surface until the Mac/MCP contract is proven.

## Product Bar

Fork should feel like a normal chat affordance, but it is not UI sugar. It is a
durable thread mutation.

The child thread must be immediately usable by agents:

```text
MCP thread_fork
-> returns child thread id + fork provenance
-> MCP thread_get(child)
-> MCP thread_send(child, follow-up)
```

The feature fails if the Mac app can show a forked-looking thread that MCP cannot
create, inspect, or continue. It also fails if the child thread loses attachments,
file-reference audit, or run links that were visible in the copied prefix.

## Current State

The backend is close, but not "copy one JSON file and ship it." Verified anchors
on 2026-06-21:

- `WorkThread` is the durable `thread.json` model. It carries `id`, `title`,
  `status`, `createdAt`, `updatedAt`, `pinnedAt`, `workingDir`, `projectLabel`,
  `projectId`, `defaultWorkerId`, `turns`, and `readCursor`. It has no fork
  provenance today.
- `ThreadTurn` is the durable timeline model. It can reference a `TeamRun` via
  `runId`, attachments via `attachmentRefs`, file references via
  `fileReferenceRefs`, and context packets via `contextPacketId`.
- `ThreadStore` is the persistence gate for
  `~/Library/Application Support/Allnighter/Threads/thread_<id>/thread.json`.
  It already provides explicit mutation methods for create, append, update,
  rename, pin, archive, unarchive, mark-read, project binding, and context
  packet save. Runtime callers must not raw-save mutated `WorkThread` records.
- Thread subresources live under the same thread folder:
  - `attachments/attachments.json` + canonical attachment bytes;
  - `context/<packetId>.json` context audit packets;
  - `transcript.md` derived from `thread.json`.
- `ThreadStore.runToThreadIndex()` is derived by scanning turns, but it currently
  maps one `runId` to one newest thread. Forking a thread that contains run turns
  will intentionally create multiple thread references to the same run, so this
  index must be hardened before forked run turns ship.
- CLI/contract registry already documents `alln thread send`, `thread get`,
  `thread rename`, and `thread status`, and MCP exposes `thread_send`,
  `thread_get`, `thread_rename`, and `thread_status`.
- Code reality gap: `AllnighterCLI.main` currently dispatches `thread send` and
  `thread rename`, but not `thread get` / `thread status`. MCP has those read
  tools. The fork slice should close this parity gap instead of adding another
  asymmetric thread command.
- `thread_get` and `thread_rename` currently return raw `WorkThread` JSON rather
  than a dedicated public `ThreadJSON` projection. Fork may reuse that short-term
  by wrapping `thread: WorkThread` inside a `ThreadForkJSON` response, but the
  contract should leave a clear upgrade path to a public thread projection.
- Existing stable error codes include `THREAD_NOT_FOUND`, `CLI_USAGE_ERROR`,
  `THREAD_SEND_IDEMPOTENCY_CONFLICT`, and `THREAD_SEND_FAILED`. Fork needs its
  own registry-owned errors.

## First-Principles Decision

A fork is a new `WorkThread` that copies a terminal prefix of an existing
`WorkThread` and records provenance. It is not a new run, not a summary, and not
a new execution lane.

Storage rule:

```text
parent thread.json          unchanged
child thread.json           copied prefix + fork provenance
RunStore/run_<id>/run.json  unchanged and shared by reference
```

Subresource rule:

```text
Every copied turn reference must resolve from the child thread folder.
```

That means fork cannot copy only `thread.json` when the copied turns contain
attachments or context packets. The fork mutation must either copy the referenced
subresources or fail with a registry-owned error. Silent missing attachments or
broken context reveal is not allowed.

## Feature Packet

Allnighter Feature Packet

Status: Draft

### Founder Intent

- Raw request: Fork a chat/thread; backend JSON shape should make it simple; MCP
  must work first.
- Product value: Branch from a useful point without losing context, polluting the
  original thread, or forcing a manual recap.
- Trusted workflow slice: `thread_fork -> thread_get child -> thread_send child`.
- Non-goals: no merge, no git branch/worktree, no vendor session clone, no
  GUI-only button, no run duplication.

### Current State

- Existing truth owners:
  - `WorkThread` / `ThreadTurn` in AllnighterCore.
  - `ThreadStore` in AllnighterEngine.
  - `ThreadAttachmentStore` and thread context packets under each thread folder.
  - `ContractRegistry` for CLI/MCP command/tool descriptors and errors.
- Existing models/API paths:
  - `ThreadStore.create`, `appendTurn`, `updateTurn`, `renameThread`,
    `bindProject`, `archiveThread`, `markRead*`.
  - MCP server thread handlers for `thread_send`, `thread_get`,
    `thread_rename`, and `thread_status`.
  - CLI thread handlers for `thread send` and `thread rename`; documented
    `thread get/status` need dispatch parity.
- Existing parsers/generated outputs:
  - `docs/generated/alln/*` includes the current thread tools and must be
    regenerated after adding fork.
- Existing UI surfaces:
  - Mac thread rail, thread header, and timeline action row can present fork.
  - The screenshot shows a familiar inline message action affordance.
- Existing tests/proof:
  - `ThreadStoreTests` cover atomic persistence, duplicate turns, transcript
    generation, archive/pin/read cursor behavior, context packet validation, and
    run inverse index.
  - `ThreadStoreConcurrencyTests` cover write serialization and atomic reads.
  - Contract tests cover command/tool registry parity.
  - No test covers forking, copied subresources, or duplicate run references.

### SSOT

- Truth owner: `ThreadStore.forkThread(...)` owns fork mutation and persistence.
- Model owner: `WorkThread.forkedFrom` records durable provenance.
- Contract owner: `ContractRegistry` owns `alln thread fork`, MCP `thread_fork`,
  `ThreadForkJSON`, and fork error codes.
- Lie-prone layers:
  - SwiftUI button state that copies a thread in memory.
  - MCP handler that writes `thread.json` directly.
  - CLI command that emits a child id without copying attachments/context.
  - Derived run->thread index that assumes one run belongs to only one thread.
  - A GUI title/badge that implies provenance not present in `thread.json`.
- Duplicate truth to delete:
  - Any fork source fields stored outside `WorkThread`.
  - Any GUI-only child/source relationship.
  - Any MCP-only JSON wrapper not shared with CLI.

### New Semantic Rules

1. Fork is an explicit, local, durable mutation that creates a new active
   `WorkThread`.
2. Fork source is a terminal prefix of a source thread:
   - no `fromTurnId`: copy the full source thread only if every copied turn is
     terminal;
   - with `fromTurnId`: copy turns through that turn, inclusive;
   - copied prefixes containing `draft`, `queued`, or `running` turns fail.
3. Source thread remains byte-for-byte unchanged except for unrelated future
   operations.
4. Child thread receives a new `id`, `createdAt = now`, `updatedAt = now`,
   `status = active`, `pinnedAt = nil`, and a read cursor already advanced
   through the copied prefix so a fork does not create fake unread work.
5. Child metadata inherits `workingDir`, `projectLabel`, `projectId`,
   `localRootPathSnapshot`, and `defaultWorkerId`.
6. Child title is caller-provided or generated from the source title:
   `<source title> (fork)`.
7. Copied turns preserve their turn ids and internal turn references
   (`supersedesTurnId`, `seedFromTurnId`) while normalizing `threadId` to the
   child id. Turn ids are unique per thread, not globally.
8. Copied heavy turns keep `runId`/`stageId` references. `RunStore` records are
   not copied or mutated.
9. `ThreadStore` inverse lookup must become fork-aware before copied run refs
   ship. Either expose `threadIds(forRunId:)` or prefer the non-fork ancestor as
   the primary owner when the same run is referenced by parent and child.
10. Copied attachment refs must resolve in the child:
    - copy only attachment records referenced by copied turns;
    - copy canonical bytes;
    - rewrite copied `TurnAttachment.threadId` to the child id;
    - do not copy `draft_attachments`.
11. Copied context packets must resolve from the child for reveal. They remain
    historical audit for what the original worker saw; do not rewrite packet
    text to pretend the worker saw child paths.
12. File-reference rows remain historical audit. Fork does not re-read project
    files or update stored hashes.
13. Fork is idempotency-keyable for MCP/agent retry. Reusing a key with the same
    source/thread/title/options returns the original child; reusing it with a
    different payload fails.
14. Mac UI must call the same Core/Engine service as CLI/MCP. It does not
    construct the child thread itself.

### CLI Surface

```bash
alln thread fork <thread-id|latest> [--from-turn <turn-id>] [--title <title>] [--idempotency-key <key>] [--json]
alln thread get <thread-id|latest> [--json]
alln thread status <thread-id|latest> [--json]
```

Rules:

- `thread fork` returns human text by default and `ThreadForkJSON` with `--json`.
- `thread get/status` should be dispatched through CLI as part of this slice
  because they are already in generated docs and MCP.
- `latest` resolves through the same `AllnighterCLI.resolveThreadId` helper as
  send/rename.
- `--from-turn` must name a turn in the source thread.
- `--title` is trimmed; empty title fails.
- `--idempotency-key` is optional for human CLI use and recommended for agents.

`ThreadForkJSON`:

```json
{
  "schemaVersion": 1,
  "contractVersion": "1.0.0",
  "sourceThreadId": "thread_parent",
  "sourceTurnId": "turn_worker_2",
  "childThreadId": "thread_child",
  "copiedTurnCount": 4,
  "copiedAttachmentCount": 1,
  "copiedContextPacketCount": 2,
  "sharedRunIds": ["run_123"],
  "fork": {
    "sourceThreadId": "thread_parent",
    "sourceTurnId": "turn_worker_2",
    "sourceTitleSnapshot": "Investigate onboarding bug",
    "sourceUpdatedAt": "2026-06-21T17:00:00Z",
    "createdAt": "2026-06-21T17:05:00Z",
    "origin": "mcp"
  },
  "thread": { "...": "WorkThread JSON for the child" },
  "nextTools": [
    {
      "label": "Continue in fork",
      "command": "alln thread send thread_child \"...\" --json",
      "mcpTool": "thread_send"
    }
  ]
}
```

Exit codes and errors:

| Code | When |
| --- | --- |
| `0` | Fork created or idempotent replay returned. |
| `2` / `CLI_USAGE_ERROR` | Missing source, empty title, malformed args. |
| `1` / `THREAD_NOT_FOUND` | Source thread does not exist. |
| `1` / `THREAD_TURN_NOT_FOUND` | `--from-turn` does not exist in the source. |
| `1` / `THREAD_FORK_NONTERMINAL_PREFIX` | The requested copied prefix contains draft/queued/running turns. |
| `1` / `THREAD_FORK_EMPTY_PREFIX` | The source has no copyable turns. |
| `1` / `THREAD_FORK_IDEMPOTENCY_CONFLICT` | Idempotency key reused with a different fork payload. |
| `1` / `THREAD_FORK_ATTACHMENT_COPY_FAILED` | Copied attachment metadata or bytes could not be verified/copied. |
| `1` / `THREAD_FORK_CONTEXT_COPY_FAILED` | Copied context packet refs could not be copied. |
| `1` / `THREAD_FORK_FAILED` | Defensive catch-all with trace id. |

### MCP Tool

MCP mirrors CLI and is the first acceptance surface.

Tool:

```text
thread_fork
```

Arguments:

```json
{
  "threadId": "latest",
  "fromTurnId": "optional-turn-id",
  "title": "optional child title",
  "idempotencyKey": "optional-agent-retry-key"
}
```

Returns:

```text
ThreadForkJSON
```

Errors:

```text
THREAD_NOT_FOUND
THREAD_TURN_NOT_FOUND
THREAD_FORK_NONTERMINAL_PREFIX
THREAD_FORK_EMPTY_PREFIX
THREAD_FORK_IDEMPOTENCY_CONFLICT
THREAD_FORK_ATTACHMENT_COPY_FAILED
THREAD_FORK_CONTEXT_COPY_FAILED
THREAD_FORK_FAILED
CLI_USAGE_ERROR
```

MCP implementation rules:

- Project from `ContractRegistry`, regenerate `docs/generated/alln/mcp-tools.json`.
- Use a shared handler/service with CLI; do not manually clone files inside
  `MCPServer.swift`.
- Return structured JSON in the tool result body, matching CLI `--json`.
- Include `thread_fork` in help routing and `mcp_hello.tools` once registered.

### Core / Engine Impact

Add model:

```text
ThreadForkProvenance
  sourceThreadId
  sourceTurnId?
  sourceTitleSnapshot
  sourceUpdatedAt
  createdAt
  origin: cli | mcp | gui | ios | localApi | system
```

Add to `WorkThread`:

```text
forkedFrom: ThreadForkProvenance?
```

Add engine API:

```text
ThreadStore.forkThread(
  sourceThreadId: String,
  throughTurnId: String?,
  childThreadId: String,
  title: String?,
  now: Date,
  origin: RunOrigin
) throws -> ThreadForkResult
```

Implementation notes:

- All writes occur under the existing `ThreadStoreWriteSerializer`.
- Fork writes `thread.json` atomically and regenerates `transcript.md`.
- Fork validates every copied `contextPacketId` and attachment ref before the
  child becomes visible. Partial child folders must be removed on failure.
- Fork must not call `saveForImport` from app/CLI runtime paths.
- Fork should expose a lower-level pure copier/helper only if tests need it; the
  public mutation remains `ThreadStore.forkThread`.
- If copied context packets are retained as historical audit, reveal UI must
  label them as forked/copy audit when the packet's delivered paths point at the
  source thread.

### Mac App Impact

Mac surfaces present the contract after MCP proof:

- Inline message action: Fork from this turn.
- Thread rail / header action: Fork thread.
- New child selection: after success, select the child thread and focus the
  composer.
- Parent thread: no visible mutation except normal navigation history.
- Child thread: show a small provenance affordance in the header, derived from
  `forkedFrom`.
- If the source prefix contains running work, show the same
  `THREAD_FORK_NONTERMINAL_PREFIX` recovery message as MCP/CLI.

GUI implementation must use the Core/Engine fork service. No SwiftUI-side JSON
copying.

### iOS / Remote Impact

No iOS UI in v1. When iOS wakes, it calls the same local API/MCP-equivalent
thread fork contract and renders `forkedFrom`; it must not keep an iOS-only fork
relationship.

### Auth / Privacy / Permissions Impact

- No data leaves the user's machines.
- No new Keychain, Full Disk Access, or network permission.
- MCP callers that can already read/fetch threads can create a local fork; this
  is a write to local Allnighter app data, not repo files.
- Fork may duplicate existing pasted images, worker-generated images, and
  referenced-file audit rows inside Application Support. The response should not
  inline attachment bytes.
- Idempotency records store only the canonical fork payload hash and child id,
  not thread contents.

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| GUI -> storage | `ThreadStore.forkThread` | Button copies `WorkThread` in SwiftUI and writes JSON directly. | GUI may only invoke the shared fork service. | Search/audit test rejects `saveForImport` or raw `thread.json` writes from Apps. |
| MCP -> CLI | `ContractRegistry` | MCP adds `thread_fork` with private args or return shape. | MCP tool must project from the same registry and return `ThreadForkJSON`. | Contract test checks `thread fork` and `thread_fork` parity. |
| Thread -> run | `ThreadStore` derived index | A shared run id means the child now owns the run. | Forked run refs do not mutate `RunStore`; inverse lookup is multi/fork-aware. | Parent with `runId` forked to child still resolves parent as primary and lists both refs. |
| Thread -> attachments | `ThreadAttachmentStore` | Forked `attachmentRefs` can point back to parent bytes. | Copied attachment refs must resolve from the child folder or fork fails. | Fork image thread, delete parent folder in temp test, child attachment reveal still works. |
| Thread -> context | `ThreadStore` context packet copy | Rewriting context packet text makes false audit. | Copied packets remain historical audit; do not re-render or re-read files during fork. | Fork packet containing old file hash/path; child reveal marks audit and preserves original delivered text. |
| Source prefix | `ThreadStore.forkThread` | Fork silently drops running/draft turns. | Nonterminal copied prefixes fail. | Source with running worker turn returns `THREAD_FORK_NONTERMINAL_PREFIX`. |

## Build Slices

### FORK-S00 - Packet and routing

- Add this doc.
- Link it from `Persistent_Work_Threads.md` and the phase board.

Proof:

```bash
git diff --check docs/phases/threads/09_Thread_Forking.md docs/phases/Persistent_Work_Threads.md docs/phases/README.md
```

### FORK-S01 - Core schema and store mutation

- Add `ThreadForkProvenance`.
- Add `WorkThread.forkedFrom` additive decode/encode.
- Add `ThreadForkResult` / `ThreadForkJSON`.
- Add `ThreadStore.forkThread`.
- Copy terminal prefix, normalize child `threadId`, preserve turn ids, set
  child read cursor through copied prefix.
- Add store tests for parent unchanged, title generation, from-turn prefix,
  nonterminal rejection, duplicate child rejection, transcript generation, and
  legacy decode.

Proof:

```bash
swift test --package-path Packages/AllnighterCore --filter ThreadStoreTests
```

### FORK-S02 - Subresources and run index hardening

- Copy referenced `attachments/attachments.json` rows + bytes to the child.
- Copy referenced `context/<packetId>.json` records for reveal.
- Add fork-aware run inverse lookup:
  - either `threadIds(forRunId:)` plus primary selection, or
  - parent-preferred `threadId(forRunId:)` when child is a fork of parent.
- Add focused tests with image attachment, context packet, and team run turn.

Proof:

```bash
swift test --package-path Packages/AllnighterCore --filter ThreadFork
swift test --package-path Packages/AllnighterCore --filter ThreadStoreConcurrencyTests
```

### FORK-S03 - CLI/MCP contract first

- Add `thread fork` to `ContractRegistry`.
- Add MCP `thread_fork` projected descriptor and handler.
- Add CLI `alln thread fork`.
- Close CLI dispatch parity for existing `thread get` and `thread status`.
- Add fork error codes and generated docs/schemas/examples.
- Add idempotency store for fork payloads.
- Add MCP transcript/unit proof before GUI work starts.

Proof:

```bash
swift test --package-path Packages/AllnighterCore --filter ContractRegistryTests
swift test --package-path Packages/AllnighterCore --filter MCPToolContractTests
swift run --package-path Packages/AllnighterCore alln dev export-contracts --check
```

Works Test transcript:

```text
MCP thread_fork {threadId:"<seed>", fromTurnId:"<terminal-turn>", idempotencyKey:"fork-1"}
-> returns childThreadId
MCP thread_get {threadId:"<child>"}
-> child has forkedFrom.sourceThreadId == seed and copied prefix only
MCP thread_send {threadId:"<child>", message:"continue from the fork"}
-> appends to child, parent remains unchanged
```

### FORK-S04 - Mac affordance

- Add inline turn action for terminal turns.
- Add thread rail/header fork action for full-thread fork.
- Select child thread on success and focus composer.
- Render provenance from `WorkThread.forkedFrom`.
- Use shared fork service; no UI-local clone.
- Run GUI proof for thread timeline and rail action.

Proof:

```bash
xcodebuild test -scheme AllnighterMac
bash scripts/gui_proof.sh <fork-thread-fixture>
bash scripts/check_gui_proof.sh
```

### FORK-S05 - Help and agent docs

- Add help topic or update thread topic for fork.
- Add examples:
  - `alln thread fork latest --json`
  - `thread_fork` + `thread_send` MCP continuation.
- Add a golden transcript for an agent branching a thread without opening the
  GUI.

Proof:

```bash
swift test --package-path Packages/AllnighterCore --filter HelpTopicRegistryTests
swift run --package-path Packages/AllnighterCore alln dev export-contracts --check
```

## Works Test

Seed fixture:

```text
parent thread
  u1 user message
  w1 worker chat with contextPacketId p1
  u2 user image/file-reference message
  team1 teamRun turn with runId run_1
  w2 worker chat
```

Gesture:

```text
MCP client calls thread_fork(parent, fromTurnId: "team1")
```

Assertions:

- Parent `thread.json` unchanged.
- Child exists with new id, active status, generated title, and
  `forkedFrom.sourceThreadId == parent`.
- Child has turns `[u1, w1, u2, team1]`; no `w2`.
- Every copied turn has `threadId == child`.
- Child read cursor is through `team1`; no fake unread light.
- Child attachment refs and context packets resolve after the parent folder is
  removed in the temp test.
- Child `team1.runId == run_1`; `RunStore` has only one `run_1`.
- Run inverse lookup is fork-aware and does not steal the run from the parent.
- `thread_send(child, "continue")` appends only to the child.

Exact proof command for implementation:

```bash
swift test --package-path Packages/AllnighterCore --filter ThreadFork
```

## Done When

- `thread_fork` works over MCP and returns `ThreadForkJSON`.
- `alln thread fork` returns the same shape with `--json`.
- Existing documented `thread get/status` CLI paths work.
- Parent thread is unchanged; child thread is active and immediately sendable.
- Fork provenance is durable in `thread.json`.
- Copied attachments/context refs resolve in the child.
- Shared run refs do not duplicate or mutate run truth.
- Generated CLI/MCP docs are updated and drift checks pass.
- Mac fork action presents the proven contract and has GUI proof.
