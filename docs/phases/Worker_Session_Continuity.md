# Worker Session Continuity

Status: **CODE RED — IN PROGRESS**. Owner surfaces: AllnighterCore + AllnighterEngine
+ AllnighterCLI (CLI/MCP) + AllnighterMac + driver manifests.
Updated: 2026-06-21.
Debugger packet: [docs/operations/debugger/2026-06-21-cursor-composer-session-continuity-code-red.md](../operations/debugger/2026-06-21-cursor-composer-session-continuity-code-red.md)
Workflow: SSOT (CLI/MCP-first) + Execution-Playbook (orchestrated, one CLI at a time).

## Founder intent (verbatim)

```text
If a single threaded conversation with one model is NOT one continuing session with
the CLI then we are dead. If I am talking to you, you remember what we have been
talking about because it is all in one CLI session. Allnighter must piggy back on top
of these single sessions within any given threaded conversation. Currently it does
not. That makes the experience 10x worse. It is a dead end.

Once we fix this we do NOT need to dump all the additional context of what happened in
the thread on the model with each turn. That is only needed if you are switching
between models since that opens a new session on the CLI side.
```

## Verdict (the reason we proceed, not kill)

**Every CLI Allnighter supports exposes resume-by-session-id.** This is a wiring gap in
Allnighter, not an architectural impossibility. Confirmed live via `--help` on each CLI
(no quota-bearing prompts in the survey):

| Source (`sourceId`) | Binary | Resume mechanism | Turn-1 id acquisition | Continuity tier |
| --- | --- | --- | --- | --- |
| `claude_code` | `claude` | `--resume <id>` | **SET** `--session-id <uuid>` (we mint it; parse-free) | `vendorSession` |
| `cursor_agent` | `agent` | `--resume <chatId>` | `agent create-chat` → id (or capture from stream-json) | `vendorSession` |
| `codex` | `codex` | `codex exec resume <id> <prompt>` | capture from `codex exec --json` JSONL | `vendorSession` |
| `grok` | `grok` | `-r/--resume <SESSION_ID>` | capture from `--output-format streaming-json` | `vendorSession` |
| `antigravity` | `agy` | `--conversation <id>` | ⚠️ no capturable id in `--print` mode (vendor gap) | `promptContextOnly` (v1) |

`claude_code` is the cleanest and is the proof-of-life CLI: we generate the session UUID,
pass `--session-id <uuid>` on turn 1, then `--resume <uuid>` forever after. No output
parsing, no race.

## The bug today (confirmed in code)

The GUI shows one conversation; the worker path launches a fresh vendor session per turn.
- `RunRequest` carries no `threadId` and no external session id.
- Driver manifests are one-shot argv with no `--resume`/session token.
- `WorkerRunner` neither accepts a resume id nor captures/persists a new one.
- No durable per-(thread, source) vendor-session store exists.
- `originConversationId` on `TeamRun` is the *origin client* conversation, not the worker
  vendor session — and the active GUI path doesn't even set it.

## New semantic rules (LOCKED)

1. **One vendor session per `(threadId, sourceId)`** — and per `modelId` too (a model
   switch within a source forks a new vendor session; see §Model switch).
2. **Resume by explicit stored id only.** `--continue`/`-c` (global most-recent) is
   FORBIDDEN — it cross-contaminates threads and any out-of-Allnighter CLI use.
3. **Context-dump is conditional (founder rule).** When we *resume* an existing vendor
   session, send ONLY the new prompt — the CLI already holds the history. We attach the
   `ThreadContextBuilder` packet ONLY when there is no live session for `(thread, source,
   model)` — i.e. the first turn on that source, or immediately after a model/source
   switch (bootstrapping the fresh session). This makes continuity faster and cheaper AND
   correctly seeds a new session on switch.
4. **Persist the receipt before claiming success.** If turn 1 creates/returns a session id
   but we cannot persist it, settle the turn with an honest continuity warning — never lose
   it silently (that recreates this bug).
5. **Source-switch isolation.** When Auto substitutes to another source, never hand that
   source another source's session id. Returning to the original source resumes only its
   own session for that thread.
6. **Cross-thread isolation.** Two threads (same repo, same model) must never share a
   vendor session id.

## Truth owner

