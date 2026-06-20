# 03 - Mac Streaming

Status: V1 implementation spec - solo worker chat first
Owner: AllnighterEngine + Mac app backend
Updated: 2026-06-19

## Goal

Make Project Manager chat feel alive while a single worker is answering.

V1 is **solo worker chat streaming** only: one chat turn, one resolved worker,
one CLI process. Team-run streaming is V2 after the one-worker path is proven.

## Founder Intent

Raw request:

```text
We must enable streaming so while waiting for answers from the agents / CLIs
Allnighter does not feel DEAD. V1: streaming for solo runs (chat responses).
Once we nail that we can think about streaming for team answers.
```

Product bar:

```text
The user sees the worker start answering before the process exits.
```

Do not fake this with timers, placeholder prose, or post-exit replay.

## Current Reality

As of 2026-06-19, the dead-air layer is the subprocess boundary:

- `ThreadSendCoordinator.completeSend` invokes `WorkerRunner.invoke` and settles
  the `worker_chat` turn only after the CLI exits.
- `WorkerRunner.invoke` calls `CommandRunner.run`.
- `SubprocessCommandRunner.run` accumulates stdout/stderr into buffers and
  returns one `CommandResult` at termination.
- Codex final-answer capture currently uses `-o {{outputFile}}`, so stdout can
  be reserved for structured events without losing the final answer.
- `RunCLI --stream` has a live `RunEvent` mapper for team/run lifecycle events,
  but it does not expose child-process text deltas from `WorkerRunner`.

Therefore V1 must add a streaming subprocess path and a worker-chat partial
output path. The existing final `WorkerRunOutcome` path remains the terminal
truth.

## User-Visible Claim

```text
When a worker supports live output, Allnighter shows the reply as it arrives.
When it does not, Allnighter shows an honest running turn and lands the full
reply on completion.
```

No product copy may claim streaming for a source until a real-driver Works Test
has shown text before process exit.

## Scope

In:

- Project Manager chat / `worker_chat` turns.
- Headless text workers only.
- Mac app first.
- CLI and MCP may expose the same event contract after the engine path exists.
- Final output still normalizes through `WorkerRunner` rules.
- Partial text is local-only thread state.

Out:

- Team-run multi-worker streaming.
- Plan/synthesis/review streaming.
- Image generation streaming.
- iOS partial streaming.
- Token-rate charts or usage parsing from streams.
- Workspace rollback/discard affordances after cancellation.

## V1 Architecture

Add a streaming command seam beside the existing request/response seam:

```text
StreamingCommandRunner.run(...)
  -> AsyncThrowingStream<CommandEvent>
```

```text
CommandEvent
- started(startedAt)
- stdout(Data)
- stderr(Data)
- completed(CommandResult)
- failed(launchError)
- timedOut(partialStdout, partialStderr)
- cancelled(partialStdout, partialStderr)
```

Rules:

- `CommandRunner.run` remains for non-streaming drivers and existing tests.
- `SubprocessCommandRunner` can implement both protocols; both paths must share
  process-group kill, timeout, env scrubbing, stdin, PATH resolution, and working
  directory rules.
- Stream chunks are bytes first. Driver parsers own UTF-8 framing, line buffering,
  JSONL parsing, and partial-message assembly.
- The terminal `CommandResult` includes the complete stdout/stderr buffers, same
  as today's non-streaming path.
- Timeout/cancel events preserve partial buffers and still emit a terminal
  result shape.

Add worker-level parsing beside `WorkerRunner.invoke`:

```text
WorkerRunner.invokeStreaming(...)
  -> AsyncThrowingStream<WorkerStreamEvent>
```

```text
WorkerStreamEvent
- started(workerId, modelId, sourceId)
- answerDelta(text, sequence, isMarkdown)
- rawEvent(sourceId, JSONValue)        # debug/audit only, not default UI text
- toolActivity(label, kind)            # optional V1, if parser can map safely
- completed(WorkerRunOutcome)
- failed(WorkerRunOutcome)
```

Rules:

- Only `answerDelta` mutates visible chat text.
- Parser failures do not kill the process by themselves. They mark the stream as
  degraded and the final result still settles from the full output/capture file.
- Partial text must not become the authoritative final answer until the worker
  settles.
- Do not expose raw reasoning by default. If a CLI emits reasoning events,
  preserve them for audit/debug only unless a later product decision explicitly
  adds a visible reasoning surface.

## Thread Storage

V1 stores partial text on the running `ThreadTurn.text` so SwiftUI can render the
same turn while it is running and after it settles.

Rules:

- Append deltas to the running worker turn at a throttled cadence.
- Target flush cadence: every 120-250 ms or every 2-4 KB, whichever comes first.
- Cap visible partial text at 64 KB per turn for V1.
- If cap is exceeded, keep the newest visible suffix and set an internal
  truncation marker. The final answer may replace the partial with the complete
  normalized output when the process exits.
- `ThreadStore.updateTurn` remains the persistence boundary; no SwiftUI-only
  truth.
- Running turn text is local user data. Do not upload or relay by default.
- On failure/timeout/cancel, preserve useful partial text and append/display the
  failure state separately; do not overwrite a real partial with only an error
  string.

Open implementation choice:

```text
Either add ThreadTurn.partialOutputTruncated: Bool, or encode truncation in a
small artifact/system field. Do not put user-visible bookkeeping prose inside
the answer text.
```

## Mac UI

V1 rendering behavior:

- The worker turn appears immediately in `running`.
- As `answerDelta` events arrive, the same turn body updates.
- Markdown may render incrementally, but malformed in-progress Markdown must not
  break layout; the final settled text is the polished render.
- A small live/running affordance is allowed.
- Cancel remains available and kills the process group.
- If streaming degrades but the CLI completes, show the final answer and avoid
  a scary error.
- If a source does not support streaming, keep today's running state and final
  answer behavior.

## Driver Capability

Extend driver manifests after the first parser lands:

```json
"streaming": {
  "supported": true,
  "mode": "jsonl_stdout",
  "args": ["..."],
  "partialOutput": true,
  "answerDeltaPaths": ["..."],
  "finalAnswerSource": "output_file|stdout|event",
  "stripAnsi": true,
  "visibleReasoning": false
}
```

Suggested enum values:

```text
mode: none | plain_stdout | jsonl_stdout | jsonl_stderr | output_file_tail
finalAnswerSource: stdout | output_file | event | parser_accumulator
```

Manifest rule:

- Keep the current non-streaming `invoke` path.
- Add `streaming.args` only for workers with a verified stream mode.
- Setup/Doctor reports stream capability separately from readiness.
- A source can be ready but not stream-capable.

## CLI Evaluation

Evaluated on 2026-06-19 from installed CLI help plus current driver manifests.

| Source | Current invoke | Stream mode found | V1 posture |
| --- | --- | --- | --- |
| Codex | `codex exec ... -o {{outputFile}} {{prompt}}` | `codex exec --json` prints JSONL events to stdout. | Supported after parser as completed-message snapshots, not token deltas. Keep `-o {{outputFile}}` for canonical final answer; parse JSONL stdout for `agent_message` snapshots/status/tool activity. |
| Claude Code | `claude -p {{prompt}} --model {{model}}` | `claude -p --output-format stream-json`; help also exposes `--include-partial-messages`. | Supported after parser. Use `--output-format stream-json --include-partial-messages`; parse only assistant text deltas into visible answer. |
| Cursor Agent | `agent -p --output-format text ...` | `agent -p --output-format stream-json`; help also exposes `--stream-partial-output`. | Supported after parser. Use `--output-format stream-json --stream-partial-output`; parse text deltas. |
| Grok Build | `grok -p {{prompt}} ... --output-format plain` | Help exposes `--output-format streaming-json` for headless mode. | Likely supported after parser. Verify event schema with a tiny real run before claiming product support. |
| Antigravity | `agy --print {{prompt}} ...` | Current `agy --help` shows no structured output/stream flag. | Not V1 stream-capable unless the CLI confirms a hidden or newer stream mode. Final-output fallback only. |
| Manual paste | no process | none | Not applicable. |

