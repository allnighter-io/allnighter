# 05 — History, Presets, Doctor + Distribution

Status: Draft — **make it the daily driver**
Depends on: 01, 02, 03, 04
Owner: Mac
Created: 2026-06-14

## Goal

Turn the working loop into something the founder reaches for every day and
trusts: browse past runs, save panel + synthesis presets, a one-click global
hotkey to capture a prompt, a Doctor that detects/repairs CLI workers, and a
notarized DMG so it launches at login like a real app.

## Non-Goals

- iOS (next milestone; see `00` § Growth Seams). Scheduling/quota/scorecards/
  taste (deferred roadmap). Relay/push.

## Approach (per `00`)

- **Run history**: a list of past `CouncilRun`s (from the Runs folder, `00` §7),
  reopen any to view members + master plan; re-run with the same prompt/panel.
- **Presets**: save named panels (which workers + which synthesizer) and named
  synthesis instructions; pick a preset before running. Ship the founder's
  six-worker default as a built-in preset.
- **Doctor**: detect each CLI (`detectCommand`), run smoke tests, show version +
  health + the exact failing reason (missing binary, not logged in, bad flags)
  with copy-able fix hints. This is where CLI churn is diagnosed.
- **Quick capture**: a global hotkey opens the prompt composer from anywhere;
  optionally prefill from the clipboard.
- **Persistence growth check**: if history/query is sluggish on flat files,
  introduce the GRDB run index (`00` §7) — additive, `run.json` stays the truth.
- **Distribution**: XcodeGen project, Developer ID signing, hardened runtime
  with the entitlements needed to spawn processes, notarized DMG; first-run
  onboarding that runs Doctor and explains why it needs to launch local CLIs.

## Ordered Slices

- [ ] P05-S01 — Run history list + detail reopen + "run again".
- [ ] P05-S02 — Panel presets (workers + synthesizer) incl. built-in six-worker default.
- [ ] P05-S03 — Synthesis-instruction presets.
- [ ] P05-S04 — Doctor UI: detect, smoke test, version, health, fix hints.
- [ ] P05-S05 — Global hotkey quick capture (+ optional clipboard prefill).
- [ ] P05-S06 — Notarized DMG (XcodeGen, Developer ID, hardened runtime, entitlements).
- [ ] P05-S07 — First-run onboarding (Doctor + permissions/why copy).
- [ ] P05-S08 — (Conditional) GRDB run index if flat-file history is slow.

## Works Test

```text
Install the notarized DMG on a clean account. First run shows Doctor: each of
the six workers reports detected/healthy or a clear reason. Save a panel preset.
Trigger the global hotkey, paste a prompt, run, get a master plan, export. Reopen
the run later from history and re-run it. A worker whose CLI was updated/broken
shows red in Doctor with a fix hint instead of silently disappearing.
```

## Exit Gates

- [ ] Works Test passes from a notarized DMG on a clean account.
- [ ] Doctor correctly classifies healthy vs missing vs unauthenticated workers.
- [ ] Presets + history persist across launches.
- [ ] Global hotkey works system-wide.
- [ ] `xcodebuild test -scheme AllnighterMac` + `swift test` green; Code Audit CLEAN.

## Closeout

**MVP shipped and dogfooded.** Next milestone (separate plan): the iOS floor
manager — wrap the existing `RunEvent` stream in a Hummingbird WebSocket server
(`00` § Growth Seams; `ON HOLD/08–09`) so the phone can send a prompt, watch the
panel, and read the master plan on the go. No engine rewrite required.