```text
Durable per-(thread, source, model) vendor session  →  ExternalWorkerSessionStore
   keyed by: threadId + sourceId + modelId + repoRoot
   carries:  vendorSessionId, continuityTier, createdAt, lastUsedAt, lastRunId, status
Visible conversation truth  →  WorkThread / ThreadTurn  (owns the store as a sidecar)
Worker-run truth            →  TeamRun / WorkerRunOutcome  (carries the resume id used +
                                any newly captured id, for audit)
```

Storage: a `thread_<id>/worker_sessions.json` sidecar (the thread owns it; keeps
`thread.json` lean and off the streaming hot path). Read/written by the engine, projected
by CLI/MCP.

## Core contract (CONT-S0)

```text
ExternalWorkerSession (Codable, Sendable)
  id: String                  # alln-local record id
  threadId: String
  sourceId: String            # claude_code | cursor_agent | codex | grok | antigravity
  modelId: String
  repoRoot: String
  vendorSessionId: String     # the CLI's own chat/session/conversation id
  continuityTier: ContinuityTier   # vendorSession | promptContextOnly | unsupported
  createdAt / lastUsedAt: Date
  lastRunId: String?
  status: .active | .stale | .invalidated

ContinuityTier (per driver, declared in the manifest)
  vendorSession      # real resume by id (claude/cursor/codex/grok)
  promptContextOnly  # no usable vendor id → bounded ThreadContextBuilder packet (agy v1)
  unsupported        # never promise continuity
```

`ExternalWorkerSessionStore`: load/save/upsert/get(threadId,sourceId,modelId,repoRoot)/
invalidate. Pure-ish over the sidecar file; injectable for tests.

## Driver manifest extension (CONT-S0)

Each driver manifest gains a `session` block:

```jsonc
"session": {
  "continuity": "vendorSession",            // tier
  "acquire": "set" | "capture" | "create",  // how turn-1 id is obtained
  "idArg": "--session-id",                   // (acquire=set) flag that ASSIGNS our uuid
  "createArgv": ["create-chat"],             // (acquire=create) returns id on stdout
  "resumeTemplate": ["--resume", "{{sessionId}}"],     // injected on later turns
  // codex differs: resume is a subcommand reshaping argv:
  //   "resumeArgv": ["exec","resume","{{sessionId}}","{{prompt}}", ...]
  "capture": { "from": "stream-json", "field": "session_id" }  // (acquire=capture)
}
```

Per CLI (verified flags; capture field confirmed by a controlled run in its slice):

- **claude_code** — `acquire:set`, `idArg:"--session-id"`, `resumeTemplate:["--resume","{{sessionId}}"]`. We mint the uuid; no capture.
- **cursor_agent** — `acquire:create`, `createArgv:["create-chat"]`, `resumeTemplate:["--resume","{{sessionId}}"]`.
- **codex** — `acquire:capture` from `codex exec --json` (field TBD by run, likely `session_id`/`conversation_id`), `resumeArgv` reshapes to `exec resume {{sessionId}} {{prompt}}`.
- **grok** — `acquire:capture` from `--output-format streaming-json` (field TBD by run), `resumeTemplate:["--resume","{{sessionId}}"]`.
- **antigravity** — `continuity:"promptContextOnly"` for v1 (no capturable id in `--print`); revisit when the vendor exposes one.

## Run-path plumbing (CONT-S1)

1. `RunRequest` gains `threadId: String?` (and the resolved `repoRoot` already exists).
2. `runViaRunService` stops dropping the thread id — passes it into `RunRequest`.
3. `RunService.run`:
   - resolve `(threadId, sourceId, modelId, repoRoot)` → `ExternalWorkerSessionStore.get`;
   - if a live `vendorSession` exists → pass `resumeSessionId` to the runner AND **skip the
     context packet** (rule 3);
   - else (first turn / switch / promptContextOnly) → no resume id; attach the context
     packet to bootstrap.
4. `WorkerRunner.invoke/invokeStreaming` gain `resumeSessionId: String?` and return
   `capturedSessionId: String?` (from the manifest `capture` rule or `create`/`set`).
5. On success, `RunService` upserts the session receipt **before** settling the run.
6. Manifest resolution (`DriverManifest.resolve`) injects the resume args / reshapes argv
   per the `session` block, given the resume id (or sets the minted id on turn 1).

## CLI / MCP surface (agent-first; MUST ship with the capability)

- `alln sessions [--thread <id>] [--json]` → list `ExternalWorkerSession` rows (thread,
  source, model, vendorSessionId, tier, lastUsedAt). Read-only projection.
