# Run Latency And Streaming Recovery

Status: **CODE RED PERF PRIORITY** - draft recovery phase
Owner: AllnighterCore + AllnighterEngine + AllnighterMac
Updated: 2026-06-21

Founder intent:

```text
Allnighter is currently a 2/10 for the core loop: startup too slow, response too
slow, streaming too slow, and the UI becomes unusable while a worker answers.
This makes the product feel dead even when the underlying worker eventually
returns a good answer.
```

Product value:

```text
Default chat must feel like a live local control bench for the CLIs the user
already pays for. Allnighter may be limited by the selected worker's real model
time, but it must not add mysterious startup delay, stream backpressure, stuck
running state, or scroll jank.
```

Trusted workflow slice:

```text
In a Project thread, send one default chat turn to one stream-capable worker
from the composer. The turn should appear immediately, show honest lifecycle
state, stream visible answer text when the worker emits it, remain scrollable
while streaming, and settle to durable done/failed/cancelled truth when the
process terminates.
```

Non-goals:

- No fake progress text, fake token streaming, or post-exit replay marketed as
  live streaming.
- No rewrite of the Unified Run Model. Chat remains a run in the repo root.
- No storage migration as the first move. SQLite/GRDB is a later measured answer,
  not a substitute for fixing per-delta app-wide work.
- No hidden cloud coordinator, entitlement change, credential change, or macOS
  permission posture change.
- No hiding failed workers or replacing sourced failure with optimistic UI.
- No broad redesign of team selection, model catalogs, or Project semantics.

## Relationship To Existing Docs

This is the umbrella recovery phase for the current dogfood failure.

- `threads/03_Mac_Streaming.md` owns the original streaming architecture and
  driver contracts.
- `Team_Run_Load_Performance.md` owns the earlier Team-run open stall and the
  broader thread/read-model performance work.
- `Unified_Run_Model.md` owns the rule that default chat is a run in the repo
  root, not a separate lightweight chat product.
- `Live_Team_Board.md` owns team-run live board behavior after the single-worker
  path is proven.

This doc does not replace those contracts. It promotes the new finding: the
single-worker default-chat streaming loop is now the product's top survival
path.

## Dogfood Evidence

Observed on 2026-06-21 from a Composer-family default chat run:

```text
Run:
~/Library/Application Support/Allnighter/Runs/run_A2FF47FF-A1BF-4563-BA74-009E5E34F5CE/run.json

Thread:
~/Library/Application Support/Allnighter/Threads/thread_B283D7A7-3B19-4FCE-981D-E088AFFB0FDF/thread.json

Model id: model_composer
Display: Grok Composer 2.5 Fast
Command model flag: grok-composer-2.5-fast
Run start: 2026-06-21T17:32:33Z
First visible answer text: about 2026-06-21T17:33:03Z
Terminal outcome: 2026-06-21T17:35:22Z
Wall duration: about 168s
Final output length: 7706 chars
Context packet: about 14.7 KB, 8 prior turns, 1 included file reference
Raw stdout log lines: about 2305
Parsed answer deltas: about 1887
Parsed reasoning deltas: about 448
```

The run artifact says the worker completed successfully, but the linked thread
turn still persisted as `running` with partial answer text and large reasoning
text. That is the correctness bug behind the user's "it is still answering"
experience.

There were also startup stderr warnings about invalid MCP tool names from
`clawwidget-builder`. They are probably not the main runtime cost, but they are
startup-path noise and proof that every run can still pay for stale/broken tool
configuration.

## Current State

What works:

- The worker can emit real structured stream events.
- `RunService` can accumulate answer and reasoning deltas and write a terminal
  run artifact.
- The Mac app can show live answer text in the selected thread.
- Earlier Team-run open work reduced terminal run decode/render stalls.

What is broken or too fragile:

- A terminal run can leave the visible thread turn stuck in `running`.
- Final `ThreadStore.updateTurn` failures are swallowed in the Mac view model.
- The app logs full prompt args and every raw/parsed stream event by default.
- Stream debug logging performs synchronous open/seek/write/close work per log
  call.
- The selected thread publishes live accumulated text through broad observable
  state.
