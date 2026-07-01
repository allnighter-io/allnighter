# Chat Module Extraction — A Reusable, Best-in-Class Chat Package

**Status:** PLAN (2026-07-01). Architecture mapped against live code; build not started.
**Goal:** Extract Allnighter's single-worker **chat** into its own cleanly-exportable Swift
package(s) that other apps can consume and benefit from every time we improve Allnighter's chat.
**Scope:** SINGLE-WORKER CHAT ONLY (one model, one thread, one worker, streaming, attachments,
warm workers). **Send-to-Team / team-run / fan-out is explicitly OUT of scope** — it stays in the
Allnighter app spine. (We may extract a separate team module later; not now.)
**Companions:** [`Warm_Single_Lane_Chat.md`](./Warm_Single_Lane_Chat.md) (the warm-worker physics),
[`Unified_Run_Model.md`](./Unified_Run_Model.md) (the run substrate we are deliberately *not* taking),
[`Persistent_Work_Threads.md`](./Persistent_Work_Threads.md) (the thread model).

---

## 1. Why this exists

I have other apps that need an AI chat surface. Rather than rebuild it, I want Allnighter's chat to
be **the** chat: one module, best-in-class, continuously improved, and every product that embeds it
inherits every improvement. Concretely that means a package with:

- The thread/turn model, the send pipeline, streaming, attachments, image-gen, manual-paste.
- Warm single-lane workers (sub-second follow-ups — the CODE RED latency win).
- A drop-in SwiftUI chat surface (message list + composer + markdown) that a host app can theme.
- **Zero** transitive dependency on Team, Project spine, Catalogs, Run substrate, MCP, or the
  remote/iOS transport. If you import the chat module you must not drag in `TeamResolver`.

This doc maps where we are and lays out the phased path to get there.

---

## 2. What we found (current architecture)

### 2.1 The data model already draws the seam — this is the good news

`WorkThread` owns chat turns directly; heavy work is a *reference*, not embedded:

- `WorkThread.turns: [ThreadTurn]`, chat turns are `userMessage` / `workerChat` / `userDecision` /
  `systemEvent` (`ThreadTurn.swift:154`).
- Team work is a separate `team`-family turn kind (`teamRun` / `designBoard` / `reviewBoard` /
  `mutatingRun`) that only carries a `runId` pointer into a `TeamRun` — the chat module never needs
  to know what those are (`ThreadTurn.swift:185`, `isHeavy`/`referencesRun` at `:194`/`:204`).
- `WorkThread.swift:8`: *"It owns chat turns directly; heavy work … is referenced by `runId`."*

So the model was designed with the cut we want. `TeamRun` is named only in **comments** inside
`ThreadStore` / `WorkerChatCoordinator` / `ThreadContextPacket` — there is **no compile dependency**
from the chat model into team code.

### 2.2 There are TWO chat substrates — this is the crux

| | **Path A — Thread chat** | **Path B — Unified Run Model** |
|---|---|---|
| Core type | `ThreadSendCoordinator` / `WorkerChatCoordinator` | `RunService` |
| Team machinery | **None** — genuinely separate, team-free by design | **Yes** — chat is a degenerate 1-seat team-run |
| Warm workers | No (cold `runner.invoke` per turn) | **Yes** — `Warm_Single_Lane_Chat` lives here |
| Live Mac GUI caller | **Dormant** (definition exists, no caller) | **The live path** (`sendRouting` → `runViaRunService`) |
| CLI/MCP caller | `alln thread send` / `thread_send` (live) | `alln run` / `team_run`, `pair_run` |

- **Path A is genuinely team-free.** It resolves one worker, appends `userMessage` + `workerChat`,
  invokes one worker via `WorkerRunner`. No `TeamRun`, `TeamResolver`, `TeamPreset`, `SkillCatalog`.
  Design intent is explicit: `WorkerChatCoordinator.swift:11` — *"`TeamRun` is never touched here."*
