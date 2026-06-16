# Mac Standalone App And Background Coordinator

Status: Draft forward phase
Owner: Founder + Mac + Shared Core + CLI + iOS
Truth owner: AllnighterCore (product semantics); background coordinator (process
lifetime + durability only)
Updated: 2026-06-15

## Founder Intent

Allnighter should not feel like a tiny menu-bar utility. It is the floor manager
for an overnight AI-agent factory: the place users start work, watch teams run,
review results, and control whether their Mac is available to their phone and
other agents.

The menu bar may remain useful as a status/control surface, but the product
shell should become a regular Mac app with a Dock presence and first-class
window. Long-running and remote workflows should be owned by an explicit
background coordinator, not by fragile window lifetime.

## Current State

The shipped Mac shell lives at `Apps/AllnighterMac` (see
`docs/mvp/03_Mac_App_And_Run_Loop.md`), built as a menu-bar-first app with
`LSUIElement = true`. This phase converts that shell to a regular Dock app; it
does not rebuild it. The existing main window, `AppModel`, and `RunEvent` wiring
are preserved.

## Decision

Forward product direction:

```text
Allnighter.app       = standalone Mac app / visual floor manager
alln                 = foreground CLI and proof surface
background coordinator = resident Mac process for long/remote work
menu bar item        = optional status and quick controls, not the product shell
```

The current MVP menu-bar app is historical foundation, not the final shell.
Future Mac app work should execute against this doc.

## Why This Is Separate From The CLI Doc

`CLI_Product_Spine.md` answers how humans and agents command Allnighter.

This doc answers when Allnighter exists as a Mac process:

- Does closing a window stop work?
- Can iOS reach the Mac?
- Where do notifications come from?
- Who owns long-running run state?
- Is the app a Dock app or a menu-bar-only app?

Those are shell/lifecycle decisions, not CLI grammar.

## Product Law

```text
The app is the floor manager.
The coordinator keeps the floor open.
The menu bar is a status light.
```

Do not build new UX that assumes Allnighter is menu-bar-only.

## Process Model

| Process/surface | Role | Runs when |
| --- | --- | --- |
| `Allnighter.app` | Standalone GUI: composer, team runs, threads, boards, setup, history, settings. | User launches it; may reopen windows over resident truth. |
| `alln` | CLI command/proof surface. Foreground by default. | User/agent runs a command. |
| Background coordinator | Resident host for long-running, resumable, remote, notification, and MCP/local API work. Owns process lifetime + durability, not product semantics. | Started on demand by work that outlives the foreground session (`team start`, Pending/Away Mode, iOS) or a pending notification; lives while it has obligations. |
| Menu bar item | Status, quick open, current-run controls, stop/pause, coordinator state. | Optional while app/coordinator is active. |

**Coordinator process model (decided 2026-06-15):** the background coordinator is
`alln serve` — the `alln` binary running in resident mode, hosting
`AllnighterCore` plus the loopback transports. It is launched on demand and, when
start-at-login is enabled, by a user-level LaunchAgent/login item that runs
`alln serve`. The GUI and iOS are clients of it over the loopback HTTP/WS surface.
It is **not** the SwiftUI app process and **not** a separate third binary.

Why: it keeps `AllnighterCore` the single truth owner and the GUI a pure presenter
even for resident work; it gives headless capability for iOS/overnight/MCP without
running the full SwiftUI app; it reuses the binary already shipped for CLI M1 (no
third binary to sign/notarize/version); and it isolates GUI and coordinator
crashes/updates. A separate helper's only real benefit — LaunchAgent lifecycle and
crash survival — is obtained by launchd running `alln serve`, so no distinct
helper binary is needed.

Single-writer rule: when the coordinator is alive it is the sole run-journal
writer, and the GUI routes resident-eligible runs to it rather than also hosting
Core in-process. With resident mode off, foreground runs run in-process through
the shared Core command handlers.

Product copy should say "Keep Allnighter running in the background," not expose
implementation nouns unless needed for troubleshooting.