- Reasoning text can grow and render by default on the latest running turn.
- The timeline uses non-lazy row layout plus per-turn geometry preferences while
  the live row height is changing.
- Text selection and growing `Text` layout make the live row expensive.
- The UI has no clear startup timing ladder: context build, worker resolution,
  spawn, first stdout, first parsed answer, first visible render, terminal, and
  settlement are not surfaced as separate facts.
- The model identity can be confusing: "Composer 2.5 Fast" may mean Cursor
  Composer in one context and Grok Composer in another. Performance expectations
  are impossible to reason about if source/model identity is blurry.

## Truth Owner

Terminal worker/run truth:

```text
RunStore / TeamRun / WorkerRunOutcome
```

Visible conversation truth:

```text
ThreadStore / WorkThread / ThreadTurn
```

Live in-memory rendering truth:

```text
Selected turn live overlay, keyed by threadId + turnId + workerId
```

The terminal rule:

```text
When a linked run reaches a terminal state, the visible thread turn must reach
the matching terminal state or expose a hard settlement error. A completed run
and a permanently running thread turn is illegal.
```

## Lie-Prone Layers

- Mac view model settlement code that turns `RunService` results into
  `ThreadTurn` state.
- Broad SwiftUI observation where one live answer update invalidates unrelated
  rail, search, unread, or geometry work.
- Debug logging that is treated as harmless while sitting on the hot stream
  path.
- Parser/debug code that preserves raw reasoning and tool events without a clear
  product rendering policy.
- Context building that can silently make a "simple chat" into a large repo/doc
  prompt.
- Driver setup that allows broken MCP/tool configuration to emit warnings on
  every run.

## New Semantic Rules

- Startup, live activity, visible answer text, and terminal settlement are
  different product states. Do not collapse them into one vague `running`.
- A stream delta is not durable conversation truth. It is live UI state until a
  throttled checkpoint or terminal settlement.
- Terminal settlement failures are product failures, not debug trivia. They must
  be logged and surfaced.
- Raw provider events are not UI. Only parsed answer deltas may become visible
  answer text by default.
- Reasoning is audit/debug by default unless a separate product decision makes
  it visible. A running turn must not auto-render unbounded reasoning text.
- Debug logs must be opt-in, bounded, rotated, and redacted. Full prompt text,
  full reasoning, and every stream token do not belong in default logs.
- The GUI must render bounded snapshots. It must not scan, decode, lay out, or
  recompute app-wide state per stream event.
- Source identity must be explicit in diagnostics and disambiguated in UI where
  users compare workers.

## Product Bar

These are Allnighter overhead gates, not promises about a provider's model
speed.

```text
Composer send accepted:
  User turn and running worker turn appear immediately.

Worker startup:
  Context build, worker resolve, command spawn, first stderr/stdout, first parsed
  answer, first UI render, terminal, and settlement are timestamped.

Live streaming:
  Provider-emitted answer text reaches the selected visible turn without a full
  thread-list reload or full thread-file rewrite per delta.

Scroll while streaming:
  The user can scroll up and down smoothly while answer and/or activity state
  changes.

Terminal:
  The thread turn settles to done/failed/cancelled promptly after the terminal
  worker outcome. No spinner may survive a terminal run.
```

## Recovery Strategy

Fix in this order:

1. Prove the timeline.
2. Fix terminal settlement correctness.
3. Remove debug I/O from the hot stream path.
4. Isolate live stream rendering from app-wide state.
5. Make scrolling and text layout bounded.
6. Reduce startup/context/driver overhead.
7. Add hard perf gates so the 2/10 path cannot regress quietly.

Do not start with a database migration. If a live delta still publishes a giant
observable array, renders unbounded text, and recomputes visibility on every
frame, a database only moves the bottleneck.

## Must-Do List

### P0 - Instrument The Run Ladder

Problem:

The user sees "slow" but Allnighter cannot yet separate our overhead from
provider/model time.

Add per-run timestamps for:

```text
composer.submit
thread.userTurn.persisted
thread.workerTurn.persisted
context.build.start/end
context.bytes
context.turnCount
context.fileReferenceCount
worker.resolve.start/end
driver.command.resolved
process.spawn.start/end
first.stderr
first.stdout.chunk
first.parsed.event
first.answer.delta
first.ui.publish
first.visible.render
last.answer.delta
process.exit
run.outcome.persisted
thread.turn.settlement.start/end
thread.turn.settlement.error
```

Counters:

```text
raw stdout chunks
raw stderr chunks
parsed stream events
answer delta count
reasoning delta count
UI publish count
ThreadStore.get count
ThreadStore.updateTurn count
ThreadStore.list count
RunStore.save/load count
debug log write count
timeline geometry preference count
visible-id recompute count
```

Proof:

- A single dogfood run produces a local timing ladder.
- The ladder can say whether delay happened before spawn, before first stdout,
  inside parser, before UI publish, during UI render, or during settlement.

### P0 - Make Terminal Settlement Non-Optional

Problem:

The dogfood run completed, but the thread turn stayed `running`.

Required changes:

- Replace swallowed final settlement writes with explicit error handling.
- Treat illegal run/thread divergence as a bug event.
- On terminal `RunService` result, settle the thread turn from the final worker
  answer and terminal status.
- If thread settlement fails, surface an error state instead of leaving an
  indefinite spinner.
- Ensure late durable checkpoints cannot overwrite a terminal turn back to
  `running`.
- Consider deriving displayed status from linked run truth for mutating/team run
  turns when the run is terminal and thread status is stale.

Proof:

- A streaming `RunService` GUI test drives deltas, emits terminal success, and
  asserts the linked `ThreadTurn` is `.done` with the full final output.
- A checkpoint-race test proves a late checkpoint does not revert `.done`.
- A failure-path test proves settlement errors are logged and visible.

### P0 - Quarantine Stream Debug Logging

Problem:

Default stream logging is on the hot path and logs too much sensitive/local
content.

Required changes:

- Disable full raw stream debug logging by default.
- Never log full prompt args in default logs.
- Never log full reasoning text in default logs.
- Replace per-event synchronous file open/seek/write/close with a bounded async
  log sink when debug capture is explicitly enabled.
- Log counts, sizes, hashes, event kinds, and timing by default.
- Add per-run opt-in raw capture for parser development, with rotation and
  redaction warnings.
- Add a local purge path for stream debug captures.

Proof:

- A stream fixture with thousands of deltas performs zero raw-event file writes
  when debug capture is off.
- With debug capture on, writes are batched/bounded and do not block parsing.

### P0 - Stop Rendering Unbounded Reasoning By Default

Problem:

The latest running turn can accumulate and render large reasoning text while the
answer is also streaming. That is expensive and not part of the original
streaming product claim.

Required changes:

- Hide reasoning by default for default chat streaming.
- Store only bounded reasoning/audit snippets unless explicit debug capture is
  on.
- If a reasoning disclosure remains, show a compact activity summary or line
  count while running.
- Do not auto-expand a full reasoning block just because the turn is latest or
  running.
- Do not let reasoning updates publish at the same cadence as visible answer
  text unless the reasoning panel is explicitly visible.

Proof:

- A stream with reasoning deltas but no visible reasoning panel produces no
  large reasoning `Text` layout while the user scrolls.

### P0 - Isolate The Live Selected Turn

Problem:

Streaming currently mutates broad published state. The selected timeline,
sidebar, unread state, search state, and geometry tracking can all pay for one
growing answer.

Required changes:

- Introduce a selected-turn live overlay keyed by `threadId + turnId + workerId`.
- Publish only the live row snapshot to the selected thread renderer.
- Keep `railRows` and thread list summaries stable unless row-level facts
  actually changed.
- Coalesce visible answer publishes to a display cadence.
- Keep durable checkpoints separate from visual publishes.
- Do not call `ThreadStore.list()` in response to answer deltas.
- Do not rewrite `thread.json` per answer delta.

Proof:

- A 2000-delta fixture produces zero thread-list reloads from answer deltas.
- Rail row snapshots do not republish for every selected-turn text update.

### P0 - Keep Scrolling Interactive During Streaming

Problem:

The timeline is doing layout and geometry work while the live row height changes.

Required changes:

- Use lazy timeline rendering for long threads.
- Avoid `.textSelection(.enabled)` on actively streaming text; enable selection
  after settlement or through an explicit action.
- Render live answer text as bounded plain text while running; render polished
  markdown after settlement.
- Consider a segmented live renderer: immutable completed chunks plus one small
  mutable tail, so every new token does not relayout one giant `Text`.
- Cap visible live text and show a truncation affordance for very long outputs.
- Keep auto-scroll only when the user is already at the bottom. If the user
  scrolls up, do not fight the scroll position.
- Throttle timeline visibility/read-clear work while a live row is changing.
- Do not run per-row geometry preference updates for offscreen rows.
- Recompute visible/read state on scroll idle or throttled cadence, not on every
  frame plus every text-height mutation.

Proof:

- A manual dogfood stream can scroll from bottom to top and back without visible
  stalls.
- A UI/perf fixture emits answer deltas while the timeline scrolls and asserts
  bounded publish/layout/visibility counts.

### P1 - Separate Honest Activity From Answer Text

Problem:

Dead air before first answer text feels like the worker is broken. But fake
progress would destroy trust.

Required changes:

- Show sourced lifecycle states:
  - preparing context
  - resolving worker
  - starting CLI
  - waiting for first output
  - worker emitted stderr
  - worker emitted non-answer event
  - streaming answer
  - settling
- Keep these states compact and factual.
- Do not invent activity. Every state needs an engine event or timestamp.
- If no answer delta has arrived, say that no answer text has arrived yet rather
  than showing fake text.

Proof:

- A driver that emits stderr before answer text shows honest startup activity.
- A non-streaming worker shows running state and final answer without implying
  live token streaming.

### P1 - Build A Direct CLI Baseline Harness

Problem:

Allnighter must know whether it is slower than the vendor CLI for the exact same
prompt, flags, model, environment, and working directory.

Required changes:

- Save the exact prompt packet used for a run.
- Run the selected driver directly with the exact command Allnighter will spawn.
- Capture direct CLI timing:
  - spawn start/end
  - first stdout
  - first parsed answer
  - process exit
  - final output bytes
- Compare Allnighter overhead to direct CLI overhead for the same packet.
- Store the comparison as local proof, not as user-facing model-speed promises.

Proof:

- One Grok Composer fixture shows whether the 23-30s pre-answer delay was
  provider/model/tool time, Allnighter startup overhead, parser delay, or UI
  render delay.

### P1 - Fix Model/Source Identity

Problem:

"Composer 2.5 Fast" is ambiguous across sources. The audit run used
`model_composer` / Grok Composer, not Cursor Agent's Composer model id.

Required changes:

- Make diagnostics always show source id, model id, display name, driver, and
  command model flag.
- In user-visible comparison/debug surfaces, disambiguate source when names
  collide.
- In run artifacts, make selected worker identity easy to inspect without
  reverse-engineering the model catalog.
- In picker UI, avoid identical labels where performance expectations differ.

Proof:

- The run details panel and log ladder clearly identify Grok Composer 2.5 Fast
  vs Cursor Composer 2.5 Fast.

### P1 - Reduce Context Startup Cost

Problem:

A default chat can carry large prior conversation and file-reference context.
That may be correct, but it must be visible, bounded, and measurable.

Required changes:

- Show context packet size in debug/run details.
- Record included turn count, file reference count, and total included bytes.
- Keep explicit file references precise; prefer requested ranges/snippets over
  whole files when the user selected a range.
- Add context budget warnings in debug surfaces when a "simple chat" sends a
  large packet.
- Keep default chat raw and useful, but avoid accidental hidden bulk.
- Add a product decision before creating a separate "fast no-context chat"
  posture, because the Unified Run Model currently says default chat is the
  default team/run in the repo root.

Proof:

- The dogfood run's 14.7 KB packet is visible in the timing ladder and can be
  reproduced.

### P1 - Clean Driver Startup And MCP Tool Hygiene

Problem:

Broken tool names surfaced in every run's startup stderr. Even if cheap, this is
wrong place/time for config cleanup.

Required changes:

- Validate MCP/tool names at setup/doctor time.
- Cache broken tool/server facts so every run does not rediscover the same
  invalid names.
