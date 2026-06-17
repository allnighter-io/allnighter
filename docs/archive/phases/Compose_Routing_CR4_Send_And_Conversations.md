# Compose Routing CR4 — Send + Conversations

**Status:** BUILT / archived (2026-06-17). CR4a through CR4e delivered.
**Owner:** GUI + Mac app (compose surface) · **Created:** 2026-06-16
**Archived:** `docs/archive/phases/Compose_Routing_CR4_Send_And_Conversations.md`
**Process:** `docs/operations/Execution-Playbook.md` · **GUI governance:** `docs/gui/GUI_Workflow.md` + the visual proof gate (`docs/phases/GUI_Visual_Proof_Gate.md`)
**Design SSOT:** `docs/phases/wiring/design_handoff_compose_routing/README.md` (+ `reference/app.jsx`, the authoritative prototype)

---

## Current Truth

This doc is no longer the work queue. CR4a–CR4e have landed: Send creates and
opens conversations, Chat runs one model through `WorkerChatCoordinator`, Fan out
renders durable team/design board turns, Execute renders durable dispatch turns,
and the Home rail has filters/search plus Pinned/Recent grouping.

Use [`Persistent_Work_Threads.md`](../../phases/Persistent_Work_Threads.md) as the live router.
The next thread-foundation work is
[`threads/05_ThreadStore_Hardening.md`](../../phases/threads/05_ThreadStore_Hardening.md).
Do not execute this CR4 packet as fresh implementation work.

## 0. Read first

This section is historical context from before CR4 landed. It explained the gap
at the time: the composer already **looked** right and **selected** right (mode,
model, effort, team) against the real bench, but Send had not yet been wired.
That gap is now closed; see **Current Truth** above.

### What is already built (do not rebuild)

| Piece | File | State |
| --- | --- | --- |
| Routing composer (bar + mode menu + target popovers + effort) | `Apps/AllnighterMac/Sources/RoutingComposer.swift` | Done (CR1–CR2) |
| Composer reads REAL bench/teams/executors | `AppModel.composeBench` / `composeTeams(for:)` / `composeExecutorIds` / `composeDefaultTeam(for:)` | Done (CR3) |
| Clean launch home (rail + "You already pay for the team" empty state) | `Apps/AllnighterMac/Sources/HomeView.swift` | Done |
| Composer specimen + dev routes + fixtures | `ComposeSpecimen` (in `RoutingComposer.swift`), `GUIFixture.swift`, `DevSettingsView.swift` | Done |

Composer state lives in `RoutingComposer` as `@State`: `mode`
(`ComposeMode .chat/.fanout/.exec`), `to` (model id), `effort` (`ComposeEffort`),
`lane` (`ComposeLane`), `team` (team id), `pop`. The old "Send is no-op" state
is obsolete; send is now routed through `ThreadsViewModel.sendRouting`.

### The backend you will wire into (already exists)

- **Conversations = work threads.** `WorkThread` + `ThreadTurn`
  (`Packages/AllnighterCore/Sources/AllnighterCore/`), persisted via
  `ThreadStore` (`…/AllnighterEngine/ThreadStore.swift`):
  `create(...)`, `list()`, `get(_:)`, `append(_ turn:toThreadId:now:)`,
  `update(...)`, `archive(...)`.
- **`ThreadTurnKind`**: `userMessage`, `userDecision`, `workerChat`, `teamRun`,
  `designBoard`, `reviewBoard`, `workOrder`, `dispatch`, `returnReview`,
  `systemEvent` — one kind per send mode's result.
- **View model:** `Apps/AllnighterMac/Sources/ThreadsViewModel.swift`
  (`threads`, `selectedThread`, `select(_:)`, `newThread(title:workingDir:)`,
  `composerText`, `send()`, `canSend`, `completeManualPaste(...)`). Today's
  thread UI is `ThreadsView.swift` (`ThreadDetailPane`, `ThreadComposer`) — the
  **old** composer; CR4 replaces it with `RoutingComposer`.
- **Runs:** single-worker chat already exists in `ThreadsViewModel.send()`
  (sends `composerText` to the resolved worker → `workerChat` turn). Team runs:
  `AppModel.runTeam()` + the async lifecycle (`AsyncTeamService`,
  `TeamRunCoordinator`). Execute: `AppModel.dispatch()` (RB4).

### Image resources (the visual SSOT — open these)