## Lifecycle Rules

Resident mode is demand-driven, not a global default. The work decides whether a
process must stay alive — not a toggle the user reasons about in the abstract.

- **Record durability is the journal's job, not a live process's.** Every run —
  foreground or resident — writes its journal incrementally, so a completed run is
  always recoverable from history after everything closes. A run whose owning
  process dies mid-flight resolves to `interrupted` on next read; it never
  vanishes and never reports a false `running`. **This rule does not hold yet:**
  the shipped journal is one-shot-at-end (see the journal-durability note at the
  top of `CLI_Product_Spine.md`) and must be made incremental first.
- **The coordinator starts on demand** for any work that can outlive the
  foreground session: `alln team start` / async runs, Pending/Away Mode,
  iOS-initiated runs, or anything with a pending notification. A short
  `alln team "..."` the user watches finish does not start it.
- **The coordinator lives while it has obligations** — unfinished owned runs or
  undelivered notifications — then exits, or stays if start-at-login is enabled.
  "Keep Allnighter running" is a consequence of outstanding work, not an abstract
  preference.
- **Closing the final window:** if the coordinator has live obligations, the app
  keeps it running and says so (warn on quit). If nothing is outstanding, closing
  quits cleanly — no idle daemon.
- Foreground CLI commands do not require the coordinator.
- Closing the main window must not silently kill a coordinator-owned run.
- Quitting Allnighter while runs are active must make the consequence explicit:
  stop running work, or keep the coordinator running if that mode exists.
- If resident mode is off, iOS and external tools see the Mac as offline.
- If the Mac sleeps, shuts down, loses network, or the coordinator stops, clients
  show that exact state. Never fake liveness.
- Reopening the app reads current truth from the run journal/coordinator, not
  from stale SwiftUI state.

## Background Coordinator Responsibilities

The coordinator owns no product semantics. `AllnighterCore` remains the truth
owner; the coordinator owns the *process lifetime and durability* of that truth —
keeping the run journal alive, replaying its event stream, and reporting liveness.

The coordinator hosts and persists (all Core-defined):

- run queue and active-run registry;
- durable run journal and resumable event stream;
- local HTTP/WebSocket surface when enabled;
- MCP long-running handoff when enabled;
- iOS cloud/direct transport handoff when enabled;
- notification delivery — the OS/push call. Notification policy and content
  remain owned by `threads/02_Notifications.md`;
- stop/cancel requests;
- coordinator health reported by `alln doctor --json`.

The coordinator does not own:

- model/source truth outside the shared Core registry;
- GUI-only state;
- arbitrary shell access;
- user credentials beyond approved source invocation environment;
- final authorization for destructive/high-risk actions without explicit user
  approval.

## Standalone App Requirements

Forward Mac shell requirements:

- regular Dock app, not LSUIElement-only;
- first window opens on launch unless the user has chosen background-only start;
- menu bar status item is optional/secondary;
- app can reopen a running session from Dock, menu bar, CLI deep link, or iOS;
- settings include background coordinator state and start-at-login control;
- setup explains what background mode enables: iOS, overnight runs,
  notifications, and remote agent calls.

## Menu Bar Role

Allowed menu bar jobs:

- show coordinator/run status;
- open the main window;
- start a quick team prompt if a compact affordance is justified;
- stop/pause an active run;
- show Mac online/offline status for iOS;
- expose "Quit Allnighter" with honest active-run handling.

Not allowed:

- menu bar as the only primary product surface;
- hiding setup, team customization, work threads, or history behind tiny menu
  affordances;
- silently running remote-control capability without a visible setting.

## Trust And Permissions

- User-level process only. No root daemon.
- No Full Disk Access by default.
- Local-only surfaces bind to loopback by default.
- iOS remote commands are typed Allnighter commands, never a remote shell.
- MCP/local API clients require explicit approval before use.
- Background mode must be revocable from the app and diagnosable from
  `alln doctor --json`.
- Every remote/background-originated run records origin and origin agent/client.