- Keep malformed tools out of the worker's advertised tool set.
- Surface repair steps through doctor/help, not repeated stream stderr.
- Measure driver startup separately from model first-output time.
- Cache CLI path and environment resolution where safe.

Proof:

- The same run no longer emits repeated invalid-tool startup warnings.
- Startup ladder distinguishes command spawn, tool/config warning, and first
  provider output.

### P1 - Harden Parser And Backpressure Boundaries

Problem:

The stream consumer should never block subprocess stdout because it is logging,
publishing UI, or doing durable writes.

Required changes:

- Parse bytes into lines/events with a small bounded parser state.
- Emit semantic deltas into an event channel.
- Do logging, UI publish, and durable checkpoints on separate bounded consumers.
- If the UI falls behind, coalesce visual state rather than blocking stdout
  consumption.
- If debug logging falls behind, drop or summarize debug events rather than
  blocking stdout consumption.
- Preserve complete terminal stdout/stderr buffers for final normalization.

Proof:

- A high-frequency stream fixture cannot make stdout consumption wait on UI
  rendering or debug file writes.

### P1 - Make Checkpoints Safe And Cheap

Problem:

Crash continuity is useful, but a checkpoint must not behave like terminal truth
or trigger app-wide reload.

Required changes:

- Keep an in-memory live overlay as the primary live UI state.
- Checkpoint at a slow cadence or byte boundary.
- Checkpoint only the selected running turn, not the whole thread list.
- Consider a live sidecar if `thread.json` rewrites remain too expensive.
- Terminal settlement replaces checkpoint truth with final normalized output.
- Failed/cancelled turns preserve useful partial output without pretending to be
  done.

Proof:

- A stream can crash/reopen with a recent partial checkpoint.
- A stream can complete with final output even if the last checkpoint is stale.

### P2 - Move Store Reads And Derivations Off The Hot Path

Problem:

Even after the first fixes, large histories and derived state can make live UI
fragile.

Required changes:

- Continue the `Team_Run_Load_Performance.md` read-model work.
- Move full store scans/decodes off MainActor.
- Publish generation-safe snapshots so stale async reads cannot overwrite newer
  live state.
- Keep rail/search/unread derived state versioned and memoized.
- Ensure selected live text updates do not recompute archive rail, project
  sections, pending state, unread lights, or Floor projections.

Proof:

- Perf counters prove live deltas do not increase full-store scan counts.

### P2 - Make The Timeline Renderer Boring

Problem:

Streaming plus scroll is the central on-screen experience. It should be built as
an efficient reader, not a decorative transcript that reflows everything.

Required changes:

- Lazy timeline rows.
- Stable row identity and stable row dimensions where possible.
- Equatable row snapshots for settled turns.
- Separate live row renderer from settled markdown renderer.
- Markdown/syntax parsing only for settled visible content.
- Long answers chunked or virtualized.
- Attachments and tool/activity blocks loaded lazily.
- Per-row geometry only where needed for read-state proof.

Proof:

- A long selected thread with one streaming turn remains usable while scrolling.

### P2 - Add Performance Budgets To CI

Problem:

The app has already regressed into a 2/10 core loop. Subjective dogfood is not
enough.

Required gates:

```text
DefaultRunStreamingSettlementTests
  terminal RunService result settles linked ThreadTurn

DefaultRunStartupTimelineTests
  timing ladder includes context, spawn, first stdout, first answer, UI publish,
  terminal, and settlement

StreamDebugLogTests
  default stream path does not log full prompts or per-token raw events

ThreadStreamingPerformanceTests
  answer deltas do not call ThreadStore.list per delta
  answer deltas do not rewrite thread.json per delta
  railRows do not republish per selected-turn text delta

ThreadTimelineScrollPerformanceTests
  high-frequency streaming plus scroll keeps bounded UI publish/layout counts

ReasoningRenderPolicyTests
  reasoning deltas do not render full reasoning by default

DriverIdentityTests
  source/model/driver identities are unambiguous in diagnostics

DirectCLIBaselineTests
  Allnighter captures a direct-driver timing comparison for the exact command
```

Manual proof:

