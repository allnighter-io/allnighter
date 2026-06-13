# 00 — Architecture and Tech Stack (the constitution)

Status: **Locked for v1.** Every phase obeys this doc. Changes here are
architecture changes and must be recorded with a dated note in §14.
Owner: Founder
Updated: 2026-06-13

> This doc fixes *how* Allnighter is built so no phase has to re-decide the stack.
> It defines the technologies, the repo layout, the system architecture, the
> cross-cutting runtime contracts (events, recovery, concurrency, completion
> detection, git, ports, processes, previews), the safety/trust model, and the
> test/quality gates. Read this before any phase.

---

## 1. Platform Targets and Languages

| Concern | Decision | Rationale |
| --- | --- | --- |
| Languages | **Swift 6** (strict concurrency), with small **Node.js** sidecar for browser automation only | One language across Mac/iOS/shared/relay; Node only where Playwright is the standard. |
| Mac OS floor | **macOS 14 Sonoma+** | Mature `MenuBarExtra`, `Observation`, modern concurrency. |
| iOS floor | **iOS 17+** | Mature ActivityKit/Live Activities, `Observation`, App Intents. |
| UI | **SwiftUI** primary; AppKit only where required (menu bar item, `NSWindow` tuning, file pickers) | Native, shared idioms, fast. |
| Async model | **Swift Concurrency** (`async/await`, `actor`, `AsyncStream`, structured tasks) | The orchestration core is concurrent by nature; actors give safe shared state. |
| State observation | **`@Observable`** (Observation framework) in apps | Modern, less boilerplate than `ObservableObject`. |

The Mac app is **unsandboxed by design** (it must run local developer tools,
spawn processes, and access enrolled repo paths). It is **notarized** and
distributed as a DMG outside the App Store. The iOS app is sandboxed, ships via
TestFlight then App Store.

---

## 2. Repository Layout

```text
/  (this repo — rename target: "Allnighter")
├── Packages/
│   └── AllnighterCore/          # SPM library: models, state machines, protocol, fixtures
│       ├── Sources/AllnighterCore/
│       ├── Tests/AllnighterCoreTests/
│       └── Package.swift
├── Apps/
│   ├── AllnighterMac/           # macOS app target (the factory + command center)
│   └── AllnighteriOS/           # iOS app target (the floor manager)
├── Services/
│   └── AllnighterRelay/         # Swift server (Hummingbird) — Milestone F only
├── Sidecars/
│   └── capture/                 # Node + Playwright: screenshots, video, QA (Milestone B/E)
├── Fixtures/                    # shared JSON fixtures (A–G, see §8)
├── scripts/                     # check.sh, doctor, codegen, project generation
└── docs/phases/                 # these docs (source of execution truth)
```

**Project generation:** use **XcodeGen** (`project.yml` per app) so `.xcodeproj`
files are generated, never hand-merged. This keeps agent-driven edits clean and
diffable. (Tuist is an acceptable alternative; pick one and stay consistent.)
`AllnighterCore` is **pure SPM** so `swift test` runs without Xcode.

**Workspace:** a single `Allnighter.xcworkspace` references the package and both
apps. `scripts/check.sh` runs `swift test` for Core plus `xcodebuild test` for
each app scheme that exists.

---

## 3. Dependency Choices (SPM)

Keep dependencies few and boring. Approved set for v1:

| Need | Library | Notes |
| --- | --- | --- |
| Local persistence | **GRDB.swift** (SQLite) | Typed, fast, migrations, observation. **Not** SwiftData — we need server-grade control, FTS, and cross-process reads. |
| Embedded HTTP + WebSocket server (Mac & relay) | **Hummingbird 2** (SwiftNIO-based) | Lightweight, async/await native, runs inside the Mac app. |
| WebSocket client (iOS/Mac) | `URLSessionWebSocketTask` (Foundation) | No dependency needed. |
| Local network discovery | **Network.framework** (`NWListener`/`NWBrowser`, Bonjour `_allnighter._tcp`) | First-party, no dep. |
| Crypto / device identity | **CryptoKit** (Ed25519 keys, sealed boxes) | First-party. |
| Logging | **swift-log** + `OSLog` | Structured logs feed Diagnostics. |
| Process/PTY (interactive agents, later) | thin in-house `PTY` wrapper over `forkpty` (or vendored **SwiftTerm**/**Subprocess** if needed) | v1 prefers headless modes (§9.3) and avoids PTY where possible. |
| Browser automation | **Playwright** (Node sidecar) | Screenshots, video, QA. Industry standard; reused by Phase 18. |

No third-party git library. **Shell out to the system `git`** via a typed
`GitClient` actor (§9.4) — git's worktree and `merge-tree` features are most
reliable from the real binary, and SwiftGit2/libgit2 worktree support is weak.

---

## 4. System Architecture

```text
                 +---------------------------------+
                 |        Allnighter iOS           |
                 | capture · feed · pick · morning |
                 +----------------+----------------+
                                  |
                  Bonjour + WebSocket (LAN)  /  Relay (remote, Milestone F)
                                  |
                 +----------------v----------------+
                 |        Allnighter Mac           |   <-- owns ALL execution state
                 |  (factory + command center)     |
                 +----------------+----------------+
        Local API (Hummingbird) · State store (GRDB/SQLite) · Event bus
                                  |
   +-------------------+----------+-----------+--------------------+
   | Lane Manager      | Agent Driver Runtime | Preview/Artifact   | Scheduler /
   | (worktrees,       | (Claude/Codex/shell/ | (port broker,      | Quota Harvester
   |  branches, ports, |  local drivers,      |  capture sidecar,  | · Scorecards
   |  process groups)  |  smoke tests)        |  artifact store)   | · Taste memory
   +---------+---------+----------+-----------+---------+----------+
             |                    |                     |
   +---------v--------+ +---------v--------+  +---------v--------+
   | Lane A (Claude)  | | Lane B (Codex)   |  | Lane C (local/…) |
   | branch + worktree| | branch + worktree|  | branch + worktree|
   | + port + procs   | | + port + procs   |  | + port + procs   |
   +------------------+ +------------------+  +------------------+
```

### Ownership rules (hard)

- **The Mac owns execution state.** SQLite on the Mac is the source of truth for
  projects, lanes, races, councils, artifacts, landings, preferences, scorecards.
- **The iPhone owns mobile capture and decision UX.** It is a thin, resilient
  client of the Mac's API. It stores no agent secrets and no repo code.
- **`AllnighterCore` owns semantic models and protocol contracts.** Both apps and
  the relay depend on it. It contains no I/O — pure types, state machines,
  encode/decode, and fixtures.
- **The relay never stores code** and is never the source of repo truth. It
  carries pairing metadata, push, and command/preview tunneling only.

### Component responsibilities (Mac)

- **Local API server** (Hummingbird): the contract-first REST + WebSocket surface
  in §6, consumed by iOS and (later) relay.
- **State store** (GRDB): persistence + change observation that drives the event
  bus.
- **Event bus**: a single append-only event log (monotonic sequence numbers) that
  every surface subscribes to (§5).
- **Lane Manager** (§9.1–9.5): worktree/branch/port/process lifecycle + recovery.
- **Agent Driver Runtime** (Phase 04): launches drivers, normalizes output to
  events, runs smoke tests, detects completion (§9.3, §9.6).
- **Preview/Artifact** (Phase 06): port broker, preview supervisor, capture
  sidecar, artifact storage.
- **Scheduler / Quota Harvester / Scorecards / Taste** (Milestone E): routing and
  intelligence.

---

## 5. Event and Streaming Contract (cross-cutting)

Mobile connections drop constantly; the UI must never lose or duplicate events.
This contract is implemented in `AllnighterCore` + Phase 08.

- **Append-only event log.** Every state change appends an `Event` with a
  **monotonic `seq: Int64`** (per Mac, global across projects) and a `ts`.
- **Resumable stream.** Clients connect with `?since=<seq>`; the server replays
  events `> since`, then streams live. Clients persist the last `seq` they saw.
- **At-least-once + idempotent apply.** Events carry a stable `id`. Clients
  **dedupe by `id`** and apply idempotently (apply = upsert into local view
  model). Never assume exactly-once.
- **Envelope:**

```json
{
  "id": "evt_01H...",
  "seq": 10472,
  "ts": "2026-06-13T05:12:09Z",
  "kind": "lane.status_changed",
  "project_id": "project_kansobooks",
  "lane_id": "lane_a17f9c",
  "payload": { "from": "running", "to": "building_preview" }
}
```

- **Event kinds** (extensible enum in Core): `project.*`, `task.*`, `lane.*`,
  `race.*`, `council.*`, `artifact.*`, `landing.*`, `worker.*`,
  `preference.*`, `schedule.*`, `diagnostic.*`.
- **Commands** are requests (REST or WS) that *produce* events; the UI updates
  only from events, never from optimistic local mutation of truth (optimistic
  *presentation* is fine, reconciled by the next event).
- **Snapshots.** `GET /projects/:id/snapshot?since=<seq>` returns current entity
  state + the latest `seq` so a cold client can hydrate without replaying all
  history.

---

## 6. API Surface (contract-first)

Defined in `AllnighterCore` as typed request/response + the REST routes below.
**Build the contract and fixtures before either app consumes it** so Mac and iOS
teams can work in parallel (§8).

```text
GET    /health
POST   /pair/begin            # Mac shows code; returns pairing challenge
POST   /pair/complete         # iOS submits pubkey + code -> trusted device
GET    /projects
GET    /projects/:id
GET    /projects/:id/snapshot
POST   /projects                       # enroll a repo
PATCH  /projects/:id                   # protected paths, commands, standing orders
POST   /projects/:id/tasks
POST   /tasks/:id/dispatch             # single lane
POST   /tasks/:id/race                 # N lanes from one base commit
POST   /tasks/:id/council
POST   /races/:id/pick
POST   /outputs/:id/implement          # picker-as-prompt
POST   /lanes/:id/stop
POST   /lanes/:id/nudge
GET    /lanes/:id/artifacts
POST   /landings/:id/land
POST   /landings/:id/revert
POST   /control/stop-all               # global kill switch
GET    /workers
GET    /events/stream?since=<seq>      # WebSocket upgrade
```

**First integration milestone** (proves the contract end to end):

```text
iOS sends "dispatch race" -> Mac creates lane records -> iOS receives lane events.
```

---

## 7. Data Model (owned by AllnighterCore)

Entities (full Codable structs; JSON shapes are the fixtures in §8). Core
defines: `Project`, `Task`, `Lane`, `Worker` (agent), `Driver`, `Race`,
`Council`, `Artifact`, `Landing`, `PreferenceEvent`, `WorkerScorecard`, `Event`,
plus enums `LaneStatus`, `RiskTier`, `CapabilityLevel`, `DispatchMode`,
`OutputType`, `EventKind`.

Canonical examples:

```json
// Project
{
  "id": "project_kansobooks", "name": "KansoBooks",
  "repo_path": "/Users/mike/Documents/GitHub/KansoBooks",
  "default_branch": "main",
  "protected_paths": ["Billing/", "Secrets/", ".env"],
  "standing_orders": ["Never touch billing without approval.",
                      "Always produce screenshots for UI changes.",
                      "Prefer small reversible branches."],
  "preview_command": "npm run dev -- --port {{PORT}}",
  "test_command": "npm test"
}
// Lane
{
  "id": "lane_a17f9c", "project_id": "project_kansobooks",
  "task_id": "task_dashboard_premium", "agent_id": "claude_code",
  "branch": "allnighter/dashboard-premium/a17f9c",
  "worktree_path": ".../Worktrees/lane_a17f9c",
  "base_commit": "abc123", "status": "ready",
  "ports": { "web": 43120 }, "preview_url": "http://localhost:43120/lane/a17f9c",
  "artifact_ids": ["artifact_screenshot_001"], "risk_tier": "green_land"
}
// PreferenceEvent
{
  "id": "pref_01H...", "project_id": "project_kansobooks",
  "event_type": "picked_winner", "context_type": "race",
  "chosen_lane_id": "lane_a17f9c",
  "rejected_lane_ids": ["lane_b93d2e", "lane_c44a11"],
  "user_note": "Best balance of polish and density.",
  "derived_memory": ["Prefers premium UI that preserves information density."]
}
```

### Lane state machine (single source of truth; tested in Phase 01)

```text
created -> preparing -> running -> awaiting_input -> building_preview
        -> qa_running -> ready -> landing -> landed
Failure/terminal: failed | blocked | conflicted | killed | abandoned | expired
```

All transitions are validated in Core (`Lane.canTransition(to:)`) with unit
tests covering every legal and illegal edge.

### Hidden on-disk layout (Mac)

```text
~/Library/Application Support/Allnighter/
  Projects/project_<id>/
    config.json
    state.sqlite                  # GRDB store (truth)
    Worktrees/lane_<id>/          # git worktree (outside the user's repo)
    Artifacts/lane_<id>/          # screenshots, recordings, summaries, redacted transcript
    Logs/lane_<id>/               # agent.stdout/stderr, supervisor.log
```

---

## 8. Fixtures and Parallel-Team Contract

`AllnighterCore` ships JSON fixtures so Mac and iOS teams build against the same
data before either runtime is complete. Minimum set:

```text
A: one project, no lanes, three available workers
B: one active single-agent lane
C: one three-way race with screenshots
D: one council verdict with dissent
E: one green-tier landing card
F: one assisted-tier landing card
G: one Morning Pull digest
```

Each fixture has a round-trip decode/encode test. iOS renders entirely from
fixtures until live API exists; Mac validates its API output against the same
fixtures.

---

## 9. Cross-Cutting Runtime Contracts

These are the hard parts. Specify them once here; phases implement them.

### 9.1 Lane lifecycle and the core invariant

- On dispatch, the Lane Manager creates, **in this order**: branch name → pinned
  `base_commit` → `git worktree add` → lane record (status `preparing`) → log dir
  → artifact dir → port allocation → process supervision group → preview URL.
- **Invariant: no agent process ever runs with cwd inside the user's active repo
  working tree.** All agent cwd = the lane worktree path. Enforced by the Lane
  Manager, never by the driver.
- Branch naming: `allnighter/<task-slug>/<short-lane-id>` (deterministic,
  readable, collision-resistant), e.g. `allnighter/dashboard-premium/a17f9c`.

### 9.2 Crash recovery and reconciliation (required for trust)

On Mac app launch, a **Reconciler** runs before serving the API:

1. Load persisted lanes from SQLite.
2. For each non-terminal lane, check: does the worktree exist? Is the supervised
   process group alive? Is the port still held?
3. Reconcile: a lane whose process died moves to `failed` (with reason); a lane
   whose worktree is missing moves to `abandoned`; orphaned worktrees with no
   record are listed in Diagnostics for cleanup, never auto-deleted.
4. Never silently lose user work; never auto-run destructive git on startup.

### 9.3 Headless-first agent invocation

v1 invokes agents in **headless / print / non-interactive** modes wherever the
tool supports it (e.g. `claude -p`, `codex` non-interactive). This avoids PTY
complexity and makes output capture deterministic. Interactive/approval flows and
true PTY attach are a **later capability**, not v1. Drivers declare whether they
need a PTY; the runtime refuses PTY-only drivers in v1 with a clear message.

### 9.4 Git contract (`GitClient` actor, shells out to `git`)

- **Worktree:** `git worktree add <path> -b <branch> <base_commit>`;
  `git worktree remove`; `git worktree prune`.
- **Base commit pinning:** a race resolves the target branch tip to a SHA once;
  all race lanes branch from that same SHA (deterministic comparison).
- **Merge simulation (no working-tree side effects):** use
  `git merge-tree --write-tree <target> <branch>` to detect conflicts and produce
  the merged tree for the risk classifier — never a real checkout/merge to test.
- **Landing:** fast-forward or `--no-ff` merge into the target branch via a
  dedicated operation; capture the merge commit SHA.
- **Revert:** `git revert -m 1 <merge_sha>` producing a clean rollback commit.
  Never `reset --hard` or delete user work. Every land writes revert metadata
  (merge SHA, branch, task/lane id, artifacts, summary).
- **Dirty active tree:** detected and surfaced; lanes never touch it (the whole
  point), but the user is told their active edits are untouched.

### 9.5 Port broker

- Allocates stable ports per lane from a configurable range (default
  `43100–43999`); persists assignments; releases on lane teardown; probes for
  availability before assigning. Friendly URLs: `http://localhost:<port>/lane/<id>`
  locally, `http://<host>.local:<port>/...` on LAN, relay tunnel when remote.

### 9.6 Process supervision, completion detection, and kill

- Each lane owns a **process group**. Spawn agent/preview/test processes into that
  group (via `posix_spawn` with `POSIX_SPAWN_SETPGROUP`, or a launch helper) so the
  whole tree can be terminated as a unit.
- **Completion detection** is per-driver and layered (first that fires wins):
  (a) process exit code; (b) a driver-declared **sentinel** in output
  (e.g. `ALLNIGHTER_DONE`); (c) structured JSON "done" event for protocol agents;
  (d) **idle timeout** (no output for N seconds) as a backstop. Each driver
  manifest declares which signals it supports.
- **Stop / kill switch:** `POST /control/stop-all` and per-lane stop send
  termination to the whole process group, mark lanes `killed`, **keep worktrees
  intact** for inspection, and **never touch the user's main branch.**

### 9.7 Preview and screenshot pipeline (Phase 06 / 18)

1. Run the project's `preview_command` (port templated in) in the lane worktree.
2. **Readiness probe:** poll the port until it accepts TCP *and* returns HTTP
   200 (configurable path), with a timeout → `failed` with a clear reason.
3. Capture via the **Node + Playwright capture sidecar**: screenshot(s) at
   declared viewports, optional short video, save to the lane Artifacts dir,
   register `Artifact` records.
4. The same sidecar drives QA (Phase 18). Native-app preview capture is post-v1;
   v1 demo targets web apps.

### 9.8 Driver manifest schema (Phase 04 / 19)

Drivers are thin, versioned JSON manifests + a small Swift adapter. Example:

```json
{
  "id": "claude_code",
  "manifest_version": 3,
  "display_name": "Claude Code",
  "capability_level": "headless_cli",
  "detect_command": "claude --version",
  "smoke_test_command": "claude -p \"Reply with ALLNIGHTER_READY\"",
  "launch_template": "claude -p {{prompt}}",
  "completion_signals": ["exit_code", "idle_timeout"],
  "supports_streaming": true,
  "supports_json_events": false,
  "supports_resume": true,
  "needs_pty": false,
  "quota_estimate": "best_effort",
  "default_categories": ["planning", "refactor", "architecture", "copy"]
}
```

- **Smoke test gate:** on launch (and on demand), each enrolled worker runs its
  smoke test; failure marks the worker unhealthy and removes it from routing with
  a visible reason. This is the churn defense.

### 9.9 Worker model and capability levels

| Level | Name | Capabilities | Examples |
| --- | --- | --- | --- |
| 1 | Headless CLI | launch, prompt, stream, stop, detect completion | Claude Code, Codex CLI, Grok, Gemini CLI, Aider |
| 2 | Protocol | structured protocol, approvals, events, resumable | ACP / app-server / SDK agents |
| 3 | IDE handoff | open prepared lane in IDE, write work-order file | Cursor, Antigravity, VS Code |
| 4 | UI automation | accessibility/browser driven | experimental only |
| L | Local model | OpenAI-compatible / Ollama / LM Studio / llama.cpp | private workers (Phase 19) |

v1 focuses on **Level 1, Level 2, and read-only Level L**. Level 3 is valuable as
a time-saver (prepared lane handoff) even without full automation. Level 4 is out
of scope for core flows. A **Worker** is modeled as `{machine, runtime/driver,
model}` so multi-machine and local workers share the same abstraction.

---

## 10. Safety and Trust Model (enforced from the first dispatch, not Phase 23)

Every phase that touches dispatch, files, landing, transport, or transcripts must
honor these. This section is itself a contract.

- **Core invariant** (repeated because it matters most): no agent writes to the
  user's active working directory. All work is in lane worktrees.
- **Protected paths.** Per project (secrets, env, billing, auth, migrations,
  deploy config, legal text, user-selected). Enforced **twice**: at prompt
  construction (the work order tells the worker) *and* at landing (a lane that
  touched a protected path is downgraded to draft-only and requires explicit
  approval). Touch detection uses the diff, not trust.
- **Standing orders** are applied before dispatch, during prompt construction, and
  before landing.
- **Kill switch.** Global `stop-all` on both Mac and iOS terminates all supervised
  process groups, marks lanes `killed`, preserves worktrees, never touches main.
- **Secrets.** iOS never stores agent credentials (kept in Mac Keychain, injected
  as env at spawn). Transcripts are **redacted before they leave the Mac** for
  phone display. Env files protected by default. Artifacts scanned for obvious
  secrets before any sync/tunnel.
- **Risk tiers** gate landing (§Phase 07): `green_land` (auto-eligible, one-tap),
  `assisted_land` (repair agent), `draft_only` (branch/PR only — protected paths,
  schema/billing/secrets, broad/speculative changes).
- **Pairing/auth.** Device generates an **Ed25519 keypair**; pairing via a code/QR
  shown on Mac; iOS submits its pubkey; the Mac stores the trusted device.
  Subsequent connections use TLS (pinned self-signed cert) + a signed challenge.
- **Relay privacy.** Local-first by default. The relay stores no code, carries
  metadata/push/commands and (opt-in) preview tunneling only, via a **reverse
  tunnel from the Mac** — never a source upload. All relay use is an explicit
  toggle.
- **Local-model safety** (Phase 19). "Local" ≠ "trusted." Local workers start
  read-only; code-writing requires explicit enablement and begins draft-only;
  local servers exposed on LAN require pairing/auth; public-internet exposure is
  warned against; local outputs are scored separately.
- **Quota honesty.** Estimated values are labeled "estimated" / "looks about …",
  never stated as exact (§Phase 17).

---

## 11. Scheduling and Resource Governance (cross-cutting; detailed in Phase 17/19)

- A **Lane Scheduler** enforces a max concurrent-lane cap (default = `min(cpu-2,
  configurable)`) with backpressure; excess dispatches queue.
- **Resource governor** considers CPU/memory pressure, thermal state, power
  source, and user foreground activity before starting heavy work.
- **Cloud scheduler** optimizes quota window, limits, model strength, cost,
  latency. **Local scheduler** optimizes machine availability, power/thermal,
  memory, foreground activity, model load time, privacy, task suitability — local
  workers have a distinct profile (e.g. "only when idle or plugged in").

---

## 12. Testing and Quality Gates

- **`AllnighterCore`:** `swift test` — model round-trips, every lane state
  transition (legal + illegal), fixture decode, protocol envelope encode/decode.
- **Mock drivers and mock client:** a `MockDriver` (scripted output + completion
  signal) and a `MockiOSClient` let Mac logic be tested without real agents or a
  real phone. The relay/server is integration-tested against the mock client.
- **Works Test per phase:** each phase doc states a concrete, runnable Works Test;
  the phase is not done until it passes.
- **Green wall** (`scripts/check.sh`): `swift test` + `xcodebuild test` for each
  existing app scheme. Closeout names any missing proof explicitly.
- **Determinism guardrail:** recurring correctness questions become deterministic
  checks (types, Codable, parser fixtures, state-machine tests), not model
  judgment. Use agents for judgment-heavy work only.

---

## 13. Distribution (detailed in Phase 23)

- **Mac:** notarized DMG, Developer ID signed, hardened runtime with the
  entitlements required to spawn processes and read enrolled paths; menu bar +
  command center; auto-update channel.
- **iOS:** TestFlight first, App Store later.
- **Relay:** containerized Hummingbird service on a small VPS or equivalent; APNs
  for push. No code storage.
- **Doctor:** `scripts/doctor` and an in-app Diagnostics tab check git presence,
  driver smoke tests, port availability, Node/Playwright sidecar, permissions
  (Full Disk Access, Local Network), and relay reachability.

---

## 14. Appendix — Functional Requirement IDs

Phase exit gates reference these IDs. They are the acceptance checklist for the
Mac and iOS apps.

### Mac (MAC-*)

| ID | Requirement |
| --- | --- |
| MAC-1 | Enroll local git repositories explicitly. |
| MAC-2 | Detect dirty main working tree and explain that lanes will not touch it. |
| MAC-3 | Create, track, and clean up hidden worktree lanes. |
| MAC-4 | Launch agent drivers in lane working directories. |
| MAC-5 | Stream normalized lane events into local state. |
| MAC-6 | Run project-specific setup, build, test, and preview commands. |
| MAC-7 | Capture screenshots/videos of previews. |
| MAC-8 | Allocate unique ports per lane. |
| MAC-9 | Expose local API for iOS and relay. |
| MAC-10 | Show race comparisons natively on Mac. |
| MAC-11 | Support "Implement This" from Mac-side council or race outputs. |
| MAC-12 | Support landing queue and one-tap revert. |
| MAC-13 | Support global pause/kill switch. |
| MAC-14 | Maintain worker scorecards. |
| MAC-15 | Maintain preference ledger and project memory. |
| MAC-16 | Run driver smoke tests and show worker health. |
| MAC-17 | Communicate quota estimates honestly as estimates. |
| MAC-18 | Keep code local unless the user enables a relay/tunnel feature requiring metadata transfer. |

### iOS (IOS-*)

| ID | Requirement |
| --- | --- |
| IOS-1 | Pair with Mac app via local network or relay. |
| IOS-2 | Capture voice and text into editable work-order interpretation. |
| IOS-3 | Show project backlog and dispatch actions. |
| IOS-4 | Show active lanes with plain-language statuses. |
| IOS-5 | Render race drafts as swipeable cards with screenshots and preview links. |
| IOS-6 | Let the user choose, combine, remix, challenge, or implement. |
| IOS-7 | Let a selection immediately dispatch implementation. |
| IOS-8 | Show landing queue with risk tiers. |
| IOS-9 | Provide one-tap global pause/kill. |
| IOS-10 | Provide push notifications and Live Activities for long-running lanes. |
| IOS-11 | Batch notifications during quiet hours. |
| IOS-12 | Show Morning Pull as a rewarding daily ritual. |
| IOS-13 | Keep typing optional in core flows. |
| IOS-14 | Support Share Sheet capture from screenshots, notes, GitHub, browser, app reviews. |
| IOS-15 | Never store agent secrets on device. |

---

## 15. Architecture Decision Log

| Date | Decision | Note |
| --- | --- | --- |
| 2026-06-13 | Initial constitution locked | Swift 6 / SwiftUI; GRDB; Hummingbird; Network.framework Bonjour; shell-out git; headless-first agents; Playwright sidecar; XcodeGen. Supersedes CLI Loci docs. |

> Append a row here whenever a phase needs to change a locked decision. Do not
> change the stack silently inside a phase.