### Codex Parser

Invocation candidate:

```text
codex exec --json --skip-git-repo-check --color never -m {{model}}
  {{effortArgs}} -o {{outputFile}} {{prompt}}
```

Parser requirements:

- Treat stdout as JSONL.
- Buffer by newline; ignore empty lines.
- Parse every JSON object into a raw audit event.
- Visible assistant answer text is a completed message snapshot at
  `$.type == "item.completed"`, `$.item.type == "agent_message"`, and
  `$.item.text`.
- `$.item.text` is a full completed message snapshot, not an incremental delta.
  Store by `$.item.id` and do not render the same item twice.
- `codex exec --json` does not expose token-by-token visible text deltas; internal
  `item/agentMessage/delta` belongs to the app-server protocol, not this JSONL
  stream.
- Do not render reasoning, `command_execution.aggregated_output`,
  `mcp_tool_call.result`, `web_search`, `file_change`, `todo_list`, top-level
  `error`, `turn.failed.error`, or item `type: "error"` as chat answer text.
- Successful terminal event is `turn.completed`, followed by process exit `0`.
- Failure terminal event is `turn.failed` with `error.message`, or top-level
  `error` followed by failed/interrupted turn handling. Current fatal/failed
  paths exit non-zero, specifically `1`.
- Per-tool command exit codes may appear at
  `$.item.type == "command_execution"` / `$.item.exit_code`; they are not the
  Codex process exit code.
- On process exit, prefer `{{outputFile}}` for canonical final answer exactly as
  today. Do not append the file to already-rendered `agent_message` text unless
  repairing a missing stream.

Tiny verified sequence:

```json
{"type":"thread.started","thread_id":"0199a213-81c0-7800-8aa1-bbab2a035a53"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"OK"}}
{"type":"turn.completed","usage":{"input_tokens":120,"cached_input_tokens":0,"output_tokens":3,"reasoning_output_tokens":0}}
```

### Claude Code Parser

Invocation candidate:

```text
claude -p {{prompt}} --model {{model}} {{effortArgs}}
  --output-format stream-json --include-partial-messages
```

Parser requirements:

- Treat stdout as JSONL.
- Extract only assistant message content intended for the user.
- Ignore hook events unless a future debug surface opts in.
- Handle partial-message chunks and final message events without duplicating text.
- Final answer can come from parser accumulator or a terminal result event.

Need from CLI if parser cannot be derived safely:

```text
Please provide the `claude -p --output-format stream-json --include-partial-messages`
event schema. Which event types and fields are visible assistant text deltas,
which are complete assistant messages, and how should clients dedupe partials
against final messages?
```

### Cursor Agent Parser

Invocation candidate:

```text
agent -p --output-format stream-json --stream-partial-output
  --model {{model}} --trust --workspace {{workingDir}} {{prompt}}
```

Parser requirements:

- Treat stdout as JSONL.
- Extract streamed partial output as visible text deltas.
- Do not render tool-call details as answer text.
- Handle sessions that emit a final JSON object after partials without
  duplicating the final answer.

Need from CLI if parser cannot be derived safely:

```text
Please provide the Cursor Agent `--output-format stream-json --stream-partial-output`
event schema. Which fields carry visible text deltas, which events describe tool
activity, and how should clients dedupe partial text from the final result?
```

### Grok Parser

Invocation candidate:

```text
grok -p {{prompt}} -m {{model}} --output-format streaming-json
```

Parser requirements:

- Verify the exact spelling and whether `-p`/`--single` is the required headless
  mode for `streaming-json`.
- Treat stdout as JSONL only after a real smoke run proves line-delimited JSON.
- Extract visible assistant output only; keep reasoning/tool events out of chat.

Need from CLI before implementation claim:

```text
Please provide the Grok Build `--output-format streaming-json` event schema and
a one-prompt sample. Which event types/fields are visible assistant text deltas,
which are reasoning/tool events, and what terminal event marks completion?
```