```text
Use a stream-capable Grok Composer run with the saved dogfood context.
Use a stream-capable Cursor Composer run with an equivalent prompt.
Use a non-streaming/final-output worker.
Send each from the Mac composer.
Scroll aggressively while answer text streams.
Verify no stuck running state after terminal outcome.
Verify the timing ladder explains every visible delay.
Verify default logs do not contain the full prompt/reasoning transcript.
```

### P3 - Consider Resident/Warm Paths Only After The Above

Problem:

Some startup delay may be unavoidable if every run spawns a heavy CLI and loads
its tool/config world from scratch.

Possible later work:

- Resident local broker per source.
- Prewarmed shell/PATH environment.
- Driver-specific persistent session where officially supported.
- Long-lived local MCP server health cache.

High-risk stops:

- Any persistent process that changes session privacy, credentials, permissions,
  or provider billing/quota behavior needs explicit product/security review.
- Do not implement this as a hidden behavior change while the basic stream path
  is still broken.

Proof:

- Only pursue after direct CLI baselines prove process startup is the dominant
  remaining Allnighter-controlled delay.

## Duplicate Truth To Delete

- Thread turn `status` saying `running` after linked run terminal success.
- Default raw stream debug logs acting like a hidden transcript store.
- Full reasoning text persisted/rendered as if it were part of the answer.
- Broad `threads` array as both durable detail model and live stream renderer.
- Repeated tool/MCP startup warnings as a substitute for setup/doctor truth.
- Ambiguous model display names that hide the actual source/driver.

## Implementation Impact

AllnighterCore:

- Add timing/counter structs to run/worker events.
- Harden `RunEvent` terminal guarantees.
- Add fixtures for high-frequency stream events and settlement races.
- Add source/model identity projections.

AllnighterEngine:

- Move raw stream logging off the hot path.
- Bound debug capture.
- Split stdout consumption from UI/log/checkpoint consumers.
- Preserve complete final output while coalescing visual deltas.
- Add direct-driver baseline harness.

AllnighterMac:

- Split selected live turn rendering from broad thread state.
- Stop swallowing terminal settlement errors.
- Hide/bound reasoning by default.
- Throttle or defer visibility/read-clear geometry while streaming.
- Make timeline rendering lazy and live-row specific.
- Add a run details/debug ladder surface.

Driver/protocol:

- Validate stream flags per source.
- Disambiguate model/source identities.
- Move MCP/tool invalid-name repair to setup/doctor.
- Add driver startup timing and first-output timing.

Auth/privacy/permissions:

- No new permissions in this phase.
- Raw stream capture is local, opt-in, redacted/bounded, and purgeable.
- Any resident process or persistent session follow-up requires explicit review.

iOS:

- No iOS streaming work in this phase.
- The Mac remains the run-truth owner. iOS should consume the later stable event
  stream, not invent a parallel streaming protocol.

## Slice Packet

```text
Slice: RLS-S00 timing ladder and dogfood fixture
Goal: Measure every stage from composer submit to terminal settlement.
Out of scope: UI redesign, storage migration.
Truth owner: Run/worker event timeline.
Lie-prone layer: One opaque running state hiding startup/parser/UI/settlement delays.
Works Test: saved dogfood run fixture emits full timing ladder.
Proof command: focused Swift tests plus one manual dogfood run.
Done when: The next slow run can be classified by stage.
```

```text
Slice: RLS-S01 terminal settlement correctness
Goal: A terminal run can never leave its linked thread turn indefinitely running.
Out of scope: scroll optimization.
Truth owner: RunStore terminal outcome + ThreadStore terminal turn state.
Lie-prone layer: Mac view model final settlement and swallowed update errors.
Works Test: streaming RunService GUI settlement test.
Proof command: focused Swift tests.
Done when: completion, failure, cancel, and checkpoint races settle honestly.
```

```text
Slice: RLS-S02 debug logging quarantine
Goal: Remove default prompt/raw-event logging and hot-path debug file I/O.
Out of scope: driver parser rewrite.
Truth owner: bounded run timeline/counters.
Lie-prone layer: StreamDebugLog as hidden transcript and stream bottleneck.
Works Test: high-frequency stream fixture with zero default raw-event writes.
Proof command: focused Swift tests.
Done when: default logs are small, redacted, and non-blocking.
```

