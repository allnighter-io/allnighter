> **Vocabulary (2026-06-15).** Current product language lives in
> `docs/phases/Work_Order_Team_Model.md`. This doc uses team/model/worker/plan
> terms only.

# 03 — Mac App Shell + Run Loop

Status: **Built (automated gates green)** — live Works Test with real CLIs is a
founder-run manual step. App builds + `AllnighterMacTests` pass.
Depends on: 01, 02
Owner: Mac (UI)
Created: 2026-06-14
Built: 2026-06-14

## Goal

Wrap the engine in a native Mac app: a menu-bar item + a window where the
founder types one prompt, sees the team, runs it, watches live per-worker
status, and reads each member's answer. After this phase the founder can fan out
to the bench with one click and read every answer in one place — no clipboard.
Synthesis (the plan) lands in Phase 04; here a run ends at `answers_in`.

## Non-Goals

- Synthesis/plan (Phase 04). Run history browser + presets + Doctor UI
  (Phase 05). iOS (Growth Seam).

## Approach (per `00`)

- **App shell**: SwiftUI app with `MenuBarExtra` (status item) and a main
  window. Unsandboxed; inherits the user's login-shell environment so spawned
  CLIs see the same PATH/auth as a terminal.
- **State**: an `@Observable` run store subscribes to the coordinator's
  `RunEvent` `AsyncStream` and applies events idempotently (upsert) — UI never
  mutates truth directly (`00` §6), so an iOS client can later share the model.
- **Prompt composer**: multiline prompt input + a "Run team" button.
- **Team view**: the configured workers as toggles (default = all enabled +
  healthy); shows health badges from Phase 02 smoke tests.
- **Live run view**: one row/chip per worker with status (`queued`/`running`/
  `done`/`failed`/`timed_out`), elapsed time, and a global **Stop**.
- **Response viewer**: per-worker answers as cards/tabs, Markdown-rendered, each
  with copy; a `manual_paste` worker shows the prompt + a paste box that fills
  its answer.
- **Worker settings (minimal)**: enable/disable workers, set the plan writer,
  edit a worker's `modelLabel`/manifest path. (Full presets + Doctor UI in 05.)
- Render initial screens from `AllnighterCore` fixtures before wiring the live
  engine, then switch to live.

## Ordered Slices

- [x] P03-S01 — App shell: `MenuBarExtra` + main `Window` + `NavigationSplitView`
  (`AllnighterMacApp`, `RootView`). LSUIElement menu-bar app.
- [x] P03-S02 — Observable store (`AppModel`) bound to the `RunEvent` stream;
  status applied live, content filled from the settled run.
- [x] P03-S03 — Prompt composer + "Run team" (⌘↵) → `TeamRunCoordinator`
  with the real `SubprocessCommandRunner`.
- [x] P03-S04 — Team sidebar with per-worker enable toggles + health badges.
- [x] P03-S05 — Live run view: status dots/strip, elapsed time, global Stop.
- [x] P03-S06 — Response viewer: per-worker cards, selectable text + copy;
  manual-paste box for `skipped` workers.
- [x] P03-S07 — Minimal worker settings (enable toggle, "Check worker health").
  (Set-plan writer/edit-manifest moves to Phase 04/05.)

## Works Test

```text
Launch the Mac app. Type one prompt, leave the default team (the six workers),
click "Run team." Each worker shows live status; healthy headless workers
return Markdown answers in parallel; any manual-paste worker shows the prompt
with a paste box. Click Stop mid-run and confirm running workers cancel. With a
completed run, read each member's answer and copy one to the clipboard. The run
reaches `answers_in` (no synthesis yet).
```

**Status:** This live test spends real CLI quota and needs the founder's CLIs
logged in, so it is a **founder-run manual step** (not auto-run by the agent).
The automated substitute — build + `AppModel` unit tests + the deterministic
engine suite — is green.

## Exit Gates

- [ ] **Founder manual:** live Works Test against real workers.
- [x] UI updates from `RunEvent`s for status; content from the settled run
  (no direct truth mutation in views).
- [x] Stop cancels in-flight workers (engine cancel proven in Phase 02;
  wired to `AppModel.stop()`).
- [x] App inherits login-shell `PATH` (`LoginShell.applyToProcessEnvironment()`).
- [x] `xcodebuild test -scheme AllnighterMac` passes; `swift test` green
  (full `scripts/check.sh` green).

## Closeout

**Built; pending one founder-run live test.** App lives at `Apps/AllnighterMac`
(XcodeGen `project.yml`; `.xcodeproj` is generated and gitignored). Activate
**Phase 04 (Synthesis + Plan)** — the one-click daily loop.

### Notes for Phase 04

- `AppModel` already owns the run + registry; synthesis adds: pick the
  `plan writer` worker (role `both`/`plan writer`, default Opus), assemble the
  synthesis prompt from `run.answeredWorkers`, run it through the same
  `WorkerRunner`, and set `run.synthesis`.
- Run the app once with real CLIs first to correct any driver flags (Phase 02
  deferred probe) before trusting synthesis output.