All under `docs/phases/wiring/compose-routing/`:
- Conversation thread + composer (the CR4 target surface):
  [`allnighter-compose-routing-base.png`](../../phases/wiring/compose-routing/allnighter-compose-routing-base.png)
- Empty "Start a work order" thread state:
  [`allnighter-compose-routing-new-work-order.png`](../../phases/wiring/compose-routing/allnighter-compose-routing-new-work-order.png)
- Mode menu: [`…-mode-menu.png`](../../phases/wiring/compose-routing/allnighter-compose-routing-mode-menu.png)
- Chat target: [`…-chat-target.png`](../../phases/wiring/compose-routing/allnighter-compose-routing-chat-target.png)
- Execute target: [`…-execute-target.png`](../../phases/wiring/compose-routing/allnighter-compose-routing-execute-target.png)
- Fan-out target: [`…-fanout-team.png`](../../phases/wiring/compose-routing/allnighter-compose-routing-fanout-team.png)
- Team dropdown: [`…-team-dropdown.png`](../../phases/wiring/compose-routing/allnighter-compose-routing-team-dropdown.png)

Authoritative prototype + spec:
[`design_handoff_compose_routing/README.md`](../../phases/wiring/design_handoff_compose_routing/README.md),
[`reference/app.jsx`](../../phases/wiring/design_handoff_compose_routing/reference/app.jsx)
(see `ThreadPane`, `Composer`, `MSG`/turn rendering), and the clickable
`Compose Routing Prototype.html` in that folder.

### Vocabulary (enforce it)

Work routes to a **model** (Opus 4.8), never a CLI (Claude Code). **Bench** =
models. **Team** = a saved lineup for one **lane** (Build/Design/Copy), edited in
settings only. **Effort** = Low/Med/High (one word). **Mode/verb** = Chat / Fan
out / Execute. Compose only *selects*; it never configures teams.

---

## 1. Cross-cutting rules (every slice obeys)

- **Launch stays clean & process-quiet.** Do not re-introduce a launch-time
  probe or auto-open setup (`Launch_Authority_TCC_Hotfix.md`). Sending is the
  first run, and only on explicit click.
- **Smart default verb, re-seeded on thread switch.** The armed `mode` derives
  from the active thread: a thread whose latest state is **spec/board ready**
  arms **Execute**; everything else **Chat**. This MUST update when the user
  switches threads (re-seed, not a one-time mount). The verb is always visible
  on the mode pill and overridable in one click. Lane is never inferred.