### Antigravity Parser

No V1 parser until the CLI exposes a stream mode.

Need from CLI:

```text
Does `agy --print` support a streaming or JSONL output mode? If yes, provide the
exact flags, event schema, answer-delta fields, terminal event, and whether the
final answer is also emitted as a complete message.
```

## Implementation Slices

- [ ] STR-S01 - Add `CommandEvent` + `StreamingCommandRunner` protocol and tests.
- [ ] STR-S02 - Implement streaming in `SubprocessCommandRunner` with shared
      launch/kill/timeout behavior.
- [ ] STR-S03 - Add `WorkerStreamEvent` and `WorkerRunner.invokeStreaming`.
- [ ] STR-S04 - Add one real parser first, preferably Claude or Cursor because
      both advertise partial-message flags.
- [ ] STR-S05 - Persist throttled partial text onto the running `worker_chat`
      turn with a 64 KB cap.
- [ ] STR-S06 - Wire `ThreadSendCoordinator.completeSend` to use streaming when
      the selected driver supports it, falling back to `invoke`.
- [ ] STR-S07 - Render running worker turn text live in the Mac timeline.
- [ ] STR-S08 - Add Codex parser while preserving output-file final capture.
- [ ] STR-S09 - Add Cursor/Claude/Grok parsers as their schemas are verified.
- [ ] STR-S10 - Add Doctor/Setup capability copy: ready vs streams live.
- [ ] STR-S11 - Decide whether CLI/MCP thread send needs `--stream` parity in V1
      or can wait until Mac chat proves the engine path.

## Team Streaming V2

V2 can reuse V1 but must not be folded into it.

Possible V2 surface:

```text
Team answer panel shows every worker as thinking/writing independently.
Each worker row streams its visible answer deltas.
The final plan still lands only after synthesis.
```

Additional V2 work:

- Worker-scoped stream multiplexing in `TeamService`/`CatalogRunCoordinator`.
- Public NDJSON additions for answer deltas.
- Per-worker partial persistence in `TeamRun` or sidecar journal.
- Synthesis stage streaming policy.
- UI grouping so multiple workers writing at once feels legible, not chaotic.

## Privacy And Safety

- Partial chunks are as sensitive as final answers.
- Store locally only.
- Do not send partial chunks to iOS, MCP clients, or external services in V1.
- Redact nothing silently.
- Reasoning events are not visible answer text.
- Cancelling kills the process group and preserves partial output.
- If a cancelled/failed turn ran in a Project working directory, the UI may warn
  that the workspace may have changed.
- Destructive cleanup remains out of scope.

## Works Test

Minimum manual Works Test before product claim:

```text
Pick one verified streaming-capable worker on Mac. Send a Project Manager chat
turn. The user turn saves immediately, the worker turn starts running, visible
partial text appears before process exit, cancel preserves partial text, and a
successful run replaces/settles with the complete normalized final answer.
Repeat with a non-streaming worker; it shows honest running state and lands the
full reply on completion.
```

Real-driver proof must name:

- source id;
- CLI version;
- exact invocation flags;
- sample event names seen;
- which event/field became visible answer text;
- whether final output duplicated partials;
- whether cancellation preserved partial text.

## Proof Commands

```text
swift test --package-path Packages/AllnighterCore
bash scripts/check.sh
```

Focused tests for implementation:

- streaming command runner emits chunks before completion;
- timeout/cancel still kill the process group and produce partial buffers;
- each parser extracts answer deltas without rendering reasoning/tool events;
- parser dedupe prevents final-message duplication;
- `ThreadSendCoordinator` falls back cleanly for `streaming.supported == false`;
- partial persistence is throttled and capped;
- final settlement preserves current success/failure semantics.

## Done When

- At least one real CLI streams visible chat text before exit in the Mac app.
- Non-streaming workers still work exactly as before.
- Partial text survives cancellation/failure.
- Final text matches the complete normalized CLI result.
- Setup/Doctor can report stream capability without confusing it with readiness.
- Product docs claim only the sources actually proven.