- **Path B makes chat a one-seat team-run.** `RunService.swift:103` — *"Unified run entry — one
  primitive for chat, execution, and answer teams."* It always builds a `TeamPreset` (falling back to
  the `default_chat` "Auto" team, `RunService.swift:249`), resolves via `TeamResolver`, and wraps the
  single worker in a full `TeamRun` (`RunService.swift:457`). `BuiltInTeams.swift:248` models chat as
  a one-row team on purpose: *"one agent, mutating-allowed, no special-case code path."*
- **The live Mac app uses Path B for all chat sends** (`ThreadsViewModel.swift:534` `sendRouting →
  runViaRunService`; `:584` `TeamCatalog.get($0) ?? TeamCatalog.defaultRunTeam()`). Path A's
  `runChat` has **no live caller in the Mac sources**.
- **Warm single-lane chat is embedded under Path B / team.** The warm execution block
  (`RunService.swift:479–558`) is only reachable after preset lookup + `TeamResolver.resolve` +
  `TeamRun` wrapping. So today **"team-free" and "warm" are mutually exclusive** — no existing code
  gives us warm chat without the team substrate. Producing that is the central engineering work here.

### 2.3 The backend send pipeline is already dependency-injected

Path A's pipeline is constructor-injected and team-free at the type level. It touches only:
`ThreadStore`, `WorkerRunner`, `WorkerImageInvoker`, `DriverRegistry`/`DriverManifest`,
`ThreadContextBuilder`, `Model`, `ThreadTurn`, `WorkerRunOutcome`, attachment stores. The only hard
code edges from the chat send path into the rest of Allnighter are **three call sites** in
`ThreadSendCoordinator`:

1. `ThreadImageSeedResolver` — seeds an image-gen turn from prior design-board outputs → depends on
   `RunStore` + Board (the only send-path edge into the run world; text chat never hits it).
2. `ProjectFileReferenceResolver` — resolves `@file` refs → depends on `ProjectFileCatalog` (project
   spine; text chat with no `@file` skips it).
3. `PendingCapacityResumeWriter` / `PendingStore` — links capacity/cooldown resume into the pending
   queue (cross-cutting, not chat-intrinsic).

Everything else the module needs (`Model`, `DriverRegistry`, `DriverManifest`, the three PURE wire
types `ClaudeMessage`/`CodexMessage`/`ACPMessage`, all `*StreamParser`s, `WorkerRunner`,
`CommandRunner` + runners, `DriverConcurrencyGate`, `CapacityClassifier`) is already team-free.

### 2.4 The UI is two parallel implementations, hard-wired to per-platform tokens

- Mac (`Apps/AllnighterMac/Sources`) and iOS (`Apps/AllnighteriOS`) share **no view code** — only the
  Core/Engine packages. iOS is a thin remote client (plain `Text`, no markdown); Mac is the
  authoritative local driver with full markdown + streaming. Both reimplement the same conceptual
  surface (`ThreadTurnRow` bubbles, avatar chip, model/effort chips, send button) against different
  token enums (`ALColor`/`ALFont` vs `IOSColor`/`IOSFont`) and different backends.
- The reusable chat views on Mac are real but entangled: `ThreadView` renders chat arms
  (`userBubble`, `workerBubble`, `ThreadThinkingBlock`, `AnswerBody`, streaming indicators, Raw⇄
  Rendered toggle) **and** team arms (`ThreadBoardRow`, `ThreadMutatingRunRow`) in the same
  `ThreadTurnRow` switch. The team arms are droppable.
- **Design tokens are pervasive and un-abstracted.** `RoutingComposer` (~116 lines) and `ThreadView`
  (~110 lines) hard-reference global `ALColor`/`ALFont`/`ALRadius`/`ALPalette`. There is no theme
  layer. `MarkdownTheme.allnighter` also binds directly to `ALColor`. A reusable cross-platform UI
  requires a **theme-injection seam** to replace these globals; otherwise we ship two themed copies.
- The logic layers are clean: `ThreadsViewModel` (send/stream) and `ThreadsPresenter` (list state)
  have **zero** token references.
