# 2026-06-21 - Cursor Composer Session Continuity Broken

Status: code-read debugger packet only. No product fix in this slice.

## Executive Verdict

Allnighter currently renders a continuing conversation in the GUI, but the active
composer send path launches Cursor Agent as a fresh headless one-shot process for
each turn. The local Cursor Agent CLI supports session continuation
(`--resume [chatId]`, `--continue`, `create-chat`, `resume`, `ls`), but
Allnighter does not persist a Cursor chat id, does not pass `--resume <chatId>`,
and has no driver-session field in the active run/session plumbing.

The founder symptom is therefore credible and expected:

```text
Turn 1: user asks model to do/read something.
Turn 2, same visible Allnighter thread + same Composer 2.5 model:
worker says it does not have prior context.
```

This is not a model-quality issue. It is a session-contract bug.

## Debug Packet

Tier: T3 Critical (core product promise failure; session state / persisted data
truth issue)

Symptom / repro:

- In one Allnighter conversation, choose `Composer 2.5`.
- Send turn 1.
- Send turn 2 in the same visible conversation, without switching model.
- Composer replies that it lacks prior context.

Bug fingerprint:

```text
RoutingComposer / ThreadsViewModel.runViaRunService
+ RunService / WorkerRunner
+ cursor_agent manifest one-shot argv
+ no persisted external CLI chat id
```

Attempt count: first documented session-continuity packet. Similar symptoms were
not found in `BUG_PATTERNS.json` or `DEBUGLOG.md`.

Seam:

```text
Visible Allnighter WorkThread
-> TeamRun / RunService run record
-> WorkerRunner subprocess invocation
-> Cursor Agent vendor chat/session
```

Truth owner:

- User-facing conversation truth starts at `WorkThread`.
- Worker-run truth starts at `TeamRun`.
- Missing owner: a durable per-thread, per-driver external CLI session mapping.
  Suggested contract: `ExternalWorkerSession` / `DriverConversationRef`, keyed
  at least by `threadId + sourceId + modelId + repoRoot`, carrying the vendor
  chat/session id and last-use metadata.

Lie-prone layer:

- The GUI thread can show prior turns, while the underlying CLI receives a new
  vendor session.
- Prompt context can include prior Allnighter text, but that is not equivalent
  to resuming Cursor's own agent harness.
- `originConversationId` exists on `TeamRun`, but that field is for the
  originating client conversation, not the worker vendor chat id, and the active
  GUI path does not set it anyway.

Regression considered:

- No exact existing regression law.
- Add a backlog law: same visible thread + same worker source must not spawn a
  fresh vendor session when the source exposes a resume handle.

Isolation harness:

- Not required before documentation. The failing primitive is not native UI or
  platform behavior; local `agent --help` proves the vendor CLI has a resume
  surface.
- A future fix should add a command-runner harness that captures argv across two
  sends and proves the second send contains a thread-scoped resume id.

Missing kill test / proof:

- A two-turn Cursor Agent continuity test that is red today: first send
  creates/captures a Cursor chat id, persists it against the Allnighter thread,
  then second send in the same thread invokes Cursor with `--resume <that-id>`
  and not `--continue`.
- A cross-thread isolation test: two Allnighter threads in the same repo and
  same model must not share the same Cursor chat id.
- A persistence test: app/store reload between turns must still resume the same
  driver session.
- A source-switch test: if Auto substitutes to another source, it must not pass
  Cursor's chat id to that other source. Returning to Cursor should resume only
  the Cursor session attached to that Allnighter thread.

Fix boundary:

- Do not fix this by prompt-stuffing more prior turns.
- Do not use `agent --continue` for Allnighter thread continuity. It resumes the
  latest Cursor session globally and can cross-contaminate threads.
- Do not overload `TeamRun.originConversationId`; it means origin client
  conversation, not worker vendor session.
- Add an explicit driver-session contract and wire it through RunService /
  WorkerRunner / manifest resolution.

Proof command / founder test:

```bash
swift test --package-path Packages/AllnighterCore --filter CursorSessionContinuity
swift test --package-path Packages/AllnighterCore --filter RunServiceSessionContinuity
```

Founder Works Test:

1. Start a fresh Allnighter thread.
2. Pick Composer 2.5.
3. Turn 1: "Remember the word amberclock and reply OK."
4. Turn 2: "What word did I ask you to remember?"
5. Expected: the worker answers `amberclock` without "I do not have prior
   context."
6. Inspect debug/proof output: second Cursor invocation used the same stored
   chat id with `--resume <id>`.

## Code Read Evidence

### 1. Active GUI composer bypasses the older `worker_chat` path

`ThreadsViewModel.sendRouting` is the visible composer send path. It resolves a
project root, appends the user turn, then calls `runViaRunService`.

Evidence:

- `Apps/AllnighterMac/Sources/ThreadsViewModel.swift:448` says sends go through
  `RunService` in a bound Project root.
- `Apps/AllnighterMac/Sources/ThreadsViewModel.swift:493` appends the user turn.
- `Apps/AllnighterMac/Sources/ThreadsViewModel.swift:501` calls
  `runViaRunService(...)`.

This matters because the older `WorkerChatCoordinator` / `ThreadSendCoordinator`
path builds a `ThreadContextPacket` from recent turns, but the active composer
path is now the unified `RunService` path.

### 2. Each composer send creates a fresh `TeamRun`

`runViaRunService` allocates a new `runId` every send and creates a run-backed
thread turn.

Evidence:

- `Apps/AllnighterMac/Sources/ThreadsViewModel.swift:556` creates
  `let runId = UUID().uuidString`.
- `Apps/AllnighterMac/Sources/ThreadsViewModel.swift:558` creates a new
  `ThreadTurn`.
- `Apps/AllnighterMac/Sources/ThreadsViewModel.swift:567` creates `RunRequest`.
- That request has `message`, `repoRoot`, `projectId`, `presetId`, `workerId`,
  `effort`, `lane`, `context`, and `deliveries`; it has no `threadId` and no
  external session/chat id.

### 3. `RunService` does not receive or persist thread/vendor session identity

`RunService.run` normalizes the repo root, resolves a team/worker, creates a
`WorkerRunner`, and runs either execution or answer shape. It does not receive a
thread id or external worker session id.

Evidence:

- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift:191`
  starts `run(_ request: RunRequest, ...)`.
- `RunRequest` currently has `context`, but no `threadId` and no
  `externalSessionId`.
- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift:257`
  constructs `WorkerRunner(...)`.
- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift:262`
  dispatches execution runs to `runExecution`.
- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift:271`
  dispatches answer runs to `runAnswer`.

### 4. `TeamRun` has origin conversation fields, but they are not the worker session

`TeamRun` contains:

- `threadId`
- `originConversationId`
- `originMessageId`

Evidence:

- `Packages/AllnighterCore/Sources/AllnighterCore/TeamRun.swift:52`
- `Packages/AllnighterCore/Sources/AllnighterCore/TeamRun.swift:53`
- `Packages/AllnighterCore/Sources/AllnighterCore/TeamRun.swift:54`

But `runExecution` constructs the `TeamRun` without those fields:

- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift:356`
  creates `TeamRun(...)`.
- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift:366`
  sets `mutating` and `executionSourceId`, but not `threadId`,
  `originConversationId`, or a vendor session field.

`CatalogRunCoordinator` does the same for answer teams:

- `Packages/AllnighterCore/Sources/AllnighterEngine/CatalogRunCoordinator.swift:52`
  creates `TeamRun(...)`.
- `Packages/AllnighterCore/Sources/AllnighterEngine/CatalogRunCoordinator.swift:61`
  stops after `createdAt`; no thread or worker-session field is populated.

### 5. `WorkThread` and `ThreadTurn` have no external worker-session storage

`WorkThread` stores local thread metadata and turns:

- `Packages/AllnighterCore/Sources/AllnighterCore/WorkThread.swift:17`
  through `:41` list current fields.
