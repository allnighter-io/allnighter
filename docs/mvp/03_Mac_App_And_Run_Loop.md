# 03 — Mac App Shell + Run Loop

Status: Draft — **first visible product**
Depends on: 01, 02
Owner: Mac (UI)
Created: 2026-06-14

## Goal

Wrap the engine in a native Mac app: a menu-bar item + a window where the
founder types one prompt, sees the panel, runs it, watches live per-worker
status, and reads each member's answer. After this phase the founder can fan out
to the bench with one click and read every answer in one place — no clipboard.
Synthesis (the master plan) lands in Phase 04; here a run ends at `answers_in`.

## Non-Goals

- Synthesis/master plan (Phase 04). Run history browser + presets + Doctor UI
  (Phase 05). iOS (Growth Seam).

## Approach (per `00`)

- **App shell**: SwiftUI app with `MenuBarExtra` (status item) and a main
  window. Unsandboxed; inherits the user's login-shell environment so spawned
  CLIs see the same PATH/auth as a terminal.
- **State**: an `@Observable` run store subscribes to the coordinator's
  `RunEvent` `AsyncStream` and applies events idempotently (upsert) — UI never
  mutates truth directly (`00` §6), so an iOS client can later share the model.
- **Prompt composer**: multiline prompt input + a "Run council" button.
- **Panel view**: the configured workers as toggles (default = all enabled +
  healthy); shows health badges from Phase 02 smoke tests.
- **Live run view**: one row/chip per worker with status (`queued`/`running`/
  `done`/`failed`/`timed_out`), elapsed time, and a global **Stop**.
- **Response viewer**: per-worker answers as cards/tabs, Markdown-rendered, each
  with copy; a `manual_paste` worker shows the prompt + a paste box that fills
  its answer.
- **Worker settings (minimal)**: enable/disable workers, set the synthesizer,
  edit a worker's `modelLabel`/manifest path. (Full presets + Doctor UI in 05.)
- Render initial screens from `AllnighterCore` fixtures before wiring the live
  engine, then switch to live.

## Ordered Slices

- [ ] P03-S01 — App shell: `MenuBarExtra` + main window + navigation.
- [ ] P03-S02 — Observable run store bound to the `RunEvent` stream (idempotent apply).
- [ ] P03-S03 — Prompt composer + "Run council" → triggers `CouncilRunCoordinator`.
- [ ] P03-S04 — Panel view with per-worker enable toggles + health badges.
- [ ] P03-S05 — Live run view: status chips, elapsed time, global Stop (cancel).
- [ ] P03-S06 — Response viewer: Markdown cards per worker + copy; manual-paste box.
- [ ] P03-S07 — Minimal worker settings (enable, set synthesizer, edit model/manifest).

## Works Test

```text
Launch the Mac app. Type one prompt, leave the default panel (the six workers),
click "Run council." Each worker shows live status; healthy headless workers
return Markdown answers in parallel; any manual-paste worker shows the prompt
with a paste box. Click Stop mid-run and confirm running workers cancel. With a
completed run, read each member's answer and copy one to the clipboard. The run
reaches `answers_in` (no synthesis yet).
```

## Exit Gates

- [ ] Works Test passes against real workers.
- [ ] UI updates only from `RunEvent`s (no direct truth mutation).
- [ ] Stop cancels in-flight workers; no orphan processes.
- [ ] App inherits login-shell env so CLIs authenticate as in a terminal.
- [ ] `xcodebuild test -scheme AllnighterMac` builds and passes; `swift test` green.

## Closeout

Activate Phase 04 (Synthesis + Master Plan) — the one-click daily loop.
