# Persistent Work Threads

Status: Finalized for implementation
Owner: AllnighterCore + AllnighterEngine + Mac app backend
Updated: 2026-06-15

## Product Promise

```text
One thread for one goal — chat, panel, build, review — without leaving
Allnighter or re-explaining yourself.
```

Everything below serves that sentence. The schema follows the story, not the
other way around.

## Founder Intent

Allnighter is missing the thing vibe coders live in all day: a durable chat
thread where they can think with an agent before asking anyone to build.

The current product has strong one-shot primitives:

```text
one prompt -> fan out -> master plan
final spec -> direct dispatch
design prompt -> design board -> build this
```

These are brilliant for the deliberate "run the council" moment. But that moment
is maybe 20% of real AI time. The other 80% is fluid:

```text
chat with one agent
brainstorm / push / refine
ask the panel when the question actually matters
turn the best answer into a work order
dispatch a builder
review the return
keep chatting in the same thread
```

Today that 80% happens in Cursor, Claude Code, Grok, or Codex — outside
Allnighter. As long as the conversational layer lives elsewhere, Allnighter is a
specialized "council launcher," not the ambient workspace where a vibe coder
thinks. This phase makes the durable product unit a **work thread**, not a run.
Runs, design boards, reviews, and dispatches become turns inside one persistent
conversation.

**Key principle: chat is the default surface. Council, design, work order,
dispatch, and review are powerful actions you take from inside the chat — not
modes you switch into.**

## Product Value

User-visible claim:

```text
Allnighter keeps one ongoing thread for a goal. In that thread you chat with one
worker, ask the whole panel when it matters, turn the best answer into a work
order, dispatch a builder, review the result, and keep going — no copy/paste, no
re-explaining, and it's all there when you come back tomorrow.
```

This is not "a nicer chat app." Allnighter does not aggregate provider chat
histories. It owns **local coordination threads** that route to the CLIs the
user already pays for. The reason to stay here instead of bouncing between tools
is that any turn can route to any worker, escalate to a panel, or become
execution while carrying the same local thread context — and the best moments
compound into work orders, picks, and outcomes the rest of the product already
understands.

iOS lede (future, but it shapes the model now): the same thread is continuable
from a phone — read it, send a chat turn, see council results, approve a
dispatch — while the Mac stays the factory. No native CLI app offers that.

## A Day in One Thread

The shape we are building, told as a session — this is the acceptance feel, not
just the schema:

```text
9:10  New thread: "Should notifications be push or pull?"
      -> chat with Grok, 2 turns, no panel, no ceremony
9:40  "ok, ask the panel which approach is simpler to ship"
      -> council run expands inline as a rich turn; scroll position kept
10:05 Pick the master plan -> "turn this into a work order"
      -> work order turn appears, editable, before anything runs
10:08 "Dispatch" (named action, confirmed) -> Codex builds in the thread's repo
13:30 Return review lands as the next turn
      -> "the auth bit feels wrong" -> back to chatting with Claude
      -> same thread, same context, no export/import
Next day: reopen Allnighter -> the thread is intact, composer focused, last
          worker remembered.
```

If worker chat + thread list do not feel good on their own, wrapping council as
turns will not save the phase. Build the feel first.

## Minimum Lovable Phase (MLP)

The honest v1 bar. "Good enough to stop context-switching to Cursor to think,"
not "ChatGPT parity."

