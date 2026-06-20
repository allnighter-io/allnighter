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
| Claude Code | `claude -p {{prompt}} --model {{model}}` | `claude -p --output-format stream-json`; real CLI v2.1.183 sample requires `--verbose` and `--include-partial-messages` for text deltas. | Supported after parser with true incremental `text_delta` output. Use `--output-format stream-json --include-partial-messages --verbose`; parse only assistant text deltas into visible answer. |
| Cursor Agent | `agent -p --output-format text ...` | `agent -p --output-format stream-json`; live runs confirm `--stream-partial-output` emits character-level assistant deltas plus duplicate flushes. | Supported after parser with true incremental assistant deltas. Use `--output-format stream-json --stream-partial-output`; append only delta-form assistant events and reconcile with `result.result`. |
| Grok Build | `grok -p {{prompt}} ... --output-format streaming-json` | Local docs and live captures confirm `text` / `thought` / `end` / `error` NDJSON. | Supported after parser with true incremental `text.data` output. Current runtime extracts final visible text after process exit; live UI updates still require the V1 streaming runner. |
| Antigravity | `agy --print {{prompt}} ...` | Antigravity CLI answer confirms no streaming, JSONL, or machine-readable event mode in current `agy --print` / `agy -p`. | Not V1 stream-capable. Final-output fallback only; stdout is clean final answer text, logs/errors go to stderr or Antigravity logs. |
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
  --output-format stream-json --include-partial-messages --verbose
  --permission-mode bypassPermissions
```

Parser requirements:

- Treat stdout as JSONL.
- `-p` + `--output-format stream-json` requires `--verbose` on Claude Code
  v2.1.183; without it the CLI hard-errors.
- `--include-partial-messages` enables streaming deltas. Without it, the stream
  includes only final messages.
- Permission-safe headless runs should use `--permission-mode bypassPermissions`
  or `--dangerously-skip-permissions` so tool prompts cannot block the run.
- Consider `--bare` for clean scripted calls when Allnighter does not want hooks,
  skills, plugins, `CLAUDE.md`, MCP auto-discovery, or keychain reads.
- Visible live text deltas are at
  `$.type == "stream_event"`, `$.event.type == "content_block_delta"`,
  `$.event.delta.type == "text_delta"`, then `$.event.delta.text`.
- Bucket streamed text by `$.event.index`; concatenate `text_delta.text` in
  order per content block.
- Final visible snapshots are at `$.type == "assistant"` and
  `$.message.content[i].type == "text"` / `$.message.content[i].text`.
- `$.type == "result"` includes terminal summary, usage, cost, and a full
  `$.result` snapshot.
- Dedupe strategy: stream `text_delta` into the running turn, then suppress the
  later `assistant`/`result` snapshots for rendering. Use them only to reconcile
  or repair missing stream text.
- Do not render as chat answer text: `content_block_start`,
  `content_block_stop`, `message_start`, `message_delta`, `message_stop`,
  `input_json_delta`, `signature_delta`, thinking blocks, `user` tool-result
  events, `system.*`, or `rate_limit_event`.
- Tool input appears as `$.event.delta.type == "input_json_delta"` with
  `$.event.delta.partial_json`; accumulate/parse for tool UI only, not answer
  text.
- Terminal event is always one final `$.type == "result"`. Success uses
  `subtype: "success"`, `is_error: false`, and `terminal_reason: "completed"`.
- Handled API errors may still exit `0`; rely on the in-band `result` event
  (`subtype: "error"`, `is_error: true`, `api_error_status`, `result`) for
  run-truth failure. Reserve non-zero exit handling for startup/invocation errors
  such as bad flags or auth failures before `system/init`.
- Retryable API failures emit `system` / `subtype: "api_retry"` events before
  retry or terminal error.
- Claude answer reported no per-call effort flag despite current local help and
  the manifest exposing `--effort`; verify on the target CLI version before
  changing effort mapping.

Tiny verified sequence:

```json
{"type":"system","subtype":"init","session_id":"ee6f...","model":"claude-opus-4-8[1m]","permissionMode":"bypassPermissions","tools":["Bash","Read","Edit"],"claude_code_version":"2.1.183","uuid":"..."}
{"type":"system","subtype":"status","status":"requesting","session_id":"ee6f...","uuid":"..."}
{"type":"stream_event","event":{"type":"message_start","message":{"id":"msg_019...","role":"assistant","content":[],"stop_reason":null,"usage":{"input_tokens":2655,"output_tokens":3}}},"ttft_ms":1136,"uuid":"..."}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"uuid":"..."}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}},"uuid":"..."}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"! What can I help with today?"}},"uuid":"..."}
{"type":"assistant","message":{"id":"msg_019...","role":"assistant","content":[{"type":"text","text":"Hi! What can I help with today?"}],"stop_reason":"end_turn","usage":{"input_tokens":2655,"output_tokens":18}},"request_id":"req_...","uuid":"..."}
{"type":"stream_event","event":{"type":"message_stop"},"uuid":"..."}
{"type":"result","subtype":"success","is_error":false,"duration_ms":1504,"ttft_ms":1439,"num_turns":1,"result":"Hi! What can I help with today?","stop_reason":"end_turn","total_cost_usd":0.087828,"usage":{"input_tokens":2655,"output_tokens":18,"cache_read_input_tokens":15626},"terminal_reason":"completed","uuid":"..."}
```

### Cursor Agent Parser

Invocation candidate:

```text
agent -p --output-format stream-json --stream-partial-output
  --model {{model}} --trust --workspace {{workingDir}} {{prompt}}