## Relationship To CLI And iOS

`CLI_Implementation_Contract.md` owns command schemas and proof gates. This doc
owns whether those commands require a resident Mac process.

`ios/README.md` and `ios/01_Connection_Spine.md` require a Mac agent/coordinator.
This doc is the Mac-side lifecycle contract that makes that possible.

## Relationship To Work Threads

`WorkerChatCoordinator` and `ThreadStore` (Persistent Work Threads, S01–S06) own
thread/turn truth today and run in-process. The background coordinator is the
resident host those components run inside when resident mode is on; it does not
replace them or fork their state. In foreground mode they run in the app/CLI
process exactly as built. Folding `WorkerChatCoordinator` into the coordinator is
a possible future consolidation, not a requirement of this phase.

## Implementation Slices

1. **Routing (done 2026-06-15):** menu-bar-only assumptions removed from forward
   Mac docs; new work routed here via `README.md`, `AGENTS.md`, and
   `CLI_Product_Spine.md`. The executable build sequence begins at slice 2.
2. **Standalone app shell (done 2026-06-15):** runtime-promoted Dock app — the
   bundle launches as an accessory (`LSUIElement`, so the hosted unit-test runner
   connects) and `AppDelegate` promotes it to a regular Dock app
   (`setActivationPolicy(.regular)` + activate) on real launches, staying accessory
   under XCTest. Net result: a standalone Dock app with icon + main window;
   `AppModel`/`RunEvent` wiring preserved. (Visual Finder-launch Works Test is
   founder-run — no UI automation yet.)
3. **Status item pass (done 2026-06-15):** `MenuBarExtra` kept as optional
   status/quick controls (open, quick capture, run status, Stop-while-running) —
   secondary to the window, not the product shell.
4. **Coordinator contract:** build the coordinator as `alln serve` (resident
   `AllnighterCore` + loopback transports; see "Coordinator process model" under
   Process Model). Define the GUI/iOS↔coordinator process boundary, health shape,
   single-writer run journal, and `alln doctor --json` coordinator checks.
   Requires incremental journaling (CLI build order step 3) first.
5. **Resident mode MLP:** start/stop coordinator from the app; foreground runs
   can still run without it.
6. **Window-close behavior:** prove closing/reopening the app preserves active
   coordinator-owned run truth.
7. **Remote readiness:** expose enough coordinator health for iOS pairing and
   offline states.
8. **Start at login:** add opt-in login item/LaunchAgent after coordinator MLP is
   proven.

## Works Test

```text
Launch Allnighter from Finder. It appears as a normal Dock app and opens the
main window. Start a team run in resident mode, close the window, then reopen
Allnighter: the active run is still visible with current state. Stop the
coordinator: iOS/doctor report the Mac as offline/unavailable, not "running."
Run `alln team "..."` with resident mode off and confirm the foreground CLI still
works. Quit Allnighter during an active coordinator-owned run and confirm the app
asks whether to stop work or keep background work running.
```

## Proof Commands

```bash
alln doctor --json
alln team --json "foreground run without resident mode"
```

Mac proof remains app-level until UI automation exists:

```text
Open app -> Dock presence visible -> close/reopen -> active run state preserved.
```

## Non-Goals

- No cloud service decision; iOS transport docs own relay/direct details.
- No App Store/notarization decision.
- No root daemon.
- No arbitrary remote shell.
- No requirement that every `alln team` command start the resident coordinator.

## Open Questions

1. Decided (see "Coordinator process model" under Process Model): the coordinator
   is `alln serve` launched by a user-level LaunchAgent/login item — not the app
   process, not a separate helper. The CLI-level "defer `alln serve` past M1"
   decision in `CLI_Product_Spine.md` still governs *when* it is built.
2. Decided (see Lifecycle Rules): closing the final window keeps the app running
   only while the coordinator has live obligations. Remaining: should an active
   *foreground* run block quit, or only warn?
3. Should the menu bar item always exist while the coordinator is active?
4. What is the minimum visible background-mode consent copy for first launch?