- `alln sessions invalidate <threadId> <sourceId>` → drop a session (force a fresh start).
- MCP: `worker_sessions_list` (projects the same envelope), `worker_sessions_invalidate`.
- Run artifacts / `run_show` expose `resumeSessionIdUsed` + `capturedSessionId` so an agent
  can PROVE turn 2 resumed turn 1's session.
- Contract-registered (`ContractRegistry`), schema-backed JSON, error codes
  (`SESSION_NOT_FOUND`, `SESSION_PERSIST_FAILED`). One contract — CLI = MCP = GUI.

## Kill tests (red today → green when fixed)

```text
WorkerSessionStoreTests
  upsert/get by (thread,source,model,repoRoot); cross-thread rows never collide.
RunServiceSessionContinuityTests
  testGuiRunRequestCarriesThreadId
  testResumeSkipsContextPacket            # rule 3: resumed turn sends prompt only
  testSwitchModelForksNewSessionAndDumpsContext
WorkerRunnerSessionTests (argv-capture harness)
  testTurn2InjectsStoredResumeId
  testNeverUsesGlobalContinue             # negative: argv must not contain --continue/-c
  testDifferentThreadsDoNotShareVendorId
  testReloadedThreadStillResumes          # persistence across store reload
Per-CLI live continuity (quota-bearing, one per CLI):
  claude: set session-id turn1 → resume turn2 → model recalls turn-1 fact.
  cursor/codex/grok: capture id turn1 → resume turn2 → recall.
```

Founder Works Test: fresh thread → pick a model → turn 1 "Remember the word amberclock and
reply OK" → turn 2 "What word did I ask you to remember?" → answers `amberclock` with no
"I lack prior context"; run artifact shows turn 2 used turn 1's `vendorSessionId`.

## Sliced plan (Execution-Playbook, orchestrated, one CLI at a time)

- [ ] **CONT-S0 — Contract + store + manifest schema.** `ExternalWorkerSession[Store]`,
  `ContinuityTier`, manifest `session` block + decoder, `RunRequest.threadId`. Tests:
  `WorkerSessionStoreTests`. No behavior change yet.
- [ ] **CONT-S1 — Run-path plumbing + argv harness.** Thread id through
  `runViaRunService → RunRequest → RunService → WorkerRunner`; resume-id in / captured-id
  out; conditional context packet; persist-before-success. Argv-capture kill tests RED→GREEN.
- [ ] **CONT-S2 — claude_code (proof of life).** `--session-id` mint + `--resume`; live
  two-turn recall run. **First end-to-end green CLI.**
- [ ] **CONT-S3 — cursor_agent.** `create-chat` + `--resume`; live recall.
- [ ] **CONT-S4 — codex.** `--json` capture + `exec resume`; live recall.
- [ ] **CONT-S5 — grok.** `streaming-json` capture + `--resume`; live recall.
- [ ] **CONT-S6 — antigravity.** declare `promptContextOnly`; bounded context; vendor ask.
- [ ] **CONT-S7 — CLI/MCP surface + GUI honesty.** `alln sessions` + MCP tools + run-artifact
  receipts; GUI shows continuity state per thread/source.

Each slice: implement → focused proof → deslop → audit → closeout (green wall) → commit.

## Risks / unknowns (closed per slice, real runs allowed)

- Exact capture field name for codex/grok/cursor stream-json — confirmed by one controlled
  run in that CLI's slice (quota acceptable per founder).
- Antigravity has no headless id surface — v1 `promptContextOnly`; do not fake a vendor id.
- Model-switch policy = fork a new vendor session per `(thread, source, model)`; switching
  back resumes the prior one if still valid.
- Vendor session expiry/eviction — on a resume failure, invalidate the stored row, fall
  back to a fresh session + context packet, and surface it honestly.

## Done when

- Same thread + same model = one continuing vendor session; turn 2 recalls turn-1 facts.
- Resumed turns send the prompt only (no context re-dump); switches fork + seed context.
- `--continue` never appears in any argv; threads never share a vendor id; persistence
  survives store reload.
- All five CLIs are either real `vendorSession` (claude/cursor/codex/grok) or honestly
  `promptContextOnly` (agy), declared in the manifest and visible via CLI/MCP.
- Kill tests green; one live two-turn recall proof per `vendorSession` CLI.