- `AllnighterMarkdown` is **already** a standalone, reusable SwiftPM package (forked
  swift-markdown-ui + NetworkImage, MIT). It is the precedent for this whole effort and a dependency
  of the chat UI module.

### 2.5 The team-routing coupling in the composer is well-localized

Team routing threads through **one value type + one send method** per platform, so the cut is
contained despite large files:

- Mac: `ComposeRouting.team: String?`; `RoutingComposer` `TargetTab.model/.team` popover, `teamPickerBody`,
  `rankedTeams`, `selectTeam`, `resolvedWorkerId(forTeam:)`, the "Send-to-team launcher" mode;
  `ThreadsViewModel.sendRouting → runViaRunService` (Path B).
- iOS: `IOSComposerTeamPickerSheet`, `composer-team-chip`, `IOSComposerDraft.selectedTeamId`,
  `IOSComposerCatalog.teams/defaultTeam/teamPresetIDs`.

Removing these leaves a clean single-worker composer (editor + Auto/model chip + effort chip +
attachments + `@`-refs).

---

## 3. Target state

Two new bottom-layer packages plus the existing markdown package, with Allnighter (and any other app)
sitting on top:

```
┌─────────────────────────────────────────────────────────────┐
│  Host apps: AllnighterMac, AllnighteriOS, <your other apps>  │
│   - provide a Theme, a ChatModelResolving, a workspace root   │
│   - own Team / Project / Run / MCP / remote transport         │
└───────────────┬──────────────────────────┬──────────────────┘
                │                          │
        ┌───────▼────────┐        ┌────────▼─────────┐
        │ AllnighterCore │        │  AllnighterChatUI │  (SwiftUI: list + composer)
        │  + Engine      │        │   theme-injected  │
        │ (team/project/ │        └────────┬─────────┘
        │  run/mcp/remote)│                 │
        └───────┬────────┘        ┌─────────▼──────────┐   ┌──────────────────┐
                └────────────────►│ AllnighterChatCore │──►│ AllnighterMarkdown│
                  (depends on)    │ models + send +    │   │ (already standalone)│
                                  │ streaming + warm   │   └──────────────────┘
                                  │ workers (Foundation)│
                                  └────────────────────┘
```

Non-negotiables for the module:

- `AllnighterChatCore` depends only on `Foundation` (+ its own value types). It has **no** knowledge
  of Team, Project, Run, Catalog, MCP, or remote transport. Importing it must not pull any of those.
- `AllnighterChatUI` depends on `AllnighterChatCore` + `AllnighterMarkdown` + SwiftUI, and takes its
  colors/fonts through an injected `ChatTheme`, never a global `ALColor`.
