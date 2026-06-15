# 03 - Mac Streaming

Status: Fast follow after Work Threads MLP
Owner: AllnighterEngine + Mac app backend
Updated: 2026-06-15

## Goal

Make chat and long-running turns feel alive on Mac by streaming output when a
driver can expose it.

Streaming is not required for the thread MLP. It is the first feel upgrade after
the async thread spine works.

## User-Visible Claim

```text
When a worker supports live output, Allnighter shows the reply as it arrives.
When it does not, Allnighter still shows an honest running turn and lands the
full reply on completion.
```

## Scope

Mac first. iOS does not need token streaming for this phase.

iOS can continue to show:

```text
sent -> running -> reply landed
```

and later subscribe to completion / partial snapshots once the remote event
spine can carry them safely.

## Non-Goals

- No fake streaming.
- No requirement that every driver stream.
- No mobile streaming requirement.
- No parsing provider usage from stream text in this phase.
- No changing `TeamRun`/`ThreadTurn` ownership. Current code may still say
  `TeamRun` until the vocabulary cleanup lands.
- No token-per-second charts or fake telemetry unless the driver reports exact
  values as structured events.
- No inline discard/reset of workspace changes after cancellation.

## Capability Model

Add driver capability, not global behavior:

```text
DriverStreaming
- mode: none | stdout | stderr | output_file_tail | pty
- flushPolicy: line | chunk | final_only
- stripAnsi: Bool
- partialOutputCapBytes
```

Suggested placement: extend driver manifests only after one real CLI proves the
shape. Until then, keep the engine seam small.

## Engine Impact

Add a streaming command path beside existing request/response:

```text
StreamingCommandRunner.run(...)
  -> AsyncStream<CommandEvent>
```

```text
CommandEvent
- started
- outputChunk(text, stream)
- completed(CommandResult)
- failed(reason)
- timedOut(partialText)
- cancelled(partialText)
```

Rules:

- Existing `CommandRunner.run` remains for non-streaming drivers.
- `WorkerRunner.invoke` can keep returning final `WorkerRunOutcome`.
- A new coordinator path persists partial text onto the running turn.
- Final text is normalized the same way as non-streaming output.
- Partial output is capped and can be truncated; full transcript may stream to a
  local file if needed.

## Mac App Impact

- Running worker turns update their body as chunks arrive.
- A small "live" state is acceptable; no progress percent.
- Rendered Markdown is the default final view. A raw-output view is useful for
  debugging only when the driver exposes raw stdout/stderr separately.
- Cancel remains available.
- If streaming fails mid-run but the process completes, keep the final answer.
- If the process fails, preserve partial text with the failure state.

## Cancellation And Dirty Workspaces

Streaming can make cancellation feel instantaneous, but it does not make
executor side effects reversible.

Rules:

- Cancelling kills the subprocess and preserves partial output.
- If the turn ran in a `workingDir`, the cancelled/failed turn may say:
  "This workspace may have changed."
- Safe affordances are allowed: reveal working directory, open/view diff when
  available, copy cleanup guidance.
- Destructive affordances such as `git reset`, discard changes, or delete files
  are out of scope for this phase. They belong to a later managed-execution
  safety phase with explicit confirmation and proof.

## Privacy

Partial chunks are the same sensitivity as final output.

- Store locally.
- Do not upload by default.
- Redact nothing silently.
- If mobile later receives partials, it must follow the iOS E2E content rules.

## Ordered Slices

- [ ] STR-S01 - Prototype streaming with one real Mac driver.
- [ ] STR-S02 - Add `StreamingCommandRunner` + `CommandEvent` tests.
- [ ] STR-S03 - Add driver streaming capability metadata.
- [ ] STR-S04 - Thread turn partial-output persistence with cap/truncation.
- [ ] STR-S05 - Mac timeline live rendering.
- [ ] STR-S06 - Fallback path: non-streaming drivers still use async MLP behavior.
- [ ] STR-S07 - Evaluate iOS partial snapshots after remote spine exists.

## Works Test

```text
Pick one streaming-capable worker on Mac. Send a chat turn. The user turn saves
immediately, the worker turn starts running, partial text appears before process
exit, cancel preserves partial text, and final output matches the command's
completed result. Repeat with a non-streaming worker; the UI shows honest running
state and lands the full reply on completion.
```

## Proof Command

```text
swift test
scripts/check.sh
```

At least one real-driver manual Works Test is required before claiming streaming
support in product copy.