- There is `defaultWorkerId` and `turns`; there is no `externalSessions`,
  `driverSessions`, `cursorChatId`, or equivalent.

`ThreadTurn` stores local turn facts:

- `Packages/AllnighterCore/Sources/AllnighterCore/ThreadTurn.swift:8` through
  `:48` list current fields.
- There is `runId`, `contextPacketId`, and `seedFromTurnId`; there is no
  external CLI session id.

### 6. `WorkerRunner` resolves and runs manifest argv only

Non-streaming:

- `Packages/AllnighterCore/Sources/AllnighterEngine/WorkerRunner.swift:96`
  builds `DriverManifest.ResolveContext` from prompt/model/workingDir/outputFile.
- `Packages/AllnighterCore/Sources/AllnighterEngine/WorkerRunner.swift:103`
  resolves manifest args.
- `Packages/AllnighterCore/Sources/AllnighterEngine/WorkerRunner.swift:111`
  runs the subprocess.

Streaming:

- `Packages/AllnighterCore/Sources/AllnighterEngine/WorkerRunner.swift:260`
  builds the same context.
- `Packages/AllnighterCore/Sources/AllnighterEngine/WorkerRunner.swift:263`
  resolves streaming args.
- `Packages/AllnighterCore/Sources/AllnighterEngine/WorkerRunner.swift:274`
  runs the streaming subprocess.

There is no parameter for `externalSessionId`, no result metadata for a newly
created vendor chat id, and no callback to persist one.

### 7. Cursor Agent manifest never passes `--resume`

Packaged app manifest:

- `Apps/AllnighterMac/Resources/Drivers/cursor_agent.json:11` through `:20`
  define non-streaming args:

```text
agent -p --output-format text --model {{model}} --trust --workspace {{workingDir}} {{prompt}}
```

- `Apps/AllnighterMac/Resources/Drivers/cursor_agent.json:36` through `:46`
  define streaming args:

```text
agent -p --output-format stream-json --stream-partial-output --model {{model}} --trust --workspace {{workingDir}} {{prompt}}
```

Neither includes `--resume {{sessionId}}`, `--continue`, or any session token.

`DefaultConfig.swift` embeds the same Cursor manifest string for the CLI /
package fallback, so this is not only a bundle-resource issue.

### 8. Cursor stream parser cannot surface a session id even if the stream has one

`CursorStreamParser.Event` decodes only:

- `type`
- `timestamp_ms`
- `model_call_id`
- `message`
- `result`

Evidence:

- `Packages/AllnighterCore/Sources/AllnighterEngine/CursorStreamParser.swift:64`
  through `:69`.

Unknown fields are ignored by Swift decoding. Raw events may be yielded for
audit, but `WorkerRunOutcome` and `WorkerAnswer` have no place to store a vendor
session receipt.

### 9. Cursor Agent itself exposes continuation

Local help inspection only; no prompt was sent and no quota-bearing run was
made.

Commands run:

```bash
command -v agent
agent --version
agent --help
agent create-chat --help
agent resume --help
agent ls --help
```

Observed relevant help surface:

```text
--resume [chatId]    Select a session to resume
--continue           Continue previous session
create-chat          Create a new empty chat and return its ID
resume               Resume the latest chat session
ls                   Resume a chat session
```

Conclusion: vendor continuation is possible for Cursor Agent. Allnighter is not
using it.

## Why Prompt-Stuffing Is Not The Fix

`ThreadContextBuilder` can render recent local turns into a prompt:

- `Packages/AllnighterCore/Sources/AllnighterEngine/ThreadContextBuilder.swift:123`
  selects text turns.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ThreadContextBuilder.swift:134`
  writes a `Recent turns:` block.

That is useful as bounded context, but it is not the Cursor CLI harness. The
founder explicitly expects the same CLI session semantics as working inside
Cursor CLI. If Cursor supports a real session id, Allnighter must use it.

Prompt-stuffing is also fragile:

- It truncates.
- It loses hidden tool state and vendor-side conversation state.
- It does not preserve the worker's own harness continuity.
- It can make the GUI look fixed while the second CLI argv is still fresh.

## Required Future Implementation Shape

1. Add a driver-session contract.

   Suggested durable record:

   ```text
   ExternalWorkerSession
     id
     threadId
     sourceId          # cursor_agent
     modelId           # model_cursor_composer_25 for strict v1
     repoRoot
     vendorSessionId   # Cursor chat id
     createdAt
     lastUsedAt
     lastRunId?
     status
   ```

   Storage can be additive on `WorkThread` or a separate
   `thread_<id>/worker_sessions.json`. A separate file avoids bloating
   `thread.json`, but the truth owner is still the thread.

2. Extend runner invocation input and output.

   `WorkerRunner.invoke` / `invokeStreaming` need an optional session ref and
   need to return any new/updated session receipt. Do not hide this inside raw
   stdout parsing only.

3. Extend driver manifests with session-aware args.

   Cursor needs something equivalent to:

   ```text
   first turn:
     agent -p ... --workspace {{workingDir}} {{prompt}}
     or pre-create: agent create-chat -> id, then agent -p --resume {{sessionId}} ...

   later turns:
     agent -p ... --resume {{sessionId}} --workspace {{workingDir}} {{prompt}}
   ```

   Exact ordering must be verified against real Cursor Agent.

4. Forbid unscoped `--continue`.

   `--continue` is global-latest state. It can resume the wrong Cursor session
   if the user has Cursor CLI activity outside Allnighter or another Allnighter
   thread just ran. Use only explicit `--resume <stored id>`.

5. Make the active GUI path pass thread identity into `RunService`.

   `RunRequest` needs `threadId` or a session context. `runViaRunService` has the
   thread id already; it drops it before creating `RunRequest`.

6. Persist receipts before claiming success.

   If first-turn Cursor returns/creates a chat id but Allnighter cannot persist
   it, the run should settle with an honest warning or failure that continuity is
   not guaranteed. Silent loss recreates this bug.

## Kill Tests To Write Before Patching

Suggested test names:

```text
CursorSessionContinuityTests.testSecondTurnUsesStoredCursorChatId
CursorSessionContinuityTests.testDoesNotUseGlobalContinueForThreadResume
CursorSessionContinuityTests.testDifferentThreadsDoNotShareCursorChatId
CursorSessionContinuityTests.testReloadedThreadStillResumesCursorChatId
RunServiceSessionContinuityTests.testGuiRunRequestCarriesThreadSessionContext
WorkerRunnerSessionTests.testCursorResumeArgIsInjectedBeforePrompt
```

The first test should use a command runner that captures argv for two sends.

Expected red state today:

```text
first args:  agent -p ... --workspace <repo> <prompt1>
second args: agent -p ... --workspace <repo> <prompt2>
```

Expected green state:

```text
first args:  create/capture chat id for thread T + cursor_agent
second args: agent -p ... --resume <stored-chat-id> --workspace <repo> <prompt2>
```

Negative assertion:

```text
second args must not contain "--continue"
```

## Open Questions For The Fixer

1. Does `agent -p --output-format stream-json ...` emit a chat id in any raw
   event, or must Allnighter call `agent create-chat` first?
2. Does `agent create-chat` create a chat that can immediately accept
   `agent -p --resume <chatId> <prompt>`?
3. Can a resumed Cursor chat change `--model`, and if yes should Allnighter
   allow same-thread model switches or fork a new external session per model?
4. Do Claude, Codex, Grok, and Antigravity expose equivalent session handles?
   If not, their drivers must explicitly declare `continuity: promptContextOnly`
   or `continuity: unsupported`, so the UI does not promise vendor-session
   continuity for them.

## What Must Never Happen Again

An agent was allowed to make Allnighter display a persistent conversation while
the worker driver launched fresh CLI sessions per turn, with no regression proof
that turn 2 resumed the same vendor chat. Future agents must not close any
conversation-continuity bug from GUI thread persistence, prompt context, or a
single successful reply. The proof owner is the second worker invocation argv
and the persisted driver-session receipt.