- Allnighter's app spine (`AllnighterCore`/`Engine`) **depends on `AllnighterChatCore`** for the
  shared thread/turn model (inverting today's "everything lives in Core"). Team code keeps using
  `WorkThread`/`ThreadTurn` from the new bottom layer.
- Warm single-lane chat lives **inside** the module, decoupled from `RunService`.

---

## 4. Key design decisions (with recommendations)

**D1 — Which chat path becomes the module?**
Build the module around **Path A's** turn/streaming/attachment shell (team-free by construction) and
lift the warm-worker layer under it. Path B (`RunService`) stays in the app spine for team runs. This
is the only way to get a team-free module that is *also* warm. Rationale: the warm block
(`RunService.swift:479–558`) is already team-free internally (needs only `manifest`, `model`,
`threadId`, `repoRoot`, `effort`, `WarmWorkerPool`, `ACPTransportProfile`); the team coupling is a
thin front-matter/result-envelope shell around it that we replace with direct worker resolution +
a minimal chat run record.

**D2 — The three send-path edges become injected protocols.**
- `ImageSeedProviding` (default: nil) — replaces the direct `ThreadImageSeedResolver` call. Design-
  board seeding stays in the app.
- `FileReferenceResolving` — the module ships a trivial workspace-relative resolver; the app injects
  the `ProjectFileCatalog`-backed one. Drops the project edge.
- `CapacityResumeSink` (default: no-op) — replaces the `PendingStore` post-send call. Drops the
  pending-queue edge.

**D3 — Auto/default-model resolution is injected, not embedded.**
Path B resolves "Auto" via `SubstitutionResolver` + `DefaultModelSettings` + `TeamSourceFacts`
(team-coupled). The module takes a `ChatModelResolving` protocol: given the composer selection
(explicit model, or "Auto"), return a concrete `Model` + `DriverManifest`. Default impl requires an
explicit model; Allnighter injects the Auto-tier resolver. This keeps SBDS (tiers) in the app while
the module stays generic.

**D4 — Turn model: keep the heavy/team kinds inert (recommended for v1).**
`ThreadTurnKind` retains `teamRun`/`designBoard`/`reviewBoard`/`mutatingRun` and `ThreadTurn.runId`/
`projectId` as **inert, host-owned** cases the module persists and skips but never produces. Nothing
in the chat path writes `runId` on a `workerChat` turn, so this is zero-risk and keeps Allnighter's
existing on-disk JSON valid. (Cleaner long-term option, deferred: collapse the heavy kinds to a single
generic `externalRunRef(kind:runId:)` escape hatch so the module's public schema is chat-pure. Not
worth the churn until a second host actually needs it.)

**D5 — One UI module, theme-injected, replacing both platform copies.**
`AllnighterChatUI` is the single SwiftUI surface. A `ChatTheme` protocol (colors, fonts, radii,
spacing) replaces `ALColor`/`IOSColor` globals. Allnighter provides an `AllnighterChatTheme` mapping
to `ALColor`; iOS provides one mapping to `IOSColor` (or, once markdown ships on iOS, uses the shared
default). This retires the Mac/iOS view duplication over time.

---

## 5. Phased plan

Each phase is independently shippable and leaves the app green. Order matters: backend first
(foundation), warm second (the hard win), GUI cutover third, UI module fourth, iOS + external reuse
last. Consistent with the founder foundation-first directive: build the correct final split, no
optional-field hedging on the package boundary.

### Phase 0 — Contract & boundary freeze (this doc)
Lock the boundary in §3, the injected protocols in D2/D3, and the file set in §6. No code.

### Phase 1 — `AllnighterChatCore` package (backend extraction)
- Create `Packages/AllnighterChatCore` (bottom layer, `Foundation` only, macOS 14 / iOS 17).
- Move the §6 chat-core file set out of `AllnighterCore`/`AllnighterEngine` into it.
- Introduce `ImageSeedProviding`, `FileReferenceResolving`, `CapacityResumeSink`,
  `ChatModelResolving` protocols; rewire the three `ThreadSendCoordinator` edges to them.
- Make `AllnighterCore`/`AllnighterEngine` **depend on** `AllnighterChatCore`; app-side team/project
  code keeps importing the moved model types from the new package.
- Port the relevant tests (`ThreadStore*`, `ThreadSendCoordinator*`, `ThreadContextBuilder*`,
  message/stream parser tests) into the new package's test target.
- **Exit:** whole workspace builds green; `swift build` of `AllnighterChatCore` alone pulls in **zero**
  team/project/run/mcp/remote symbols (grep-verify no `Team`/`Catalog`/`Run`/`Project` types in the
  target). Cold chat works end-to-end via `alln thread send`.

### Phase 2 — Warm single-lane chat inside the module (the hard win)
- Lift `WarmWorkerPool`, `WarmWorker`, `WarmWorkerCapability`, `WarmSessionDriver` impls
  (`ACPSession`/`ClaudeSession`/`CodexSession`), `ACPTransportProfile`, `ProcessACPTransport`,
  `ExternalWorkerSessionStore` into `AllnighterChatCore` (they already import only `AllnighterCore`
  → will import `AllnighterChatCore` after Phase 1).
- Decouple them from `RunService` by inlining a **de-teamed** warm execution path into
  `WorkerChatCoordinator` (reuse Path A's turn/streaming shell; replace the team front-matter/result
  envelope with direct model resolution via `ChatModelResolving` + a minimal chat run record).
- `SkillCatalog.assemblePrompt` is a no-op passthrough for chat (`SkillCatalog.swift:171`), so the
  skill dependency collapses to nothing — the module builds the prompt via `ThreadContextBuilder`.
- **Exit:** module-native warm chat hits the `Warm_Single_Lane_Chat` latency targets (sub-second by
  turn 3) with no team types linked. `RunService` remains the team path only.

### Phase 3 — Mac GUI cutover to the module chat path
- Switch the Mac docked composer from `sendRouting → runViaRunService` (Path B) to the module's
  `WorkerChatCoordinator` (Path A + warm). Preserve Auto (via injected `ChatModelResolving`) and warm
  latency — this is the behavior-sensitive step; verify against `ThreadStreamingPerformanceTests`.
- Delete team routing from `RoutingComposer`: remove `ComposeRouting.team`, the `Model|Team` popover
  (`TargetTab.team`, `teamPickerBody`, `rankedTeams`, `selectTeam`, `resolvedWorkerId(forTeam:)`,
  launcher mode). Keep Auto/model + effort + attachments + `@`-refs.
- Drop the team render arms from `ThreadView` (`ThreadBoardRow`, `ThreadMutatingRunRow` and their
  `.teamRun/.designBoard/.reviewBoard/.mutatingRun` cases) from the chat surface. (Team runs still
  render — but through the team UI in the app spine, not the chat module.)
- **Exit:** Mac chat sends never touch `RunService`/`TeamCatalog`; GUI proof + streaming perf green.
  "Send to Team" still exists in Allnighter, launched from its own surface, not from the chat composer.

### Phase 4 — `AllnighterChatUI` package (UI extraction + theme seam)
- Create `Packages/AllnighterChatUI` depending on `AllnighterChatCore` + `AllnighterMarkdown`.
- Introduce `ChatTheme` protocol; move the reusable Mac chat views (`ThreadTurnTimeline`,
  `userBubble`/`workerBubble`, `ThreadThinkingBlock`, `AnswerBody`, streaming/working indicators,
  `ReasoningRenderPolicy`, `DurationFormat`, `MarkdownText`/`MarkdownTheme`, `SelectableText`, the
  slim composer, `ComposerPasteboardReader`, `ComposerImageFreezer`) into it, parameterized by
  `ChatTheme` instead of `ALColor`.
- Allnighter provides `AllnighterChatTheme` (maps to `ALColor`/`ALFont`) and consumes the module views.
- **Exit:** Mac chat renders through `AllnighterChatUI` with the Allnighter theme; no `ALColor` refs
  inside the module. A tiny sample host app renders a working chat with a stock theme.

### Phase 5 — iOS adoption + external reuse harness
- Point iOS at `AllnighterChatCore` (and `AllnighterChatUI` where the platform allows), retiring the
  duplicated `Conversation*` view code in favor of the shared surface + an iOS `ChatTheme`.
- Publish `AllnighterChatCore` + `AllnighterChatUI` as their own versioned SwiftPM package (own repo
  or a `Packages/` product with a stable public API + semver), with a README and the sample app so
  other products can add one dependency and get chat.
- **Exit:** at least one other app (or the sample) embeds the module with only a `ChatTheme` +
  `ChatModelResolving` + workspace root, and gets streaming warm chat.

---

## 6. Module file set (what moves into `AllnighterChatCore`)

**Models (from `AllnighterCore`):** `WorkThread`, `ThreadTurn`, `ThreadContextPacket`,
`ThreadGetProjection`, `ThreadAttachment` (+ refs/indexes), `ThreadFileReference`,
`ResolvedThreadAttachment`, `WorkerAnswer`/`WorkerAnswerStatus`, `WorkerSessionCapture`/
`ExternalWorkerSession`, `WorkerSpawnDiagnostics`, `Model`, `DriverRegistry`, `DriverManifest`,
`Enums`, `CoreJSON`, `JSONValue`, the three PURE wire types `ClaudeMessage`/`CodexMessage`/
`ACPMessage`, `AllnighterPaths`, `TextUtil`.

**Services (from `AllnighterEngine`):** `ThreadSendCoordinator`, `WorkerChatCoordinator`,
`WorkerRunner` (+`WorkerRunOutcome`), `ThreadContextBuilder`, `ThreadStore` (+`ThreadStoreWriteSerializer`,
`ThreadFlockLock`, `ThreadMarkdown`, `ThreadSendIdempotencyStore`), the streaming stack
(`WorkerStreaming` + all `*StreamParser`s + `StreamingPartialBuffer`/`StreamDebugLog`), the command
runners (`CommandRunner`/`SubprocessCommandRunner`/`StreamingCommandRunner`/`MockCommandRunner`),
`DriverConcurrencyGate`, `CapacityClassifier`/`CapacityObservation`, the attachment path
(`ThreadAttachmentStore`/`Resolver`, `AttachmentIngestor`, `WorkspaceAttachmentStaging`,
`AttachmentDeliveryRenderer`, `ChatImageIntent`, `ComposerPasteContract`), `WorkerImageInvoker`/
`WorkerImageCapture`.

**Warm layer (Phase 2):** `WarmWorkerPool`, `WarmWorker`, `WarmWorkerCapability`, `WarmSessionDriver`
impls, `ACPTransportProfile`, `ProcessACPTransport`, `ExternalWorkerSessionStore`.

**Stays in the app spine (NOT in the module):** `RunService`, `RunStore`, all Team/Catalog/Council/
Pair/Slice/Design/Review/Stage/FollowUp/Finalizer coordinators (`CatalogRunCoordinator`,
`TeamResolver`, `TeamCatalog`, `ModelCatalog`, `SkillCatalog`, `BuiltInTeams`, `PanelPreset`,
`PairCoordinator`, …), `Project*` spine, the entire `Remote*`/`Supabase*`/`DirectMode*` transport,
`RemoteThreadProjection`, and the MCP surface. The three seam resolvers
(`ThreadImageSeedResolver`, `ProjectFileReferenceResolver`, `PendingCapacityResumeWriter`) stay in the
app as implementations of the module's injected protocols.

---

## 7. Risks & open questions

- **Behavior parity on the GUI cutover (Phase 3).** The live app uses Path B today; moving to Path A
  must preserve Auto-model routing, warm latency, mutating write-lock behavior, and image-gen. This is
  the highest-risk step — gate it behind `ThreadStreamingPerformanceTests` + a GUI proof, and keep
  Path B reachable until parity is proven.
- **Write-lock / mutating safety.** Path B runs single-worker chat under the per-root write lock and
  `RunWriteLockRegistry`. If module chat can mutate the repo, the lock discipline
  ([`allnighter-pending-execute-lane-safety`], [`allnighter-no-git-management`]) must move with it or
  be injected. Decide: is module chat read-only-safe, or does it carry the mutating lock? (Recommend:
  carry a minimal injected `WriteLockProviding` seam so hosts opt in.)
- **Turn schema (D4).** Confirm we ship inert heavy kinds for v1 vs. the generic escape hatch.
- **iOS is remote-first.** iOS chat is a thin client over the Mac engine; `AllnighterChatCore`'s
  local send path may not run on-device. iOS may consume only `AllnighterChatUI` + a remote transport
  adapter. Clarify how much of iOS actually reuses the module vs. just the views.
- **Package home.** Decide same-repo `Packages/` product vs. separate repo. Separate repo gives the
  cleanest "add one dependency" story for other apps but adds release friction; same-repo is simpler
  now. (Recommend: same-repo `Packages/` first, extract to its own repo at Phase 5 once the API is
  stable.)

---

## 8. Non-goals

- No Send-to-Team, team fan-out, design/review boards, or project-manager loop in the module.
- No API keys / BYOK — the module drives the user's existing CLI logins, same as Allnighter
  ([`allnighter-no-api-keys`]).
- No git management in the module ([`allnighter-no-git-management`]).
- Not rebuilding the markdown renderer — `AllnighterMarkdown` is already standalone and is a
  dependency, not a rewrite.
</content>
</invoke>