- **Effort + team selections persist across thread switches; only the verb
  re-seeds** (so an in-progress routing choice isn't lost).
- **Never fake a result.** A worker/team/dispatch turn shows real output or an
  honest failure with the reason — never a placeholder dressed as success.
- **GUI proof ritual per visible slice:** `bash scripts/gui_proof.sh <fixture>`
  → spawn the layout-watcher (`.claude/agents/layout-watcher.md`) → require PASS
  → `bash scripts/gui_proof_seal.sh <surface> <slug> <fixture>…` → paste the
  verdict into the packet's `watcher.md`. Non-visual view edits use
  `scripts/gui_proof_waive.sh`. Add `home-*` / `thread-*` fixtures to
  `GUIFixture.swift` (`benchScenarios` + an `opens…`/seed branch) the same way
  `compose-*` / `readiness-*` were added; compose/home seeds already force an
  all-ready bench.
- **Proof command (closeout):** `bash scripts/check.sh` (swift + GUI gate + Mac
  tests) must be green.
- **Commit per slice** (the founder works the green wall slice by slice).

---

## 2. Slices

### CR4a — Conversations shell (no run yet)

**Goal:** New work order + sending from the home creates a real `WorkThread`,
the left rail lists threads, selecting one shows a thread view with the timeline
+ the `RoutingComposer` docked at the bottom. Chat send appends a `userMessage`
turn only (the model reply is CR4b). This is the scaffold the rest hangs on.

**Scope:**
- Replace the home's "No conversations yet" rail with a real list of
  `ThreadsViewModel.threads` when non-empty (keep the empty hint when empty).
  Each row: brand glyph of the thread's lane/worker, title, a status pill, a
  relative time. Pinned/Recent grouping + filters (`All/Design/Build/Running`) +
  search are CR4e — for CR4a a flat newest-first list is fine.
- **New work order** button → `ThreadsViewModel.newThread(...)` → select it →
  show the thread view (empty "Start a work order" state per
  `…-new-work-order.png`).
- **Thread view** (new, e.g. `ThreadView` in a new file or fold into
  `HomeView`): a header (thread title + lane chip + "routed across …"), a
  scrollable **turn timeline**, and the `RoutingComposer` (non-`big`) docked at
  the bottom. Empty thread = the centered "Start a work order" block from
  `…-new-work-order.png`.
- **Wire send:** give `RoutingComposer` an `onSend: (ComposeRouting) -> Void`
  closure (struct carrying `mode/to/effort/lane/team/text`). The empty-home
  composer's `onSend` creates a thread (title from the text) + appends a
  `userMessage` turn + selects it; the thread composer's `onSend` appends to the
  current thread. Clear the textarea after send.
- **Smart default verb:** on selecting/switching a thread, re-seed `mode` from
  the thread state; keep `effort`/`team`. (A small `routingDefault(for:
  WorkThread)` helper.)

**Out of scope:** running any model; rendering worker/board/dispatch turns
(stub `userMessage` only); filters/search/pins.

**Truth owner:** `WorkThread`/`ThreadTurn` semantics → AllnighterCore +
`ThreadStore`. UI-local routing state → `RoutingComposer`. Do **not** invent new
turn kinds; reuse `userMessage`.

**Files:** `RoutingComposer.swift` (add `onSend`), `HomeView.swift` (rail list +
route New work order/send), new `ThreadView.swift`, `RootView.swift` (show thread
view when a thread is selected), `GUIFixture.swift` (`thread-empty`,
`thread-with-turns` fixtures + a seeded thread).

**Works test:** Launch → type in the home composer → Send → a conversation
appears in the rail, the thread view opens with your message as the first turn,
composer docked below. New work order → empty thread with the "Start a work
order" state.

**Proof:** fixtures `thread-empty`, `home-with-threads` (rail populated) →
watcher PASS → seal `gui_proof_seal.sh thread cr4a-conversations-shell …`.

**Done when:** Sending creates + opens a thread with a `userMessage` turn; the
rail lists threads; the composer is docked in the thread view and re-seeds the
verb on switch; `check.sh` green.

---

### CR4b — Chat send → one model answers

**Goal:** In Chat mode, Send appends the user turn AND runs the chosen single
model, streaming/returning its reply as a `workerChat` turn rendered in the
timeline (per the chat bubbles in `…-base.png`).

**Scope:**
- `onSend` for `.chat`: resolve `to` → the worker, run it via the existing
  single-worker path (reuse/extract from `ThreadsViewModel.send()` /
  `WorkerRunner` through the cached `ToolInvocation` — health == runs), append a
  `workerChat` turn with the result (or an honest failure turn).
- **Turn rendering:** user message bubble + worker reply bubble (brand glyph +
  model name + markdown body + copy). Match `…-base.png` (the "You" / model
  turns). Use the design-system markdown/bubble primitives.
- Running state: the worker turn shows a live "running…" affordance, then
  resolves in place (no app restart).
- The target chip "to" persists; user can re-route the next turn to a different
  model (the whole point — "route any turn to anyone").

**Out of scope:** fan-out board; execute; per-turn "routed across" recap header
polish.

**Truth owner:** run truth = `TeamRun`/worker outcome in the run store; the turn
references it. `ThreadStore.append`.

**Files:** `RoutingComposer.swift`/`AppModel.swift` (a `chatSend` path),
`ThreadView.swift` (workerChat turn view), maybe extract a reusable single-model
runner from `ThreadsViewModel`.

**Works test:** Chat → "token bucket or sliding window?" → Send → your message,
then the model's real answer appears in the thread. Switch the chip to another
model, send again → that model answers.

**Proof:** fixture `thread-chat` (seeded with a user + worker turn) → watcher
PASS → seal.

**Done when:** A real model answers in the thread for Chat; failures show
honestly; verb/route re-routable per turn; `check.sh` green.

---

### CR4c — Fan out → team board

**Goal:** In Fan out mode, Send launches a team run for the selected
**lane + team + effort** and renders the result as a board turn (the parallel
options + "You picked … / Open board" from `…-base.png`).

**Scope:**
- `onSend` for `.fanout`: map `lane → WorkLane`, `effort → EffortLevel`, `team →`
  the `BuiltInTeams`/preset id; start a team run (`AppModel.runTeam()` /
  `AsyncTeamService.start`) bound to the thread; append a `teamRun` (Build) or
  `designBoard` (Design) / board turn referencing the run id.
- **Board rendering:** worker answers as comparable options/cards; for Design,
  the mockup board; a pick affordance ("You picked …", "Open board"). Reuse the
  existing review/board + `DesignBoardView` primitives where possible.
- Live status (fanning out → answers in → reducing) surfaced on the turn; honest
  partial/failed states.

**Out of scope:** execute; the standalone full board window beyond what exists.

**Truth owner:** team-run lifecycle = `AsyncTeamService`/`TeamRunCoordinator`;
board turn references the `TeamRun`.

**Files:** `AppModel.swift` (`fanoutSend`), `ThreadView.swift` (board turn),
reuse `DesignBoardView`/review board.

**Works test:** Fan out · Design team · Med → Send → a board of options returns
in the thread; you can pick one.

**Proof:** fixture `thread-board` → watcher PASS → seal.

**Done when:** A real team run renders as a board turn with a pick; `check.sh`
green.

---

### CR4d — Execute → dispatch to your repo

**Goal:** In Execute mode, Send hands the work to the chosen executor model in a
working directory; the execution result (file diff + exit code) returns as a
`dispatch` turn (per the "Claude Code · execution … src/screens/Profile.tsx
+04 −63 · exit 0" turn in `…-base.png`).

**Scope:**
- `onSend` for `.exec`: resolve `to` → executor, resolve the working directory
  (thread's `workingDir` or prompt for one), dispatch via `AppModel.dispatch()`
  (RB4 execution lane — respect the inviolable execute-lane FIFO safety;
  `[[allnighter-pending-execute-lane-safety]]`). Append a `dispatch` turn.
- **Dispatch turn rendering:** executor glyph + "execution" + file path(s) +
  diff stat (`+N −M`) + exit code badge. Match `…-base.png` + `…-execute-target.png`.
- Honest failure (non-zero exit, missing dir) shown with the reason.

**Out of scope:** return-review loop (RB5) beyond linking to it.

**Truth owner:** execution lane safety + dispatch = AppModel `dispatch()` /
engine; never weaken concurrent-execute protections.

**Files:** `AppModel.swift` (`execSend`), `ThreadView.swift` (dispatch turn).

**Works test:** Execute · Opus 4.8 · pick a repo → "add the 429 path" → Send →
an execution result with a diff + exit code returns in the thread.

**Proof:** fixture `thread-dispatch` → watcher PASS → seal.

**Done when:** A real dispatch runs in a chosen dir and renders its result/diff;
execute-lane safety intact; `check.sh` green.

---

### CR4e — Rail polish (optional, last)

**Goal:** Make the conversation rail match `…-base.png`/`…-new-work-order.png`.

**Scope:** Pinned/Recent grouping, the `All/Design/Build/Running` filters (wired
to thread lane/state), working search, per-row status pills (`exit 0`,
`running`, `replied`, `board ready`, `spec ready`, `exit 1`) + tiny worker
glyphs + relative times.

**Truth owner:** `ThreadsPresenter` (derive row state/pills from `WorkThread`).

**Done when:** rail visually matches the mockups; filters/search work; `check.sh`
green.

---

## 3. Suggested order & checkpoints

CR4a → CR4b → CR4c → CR4d → CR4e. After **CR4a + CR4b** the product is usable
(send a message, a model answers in a conversation) — a natural demo checkpoint.
CR4c/CR4d add the other two verbs. CR4e is polish.

Each slice: small diff, focused proof while iterating, `check.sh` at closeout,
render→watcher→seal for visible surfaces, one commit. Log any durable lesson in
`DEBUGLOG`. Durable composer/conversation truth now lives in
[`Persistent_Work_Threads.md`](../../phases/Persistent_Work_Threads.md).

## 4. Gotchas

- `RoutingComposer` seeds `to`/`team` in `onAppear` (`seedDefaults`) because
  `init` can't read the environment — keep that when adding `onSend`.
- The composer reads `@Environment(AppModel.self)`; any host (thread view, home,
  specimen) must provide it (`RootView` already does).
- The old `ThreadsView.swift` composer (`ThreadComposer`) and the old
  Team-workspace panes (`DetailPane`, `SidebarView`, `WorkspaceSwitcher`) are
  superseded — remove or stop instantiating them as CR4 lands; don't leave two
  composers wired.
- Mac test host: the green wall's Mac tests run because `project.yml` pins
  `TEST_HOST`/`PRODUCT_MODULE_NAME` — don't change those.
- GUI capture window is fixed at 1100×720; rich panes scroll. Below-fold content
  is expected (not a P1) — add a focused fixture if a new control must be
  pixel-proven.