```

Parser requirements:

- Treat stdout as JSONL.
- Recommended headless invocation is `agent -p --output-format stream-json
  --stream-partial-output --model {{model}} --trust --workspace {{workingDir}}
  {{prompt}}`.
- `--trust` auto-trusts the workspace in headless mode; `--force`/`--yolo`
  auto-allow shell commands and are separate from trust.
- `--approve-mcps` auto-approves MCP servers when needed.
- Event types seen/expected: `system` / `subtype: "init"` for session metadata,
  `user` for prompt echo, `assistant` for visible text/delta/flush events,
  `tool_call` / `subtype: "started"|"completed"` for tool activity, `result` /
  `subtype: "success"` for terminal success. Official docs say `thinking` is
  suppressed in print mode.
- Visible assistant text path is `$.message.content[*].text` where
  `$.message.content[*].type == "text"`.
- With `--stream-partial-output`, append only `$.type == "assistant"` events
  where `$.timestamp_ms` is present and `$.model_call_id` is absent. These are
  small incremental deltas, not growing prefixes.
- Skip `assistant` events where `$.timestamp_ms` and `$.model_call_id` are both
  present; live/forum evidence classifies these as duplicate buffered flushes
  before tool calls.
- Skip `assistant` events where `$.timestamp_ms` is absent; these are duplicate
  full end-of-turn flushes when partial output is enabled.
- Without `--stream-partial-output`, `assistant` events at the same text path are
  full message segments between tool calls, not deltas.
- Canonical final answer is `$.type == "result"` / `$.result`; it concatenates
  all assistant segments across the run, including text before and after tool
  calls.
- Dedupe strategy: stream delta-form `assistant` events into the running turn,
  skip duplicate flushes, then use `result.result` to verify/replace/repair the
  accumulated text at terminal settlement. Do not append `result.result` as one
  more delta.
- Do not render as chat answer text: `system`, `user`, `tool_call` started or
  completed payloads, `thinking`, `result` as a delta, `assistant` duplicate
  flushes, or tool-result payloads such as
  `tool_call.readToolCall.result.success.content`.
- Success terminal event is `$.type == "result"`, `$.subtype == "success"`,
  `$.is_error == false`, with `duration_ms`, `duration_api_ms`, `session_id`,
  optional `request_id`, and `usage` fields such as `inputTokens`,
  `outputTokens`, `cacheReadTokens`, and `cacheWriteTokens`.
- There is no documented guaranteed in-band stream error event. Startup/auth/flag
  errors and run failures exit non-zero, usually `1`, write to stderr, and may
  end the stream without a `result` event. Treat missing terminal `result` plus
  non-zero exit as failure.
- `call_id` correlates `tool_call` started/completed pairs. `session_id` is
  stable for the whole run.

Tiny verified sequence:

```json
{"type":"system","subtype":"init","apiKeySource":"login","cwd":"/Users/mike/Documents/GitHub/Allnighter","session_id":"33e43ce1-14de-4f70-9676-d49007e36ac6","model":"Composer 2.5","permissionMode":"default"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Count from 1 to 3, one per line."}]},"session_id":"33e43ce1-14de-4f70-9676-d49007e36ac6"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"1"}]},"session_id":"33e43ce1-14de-4f70-9676-d49007e36ac6","timestamp_ms":1781919755021}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"\n"}]},"session_id":"33e43ce1-14de-4f70-9676-d49007e36ac6","timestamp_ms":1781919755024}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"2"}]},"session_id":"33e43ce1-14de-4f70-9676-d49007e36ac6","timestamp_ms":1781919755024}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"\n"}]},"session_id":"33e43ce1-14de-4f70-9676-d49007e36ac6","timestamp_ms":1781919755024}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"3"}]},"session_id":"33e43ce1-14de-4f70-9676-d49007e36ac6","timestamp_ms":1781919755025}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"1\n2\n3"}]},"session_id":"33e43ce1-14de-4f70-9676-d49007e36ac6"}
{"type":"result","subtype":"success","duration_ms":3467,"duration_api_ms":3467,"is_error":false,"result":"1\n2\n3","session_id":"33e43ce1-14de-4f70-9676-d49007e36ac6","request_id":"28f2e6bd-623b-4f0f-9451-629817984d30","usage":{"inputTokens":28481,"outputTokens":36,"cacheReadTokens":1161,"cacheWriteTokens":0}}
```

### Grok Parser

Invocation candidate:

```text
grok -p {{prompt}} -m {{model}} --output-format streaming-json
  --cwd {{workingDir}} --always-approve --no-wait-for-background
  --no-subagents --disable-web-search
```

Parser requirements:

- Primary headless form is top-level `grok -p` / `grok --single <PROMPT>`, not
  `grok agent`.
- Treat stdout as JSONL.
- Visible live text deltas are at `$.type == "text"` / `$.data`. These are
  incremental deltas, not snapshots; concatenate in arrival order.
- Reasoning is `$.type == "thought"` / `$.data`; never render as chat answer
  text.
- Success terminal event is `$.type == "end"` with metadata such as
  `stopReason`, `sessionId`, and `requestId`. No full assistant message is
  repeated in the stream.
- Error event is `$.type == "error"` / `$.message`; also handle non-zero process
  exits.
- Treat `max_turns_reached`, `auto_compact_*`, and unknown event types as
  non-answer events.
- Tool calls/results are not surfaced in this `streaming-json` envelope; use ACP
  (`grok agent stdio`) later if Allnighter needs live tool visibility.
- Exit codes observed/documented for headless: `0` normal completion, `1` error,
  `130` SIGINT, `143` SIGTERM.
- Current Allnighter runtime uses this schema only to extract Grok's final
  visible answer after process exit. True live chat updates still require
  `StreamingCommandRunner` / `WorkerStreamEvent`.

Tiny verified sequence:

```json
{"type":"thought","data":"The"}
{"type":"thought","data":" user asked for one word.\n"}
{"type":"text","data":"P"}
{"type":"text","data":"ONG"}
{"type":"end","stopReason":"EndTurn","sessionId":"019ee2bf-...","requestId":"1e6a7982-..."}
```

Full Grok reference: `docs/phases/setup/Grok_Build_CLI_Support.md`.

### Antigravity Parser

No V1 parser until the CLI exposes a stream mode. Current Antigravity answer
confirms `agy --print` / `agy -p` has no token streaming, JSONL, or structured
event output.

Fallback invocation:

```text
agy --print {{prompt}} --model {{model}} --dangerously-skip-permissions
```

Optional flags:

- `--print-timeout <duration>` for longer headless runs; default is currently
  `5m0s`, and image generation uses `10m` in the manifest.
- `--add-dir <path>` when the run needs additional context outside the workspace.

Parser/runtime requirements:

- Treat stdout as the final answer text, not an event stream.
- Keep `stripAnsi: true`.
- Diagnostics, warnings, and errors are expected on stderr or in Antigravity's
  persistent logs, defaulting under `~/.gemini/antigravity-cli/logs` unless
  `--log-file` overrides it.
- Terminal signal is process exit. Non-zero exit means failure; error context is
  stderr/log output.
- Product capability should say "final answer only" rather than "streams live."

Full Antigravity reference: `docs/phases/setup/Antigravity_CLI_Support.md`.

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