| Must feel good in v1 | Explicitly deferred |
| --- | --- |
| Thread survives restart; reopens focused | Token-by-token streaming (substrate is request/response today) |
| Send a follow-up; prior turns are in context automatically | Edit-and-resend beyond the supersede gesture |
| Pick the worker per message, with a sensible default | A/B branch / fork-and-merge lanes |
| User message is saved instantly; worker turn shows running immediately | Auto-harvested facts + conflict detection |
| Markdown + code blocks render; copy works | Rolling summarization of long threads |
| Failure / cancel / manual-paste are visible turns, never silent | IDE focus-sync (reading Cursor/Xcode's active file) |
| One click: "ask the panel" / "turn into work order" from a chat turn | Design board as a first-class thread turn |
| Quote a prior turn into the next prompt | Remote/iOS thread sync |

The MLP is **slices S01–S06**: core models, store, context builder, one-worker
chat, and a minimal Mac chat surface that lives *alongside* the existing council
UI. Everything after that strengthens the loop; nothing after it is required to
prove the wedge.

## Trusted Workflow Slice

```text
create thread (optionally anchored to a working dir)
-> send a brainstorming chat turn to one worker (the thread's default)
-> worker replies; reply is saved as a turn
-> send a follow-up; the context packet includes the earlier user turn and reply
-> "ask the panel" from the same thread; the council run is saved as a turn
-> "turn this into a work order"; an editable work-order turn appears
-> dispatch from the thread; dispatch runs in the thread's working dir
-> return review lands as another turn
-> keep chatting from the returned result
```

## Non-Goals (v1)

- No full Claude/ChatGPT parity.
- No token-by-token streaming in v1 (named as a known gap; see Latency &
  Liveness). The substrate is request/response today.
- No managed repo lane, worktree semantics, or commit magic. A thread's
  `workingDir` is a *context anchor* for chat and a *default cwd* for dispatch —
  nothing more.
- No cloud sync requirement; local-first.
- No provider-native session continuity *requirement*. v1 rebuilds the context
  packet each turn (honest, cross-worker, transcript-as-truth). Riding a vendor's
  native session is a future optimization, never the source of truth.
- No attempt to merge or import vendor chat histories.
- No hidden background execution from casual chat.
- No A/B branching / fork-and-merge lanes in v1.
- No auto-harvested or auto-categorized facts; no rolling summarization.
- No cost, token, or quota theater on turns. Observed duration is honest;
  estimated/echoed token counts and dollar figures are banned by product law.
- No UI visual design in this doc; the designer owns the surface spec. This doc
  owns the *experience contract* (composer behavior, defaults, escalation
  semantics), not pixels.
- No durable product truth living only in SwiftUI state.

## Deferred (named so nobody re-invents them ad hoc)

- **Branching / option lanes.** Forking a thread to try two directions side by
  side and merging the winner fits Allnighter's "option factory" identity, but it
  is a large surface. Revisit after the linear thread proves out.
- **Pinned facts + living scratchpad.** `PinnedThreadFact` and `activeSummary`
  return when threads routinely grow past the context cap. v1 covers the same
  need 80% with recent-turns + quote-a-turn.
- **Design board as a thread turn.** Design is a second escalation lane; ship
  chat + council + dispatch first.

## Current State

Existing truth owners (verified against the code, not assumed):

- `CouncilRun` (`CouncilRun.swift`) is the durable unit for council / design /
  review / dispatch history: prompt + panel seats + member responses +
  append-only `StageOutput`s, with closed status machines.
- `StageOutput` records analysis, plan, reviews, final spec, dispatch, return
  review, and outcome score stages.
- `RunStore` persists runs as folder-of-JSON + derived Markdown.
- `WorkerRunner.invoke` runs one worker CLI once via `CommandRunner` and
  normalizes the result. It already accepts `workingDirectoryOverride` and
  `timeoutOverride` — the hook a thread `workingDir` needs.
- `CommandRunner.run(...) async -> CommandResult` is **request/response**: it
  returns after the process exits. There is no streaming path today. This is the
  single most important constraint on "chat feel" and the reason streaming is a
  named v1 non-goal.
- The Mac app routes a one-shot `ComposeView` to `RunResultsView` /
  `HistoryDetailView` / `DesignBoardView`. There is no message list, no
  multi-turn state, no thread identity. History is a flat list of `CouncilRun`s.

Missing truth:

- No durable thread object.
- No persisted chat turn model.
- No backend contract for "ask one worker in this thread."
- No context packet builder for carrying prior turns into the next worker call.
- No streaming command path (so v1 chat is request/response; see Latency).
- No stable way for a designer to spec a thread/chat surface without inventing
  semantics in UI.

## SSOT

Truth owner: `AllnighterCore` (thread + turn + context-packet semantics).

Storage owner: `AllnighterEngine` (`ThreadStore`, alongside `RunStore`).

UI owner: Mac (and later iOS) render thread truth; they do not invent it.

Lie-prone layers:

- SwiftUI local arrays of messages.
- CLI-native sessions presented as Allnighter truth.
- Prompt prose that includes prior context but is never saved as a turn.
- Run history pretending to be the user's whole conversation.
- A stored thread "running" flag that drifts from actual in-flight turns.
- Future iOS mirrors displaying partial state as complete thread truth.

## Semantic Rules

1. **The durable product unit is a work thread.** A thread represents one ongoing
   user goal.
2. **A run is a turn artifact, not the product unit.** Council runs, design
   boards, review boards, dispatches, and return reviews attach to a thread turn
   and keep their own run/stage truth. Do not bloat `CouncilRun` with chat.
3. **Chat is the default turn.** A user can ask one worker a normal question
   without creating a council run or dispatch.
4. **Routing is per turn.** One thread may use Claude for one turn, Grok for the
   next, the full panel for the next, and Codex for execution.
5. **Enter never builds.** Hitting Enter sends a chat turn to the thread's
   resolved default worker — never a dispatch. Crossing into execution is always
   a named action with an editable work-order preview and confirmation.
6. **Allnighter's transcript is truth.** Vendor-native sessions may exist, but the
   saved Allnighter thread is the durable context future turns use. Vendor
   sessions are an optimization, never the source of truth.
7. **Every worker turn records its assembled context packet.** If Allnighter gave
   prior context to a worker, the exact packet is persisted or reproducibly
   derivable, and the user can reveal it.
8. **Failures are turns too.** A failed reply, cancelled chat, timed-out
   dispatch, or worker-cooling-down hold remains visible with honest status.
9. **Thread liveness is derived, not stored.** Stored thread status is `active`
   or `archived`. "Running" / "needs attention" are computed from the turns, so
   the list badge can never lie.
10. **Chat respects admission control like any other work.** If the chosen worker
    is cooling down or needs sign-in, the turn shows a honest waiting/blocked
    state with the reason — never a silent failure or a faked reply. Casual chat
    does not auto-fan across workers; panel and dispatch may queue.

## Core Model

Truth owner: `AllnighterCore`. Text-block pseudo-types (match existing doc
style; not TypeScript).

```text
WorkThread
- id
- title                  // auto from first user message; user-editable
- status                 // active | archived   (liveness is derived, not stored)
- createdAt
- updatedAt
- pinnedAt?
- workingDir?            // optional project anchor: chat context + dispatch cwd
- projectLabel?          // optional free text for grouping/search ("iOS", "core")
- defaultWorkerId?       // composer personality; resolution ladder if nil
- turns: [ThreadTurn]
// deferred: activeSummary?, pinnedFacts — see Deferred
```

Derived (computed, never stored — Rule 9):

```text
WorkThread.isRunning       = any turn.status in { queued, running }
WorkThread.needsAttention  = any turn.status in { failed, timedOut } OR any turn
                             awaiting manual paste / sign-in
WorkThread.lastWorkerId    = workerId of the most recent worker-authored turn
WorkThread.preview         = trimmed text of the most recent message/reply turn
```

```text
ThreadTurn
- id
- threadId
- kind                   // storage enum, below
- status                 // draft | queued | running | done | failed | timedOut | cancelled
- createdAt
- completedAt?
- author                 // user | worker(workerId) | system
- text?
- workerId?
- runId?                 // council/design/review/dispatch turns reference a CouncilRun
- stageId?               // points into the referenced run's stage when relevant
- artifactRefs: [ArtifactRef]
- contextPacketId?
- supersedesTurnId?      // retry / regenerate / edit-resend (append-only, never mutate)
- seedFromTurnId?        // "continue from this answer" / quoted turn
```

```text
ThreadContextPacket
- id
- threadId
- turnId
- createdAt
- strategy               // recent_turns | explicit_selection   (summary_* deferred)
- includedTurnIds: [ThreadTurn.ID]
- includedRunIds: [CouncilRun.ID]
- includedFiles: [String]   // paths resolved against workingDir; contents capped
- text
- truncated: Bool
- truncationNote?           // user-visible: "included last 12 turns; older omitted"
```

```text
ArtifactRef
- kind     // masterPlan | finalSpec | designBoard | dispatchResult | returnReview | screenshot | file | diff
- runId?
- stageId?
- path?
- excerpt?   // e.g. master-plan excerpt, return-review summary, diff stat
```

Notes:

- `WorkThread.turns` may be denormalized for fixtures; storage can be
  append-only files if easier.
- **Ownership rule (decided — do not bikeshed in S02):** a thread turn references
  the run via `ThreadTurn.runId`. `CouncilRun` is **not** modified — it stays the
  pure run-truth owner of members and stages. Inverse lookup (run -> thread) is a
  store-level index, not authoritative state. This avoids the duplicate-ownership
  bug class.
- A thread title is generated from the first user message but stays editable.
- Retry / regenerate / edit-and-resend never mutate a turn. They append a new
  turn with `supersedesTurnId` set; the UI renders the latest, the transcript
  keeps the history. This is exactly the "routing is per turn" superpower made
  tangible ("regenerate that, but with Grok").

## Turn Kinds and User-Visible Families

Storage kinds stay granular (cheap, precise). The UI collapses them into **four
visible families plus system**, so the timeline never shows eleven card types and
the user never has to know the taxonomy.

| Family (what the user sees) | Storage kinds | Render |
| --- | --- | --- |
| **Message** | `user_message`, `user_decision` | Plain text, right-aligned author=user |
| **Reply** | `worker_chat` | Plain text with worker provenance |
| **Council** | `council_run`, `design_board`, `review_board` | Collapsed summary line; expands in place to member answers + master plan |
| **Build** | `work_order`, `dispatch`, `return_review` | Editable spec / live execution card / returned result |
| **System** | `system_event` | Collapsed by default (migration notes, holds, sign-in prompts) |

`user_decision` is high value and underused elsewhere — it captures "pick option
B", "ship the simpler plan", "reject this return review". Record it as a turn so
the moment a direction was chosen is visible and quotable. (Auto-pinning these is
deferred with the rest of the facts machinery.)

## Composer Contract

The composer is the product. This is semantic behavior the designer and
`AppModel` must implement; visuals belong to the design-system doc.

### Default worker resolution (what answers when I hit Enter)

```text
1. thread.defaultWorkerId, if set
2. else thread.lastWorkerId (most recent worker-authored turn)
3. else the global daily-driver preference
4. else the first healthy headless-CLI worker
```

If none resolve (no healthy worker), the composer says so honestly and offers
Doctor / manual-paste — it does not silently fail.

### Composer state machine

```text
empty thread          -> composing
composing + Enter      -> worker_chat to the resolved default worker
composing + "Ask panel"-> council_run (prompt assembled from recent turns or a quoted turn)
composing + "Design"   -> design_board turn (deferred lane; future)
turn action "Turn into work order" -> work_order turn (editable preview, nothing runs yet)
work_order + "Dispatch" (named, confirmed) -> dispatch turn (runs in thread.workingDir)
dispatch done          -> return_review turn
any turn + "Continue from this" / "Feed result to worker" -> seeds the next worker_chat
```

The composer is always visible at the bottom of a thread. After a council or
build turn completes, the composer returns to chat mode automatically — the
default is always "keep talking."

### Escalation actions (the actual pitch: one-click chat -> panel -> build)

| User action | Turn kind | Context included |
| --- | --- | --- |
| Send (Enter) | `worker_chat` | recent turns + any attached files |
| Ask the panel | `council_run` | recent turns, or a single quoted turn if one is selected |
| Turn into work order | `work_order` | selected turns / accepted master plan |
| Dispatch | `dispatch` | the work-order text + `thread.workingDir` as cwd |
| Continue from result | `worker_chat` | the dispatch/return-review output preloaded into context |

### Guardrails (Rule 5, concrete)

- Build/Dispatch is **never** the Enter action and never fires from a chat turn
  implicitly. It is a named button on an editable work-order turn, with a visible
  preview of what will be sent and where it will run.
- "Continue from this answer" pre-loads a quoted turn into the next chat input;
  it does not auto-send.

## Context Assembly

What the user feels: "Allnighter remembers this thread." What the engine does:
assemble a bounded packet each turn (v1 is stateless at the provider level —
rebuild every turn; do not depend on vendor chat memory for correctness).

V1 packet shape:

```text
Thread: <title>   (workingDir: <path>, if set)

Recent turns:
1. User: ...
2. Claude: ...
3. User: ...

Quoted / selected:
- <turn excerpt>            (only when strategy = explicit_selection)

Attached files (resolved against workingDir):
- <path>: <capped contents>

Relevant artifacts:
- Master plan from run <id>: <excerpt>

Latest user message:
<message>
```

Rules:

- v1 strategies: `recent_turns` (default) and `explicit_selection` (quote a turn
  / attach a file). `summary_*` is deferred.
- Recent turns first; preserve author and worker provenance.
- Apply a byte/character cap with **user-visible** truncation, not just a
  `truncated: Bool` in JSON. Surface it: "included the last N turns; older
  omitted." When the user blames the model for forgetting, the truncation must be
  visible so they trust the limit, not the tool.
- The user never reads raw packet assembly in normal flow — but a **Reveal /
  copy context** affordance must exist (reuse the manual-synthesis reveal
  pattern). Before a panel or dispatch turn, the user can preview what will be
  sent. Trust comes from being able to look, not from being shown by default.
- Keep context local. Never silently include private run artifacts from outside
  the thread. Attached files are read from `workingDir`, capped, and never sent
  anywhere except the selected worker invocation.

## Latency & Liveness (the honest streaming stance)

Vibe coding is feel, and feel is mostly perceived speed. The substrate is
request/response today (`CommandRunner` returns after the process exits), so v1
will not stream tokens. That is acceptable **only if** we are honest and the
turn never feels dead:

- The user's message turn is persisted and rendered **immediately** (optimistic),
  before any worker is invoked.
- The worker turn enters `running` **immediately** and shows a live "working"
  state (design-system owns the visual; a pulse, not a fake spinner-with-percent).
- When the CLI returns, the full reply lands in the turn body. Partial output is
  surfaced if and only if the driver actually emits it.
- **Cancel** kills the subprocess; the turn becomes `cancelled` with any partial
  text preserved — never a silent disappearance.
- Timeouts become a visible `timedOut` turn with the worker and elapsed time.

Known feel gap (do not promise otherwise): no token streaming in v1. Token
streaming requires a streaming `CommandRunner` variant and is tracked as a
post-MLP slice (S10-adjacent). The Works Test asserts the optimistic-render and
honest-failure behavior so nobody accidentally ships a dead spinner.

Turn metadata shown: `worker · model · observed duration`. **No** token counts,
dollar figures, or "marginal cost" — that is estimate/quota theater banned by the
post-MVP product laws.

## Admission Control Interaction

This phase and `Utilization_Admission_Control.md` must not fight in
implementation. One rule set:

- A chat turn to a worker that is `coolingDown` / `authRequired` produces a
  honest blocked/waiting turn state with the observed reason ("Claude cooling
  down until 2:14 AM"), not a silent failure.
- Casual chat does **not** auto-reroute to another worker. The user picks the
  worker; if it is unavailable, the thread says so and offers to switch or wait.
- Panel and dispatch turns may queue per the admission scheduler. Casual chat
  does not auto-queue overnight.

## Backend Impact

AllnighterCore:

- Add `WorkThread`, `ThreadTurn`, `ThreadContextPacket`, `ArtifactRef`, the
  storage `kind` enum, the family mapping, and turn/thread status enums, all
  `Codable` with deterministic fixtures.
- Add the derived-liveness helpers (Rule 9) as computed properties, not stored
  fields.
- Add round-trip tests and illegal-state tests for the turn lifecycle (e.g. a
  `done` turn cannot return to `running`; a `supersedesTurnId` must point at an
  existing turn).
- Do **not** modify `CouncilRun` (ownership rule).

AllnighterEngine:

- Add `ThreadStore` (sibling to `RunStore`, same folder-of-JSON philosophy):
  create / list / get / append / update / archive, keeping `updatedAt` honest.
  Runs stay in their own folders; threads reference `runId`.
- Add `ThreadContextBuilder` (recent_turns + explicit_selection, caps,
  truncation metadata, file attach against `workingDir`).
- Add `WorkerChatCoordinator` for one-worker chat turns: optimistic user turn,
  build packet, invoke via the existing `WorkerRunner` (passing
  `workingDirectoryOverride: thread.workingDir`), persist the reply turn, honor
  cancel/timeout/admission honestly. Manual-paste workers fall back to revealing
  the exact packet and accepting a pasted answer as the reply turn.
- Reuse the `RunEvent` stream for any council work inside a thread; add a thin
  turn-update mechanism for chat turns.

Mac app backend:

- **S06 (MLP, additive):** add a thread detail view (timeline + always-visible
  composer) reachable alongside the existing council UI. Do not remove run
  history yet.
- **S08 (flip):** make Home a thread list; existing run views become detail panes
  attached to council turns; legacy `CouncilRun`s migrate to one-turn threads.
- Composer actions map to the escalation table. Quick capture (⌥⌘Space) creates a
  new thread (or appends to the active thread, per a setting) — not an orphan
  prompt.

iOS:

- Consume the same thread/turn models once the remote spine exists. The Mac
  stays thread truth. The model's `workingDir`, derived liveness, and turn
  families are designed so a phone can render and send without inventing state.

Driver / protocol:

- No new provider APIs for v1. Existing headless CLI manifests drive worker chat.
- Future: a streaming `CommandRunner` variant for token streaming; future
  protocol events stream thread/turn updates, not only run events.

Privacy / permissions:

- Thread transcripts and `workingDir` file contents are local by default.
- Only the assembled packet goes to the selected worker invocation — nothing
  else, nowhere else.
- No telemetry on thread content. Export (S09) is user-initiated.
- iOS/cloud relay must treat thread content as E2E-sensitive, same as prompts and
  run outputs.

## Migration

- Each historical `CouncilRun` becomes an **auto-thread**: titled from its prompt,
  containing a single `council_run` turn that references the existing `runId`,
  plus one `system_event` turn noting "imported run — no prior chat."
- **No synthetic backfilled user/chat turns.** Honest empty history.
- `runAgain` becomes "Continue in thread" / "Fork to a new thread with this
  prompt."
- Migration is lazy and idempotent (wrap on access / first list build), not a
  startup batch job over `Runs/`. One mental model — no permanent "old council
  history" tab.

## Designer Handoff

Spec surfaces from these backend truths. Five non-negotiable behaviors (visuals
are yours; these contracts are not):

1. The **composer is always visible** at the bottom of a thread — never a separate
   "new council run" screen.
2. **Default action = Send to [resolved worker].** Secondary actions: Ask panel ·
   Turn into work order · Dispatch (· Design, when that lane ships).
3. **Council/build turns expand in place** to a rich card (member answers, master
   plan, live dispatch, returned result) — never navigation away that loses
   scroll position.
4. **Running/failed/waiting are turn states inside the thread**, shown on the turn
   that owns them — not separate inboxes. Thread-list liveness is derived.
5. **Thread list is Home**, with per-thread last-message preview, last-worker
   glyph, and relative time. Old runs appear as migrated one-turn threads.

Empty state after Setup: "Start a thread — think with one worker, escalate when
ready," with one muted example placeholder (not pre-filled).

## Ordered Slices

MLP = S01–S06.

- [ ] PWT-S01 — Core models: `WorkThread`, `ThreadTurn`, `ThreadContextPacket`,
  `ArtifactRef`, kind/family/status enums, derived-liveness helpers, fixtures,
  Codable round-trip + illegal-state tests. (`workingDir`, `defaultWorkerId`,
  `supersedesTurnId`, `seedFromTurnId` included.)
- [ ] PWT-S02 — Linkage: `ThreadTurn.runId` reference rule + store-level inverse
  index; tests that prevent duplicate ownership. `CouncilRun` untouched.
- [ ] PWT-S03 — `ThreadStore`: create/list/get/append/update/archive with
  deterministic file fixtures and honest `updatedAt`.
- [ ] PWT-S04 — `ThreadContextBuilder`: recent_turns + explicit_selection, caps,
  visible truncation metadata, file attach against `workingDir`, tests.
- [ ] PWT-S05 — `WorkerChatCoordinator`: optimistic user turn, packet build,
  `WorkerRunner` invoke with `workingDir`, honest cancel/timeout/admission,
  manual-paste reveal fallback. Engine-level Works Test passes here.
- [ ] PWT-S06 — Minimal Mac chat surface (additive): thread detail timeline +
  always-visible composer + thread list, **alongside** existing council UI. This
  is where the MLP becomes demoable.
- [ ] PWT-S07 — Wrap existing council/design/review/dispatch flows as thread turns
  (escalation actions + inline rich turns + "feed result to worker"), without
  changing run/stage truth.
- [ ] PWT-S08 — Ownership flip: Home becomes the thread list; lazy migration of
  legacy runs to one-turn threads; quick capture -> thread.
- [ ] PWT-S09 — Export bundle: full thread transcript (Markdown) + linked run
  artifacts.
- [ ] PWT-S10 — Remote/event seam: thread.created, turn.created, turn.updated,
  turn.completed, turn.failed, thread.archived. (Streaming `CommandRunner` for
  token streaming is tracked here-adjacent as a feel upgrade.)

## Works Test

Structural + emotional. A founder should be able to demo all of this.

```text
1. 30-second brainstorm:
   New thread. Send "before we build, brainstorm the simplest approach" to one
   healthy worker. The user turn renders instantly; the worker turn shows running
   immediately; the reply is saved as a turn. Send a follow-up to a DIFFERENT
   worker — the saved context packet includes the earlier user turn and reply.

2. Escalation:
   From the same thread, "ask the panel." A council run is saved as a turn
   referencing the run; reveal shows the packet included turns 1-2. Pick the
   master plan -> "turn into work order" -> an editable work-order turn appears
   and nothing has run yet.

3. Build in the thread's repo:
   Set the thread workingDir. Dispatch the work order; the builder runs in that
   dir. Dispatch and return review land as later turns in the same thread.

4. Next day:
   Quit the app. Reopen. The thread is intact, the composer is focused, and the
   last worker is remembered.

5. Failure honesty:
   Cancel a worker mid-reply -> the turn is `cancelled` with any partial text,
   not gone. Point chat at a cooling-down worker -> a honest waiting turn with the
   reason, never a fake reply.
```

## Proof Command

```text
swift test
scripts/check.sh
```

Engine Works Test (steps 1–2, 5 at the coordinator level) must pass
deterministically with `MockCommandRunner` after S05, independent of the UI. If
the Mac app cannot yet drive the full UI flow at a given slice, the proof names
that gap and keeps the deterministic engine test.

## Done When

- A user can persist an exploratory chat with one worker before any council or
  dispatch, with the worker chosen by the default-resolution ladder.
- Follow-up turns receive explicit thread context from the saved transcript, with
  truncation visible when it happens.
- "Ask the panel" / "turn into work order" / "dispatch" / "continue from result"
  all work as one-click escalations from within the thread, carrying context.
- A thread can anchor to a `workingDir` that grounds chat context and is the
  default cwd for dispatch.
- Council/design/review/dispatch work attaches to the thread as turns instead of
  becoming disconnected history rows; `CouncilRun`/`StageOutput` truth is reused,
  not duplicated.
- Thread state survives restart; the thread reopens focused with the last worker
  remembered.
- Worker failures, cancellations, timeouts, and admission holds are visible turns.
- The designer has stable backend semantics and the five composer contracts.

## Open Questions

1. **Native session continuity (post-v1):** when chatting repeatedly with the
   same worker, should we ride `claude --resume` / `codex resume` as a speed/cost
   optimization while keeping the Allnighter transcript as truth? (Default
   answer: yes, later; never as the source of truth.)
2. **Multiple in-flight council runs per thread:** allowed concurrently, or one
   active run at a time?
3. **Thread scope guidance:** one thread per goal forever, or encourage "new
   thread per feature"? Affects auto-title quality and archive UX.
4. **Panel snapshot vs live panel:** when escalating to the panel, use the
   sidebar's current seat selection, or a panel snapshot stored on the thread at
   creation? (Leaning: use current seats; record what was used on the turn.)
5. **Quick capture default:** new thread vs append to active thread — ship which
   as the default, and is it a setting?
6. **iOS compose scope:** can the phone send chat turns, or only view + approve
   panel/dispatch in the first remote cut?
7. **Search:** at what thread count does title+preview list need real search?
   (Likely v1.5: search titles + first message + run prompts.)