```text
Slice: RLS-S03 live selected-turn renderer
Goal: Stream answer text without invalidating app-wide thread/rail state.
Out of scope: all settled-message markdown redesign.
Truth owner: selected live overlay plus terminal ThreadStore settlement.
Lie-prone layer: broad published `threads` array.
Works Test: 2000 deltas produce bounded UI publishes and no thread-list reloads.
Proof command: ThreadStreamingPerformanceTests.
Done when: answer deltas update only the live row and required compact status.
```

```text
Slice: RLS-S04 scroll survival
Goal: The user can scroll smoothly while a long answer streams.
Out of scope: search/index overhaul.
Truth owner: selected timeline renderer.
Lie-prone layer: non-lazy timeline, text selection, growing Text layout, geometry preferences.
Works Test: high-frequency stream plus scroll fixture/manual proof.
Proof command: GUI perf test plus manual dogfood proof.
Done when: streaming no longer makes scrolling feel unusable.
```

```text
Slice: RLS-S05 startup/context/driver diet
Goal: Remove avoidable startup overhead and explain unavoidable worker time.
Out of scope: changing the default run model.
Truth owner: timing ladder + context packet facts + driver identity.
Lie-prone layer: hidden prompt bulk, broken tool startup warnings, ambiguous model names.
Works Test: direct CLI baseline comparison for same command/prompt.
Proof command: focused harness test plus manual direct comparison.
Done when: every pre-answer delay is attributed to context, spawn, provider, parser, or UI.
```

```text
Slice: RLS-S06 hard performance wall
Goal: Prevent regression of the core chat/streaming loop.
Out of scope: broad product feature work.
Truth owner: test counters and dogfood proof packet.
Lie-prone layer: subjective "feels better" claims.
Works Test: CI/focused tests assert settlement, logging, reload, write, and render budgets.
Proof command: `bash scripts/check.sh` once the focused tests exist.
Done when: the phase can only close with counter-backed proof.
```

## Works Test

Primary Works Test:

```text
From the Mac composer, send a default chat to a stream-capable worker using the
saved dogfood prompt/context shape. The worker turn appears immediately, honest
startup activity is shown before answer text, answer text streams when emitted,
the thread remains scrollable, default logs stay bounded/redacted, and the turn
settles to terminal truth when the worker exits.
```

Proof command:

```text
swift test --package-path Packages/AllnighterCore
xcodebuild test -scheme AllnighterMac
```

Until all Mac perf/UI tests exist, closeout must include the missing proof and a
manual dogfood packet with:

```text
run id
thread id
model/source/driver id
context bytes
spawn timing
first stdout timing
first answer timing
first visible render timing
terminal timing
settlement timing
reload count
thread write count
debug log write count
UI publish count
scroll proof notes
```

## Done When

- A completed run cannot leave its thread turn running.
- The dogfood run ladder explains startup delay by stage.
- Default stream logs no longer contain full prompt/reasoning/raw-event dumps.
- Debug logging cannot backpressure stdout parsing.
- Visible answer streaming does not trigger full thread-list reload per delta.
- Visible answer streaming does not rewrite full `thread.json` per delta.
- Reasoning is hidden/bounded unless explicitly opened or debug capture is on.
- The selected timeline remains scrollable while a long answer streams.
- Source/model/driver identity is unambiguous in diagnostics.
- Broken MCP/tool startup warnings are handled by setup/doctor, not rediscovered
  in every default chat run.
- Performance tests and manual dogfood proof cover startup, streaming,
  scrolling, and terminal settlement.

## Open Questions

- Should default chat have a user-visible "context size" affordance in the main
  composer, or only in run details/debug surfaces?
- Should there be a separate explicit "fast no-file-context" posture? This is a
  product decision because default chat currently means the Default Team run in
  the repo root.
- Should visible reasoning ever ship as a product surface, or stay audit/debug
  only?
- Should terminal thread status be stored redundantly, derived from linked run
  state, or both with a consistency repair path?
- When the measured remaining overhead is process startup, is a resident local
  broker acceptable under Allnighter's privacy and permission posture?
