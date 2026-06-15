# 05 — History, Presets, Doctor + Distribution

Status: Draft — **make it the daily driver**
Depends on: 01, 02, 03, 04
Owner: Mac
Created: 2026-06-14

## Goal

Turn the working loop into something the founder reaches for every day and
trusts: browse past runs, save panel + explicit synthesis presets, choose which
worker writes the master plan, use a one-click global hotkey to capture a
prompt, run a Doctor that detects/repairs CLI workers, and install a notarized
DMG so it launches at login like a real app.

## Non-Goals

- iOS (next milestone; see `00` § Growth Seams). Scheduling/quota/scorecards/
  taste (deferred roadmap). Relay/push.
- Review-board / final-spec workflow (`RB0`-`RB4`). Phase 05 ships the daily
  driver and the preset foundation; it does not add post-synthesis reviews.
- Direct executor dispatch (`RB4`). Phase 05 ships the daily driver and preset
  foundation; RB4 later sends the final spec to the selected CLI without
  Allnighter-owned git/worktree rules.

## Approach (per `00`)

- **Run history**: a list of past `CouncilRun`s (from the Runs folder, `00` §7),
  reopen any to view members + master plan; re-run with the same prompt/panel.
- **Presets**: save named panels with explicit fields:
  `panelWorkerIds`, `draftSynthesizerWorkerId`, and
  `draftSynthesisInstructionPresetId`. Pick a preset before running. Ship the
  founder's six-worker default as a built-in preset, with Opus as the default
  synthesizer only by configuration.
- **Synthesis instruction presets**: named, editable prompt templates for the
  draft master plan. Fix the current roundtrip seam so `run.json` records the
  preset/custom instruction actually used, not always `default_master_plan_v1`.
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
- [ ] P05-S02 — Panel presets with explicit `panelWorkerIds`,
  `draftSynthesizerWorkerId`, and `draftSynthesisInstructionPresetId`, incl.
  built-in six-worker default.
- [ ] P05-S03 — Synthesis-instruction presets: built-in default, custom editable
  preset, honest persistence in `Synthesis.instructions`, and rerun from history
  with the same preset.
- [ ] P05-S04 — Doctor UI: detect, smoke test, version, health, fix hints.
- [ ] P05-S05 — Global hotkey quick capture (+ optional clipboard prefill).
- [ ] P05-S06 — Notarized DMG (XcodeGen, Developer ID, hardened runtime, entitlements).
- [ ] P05-S07 — First-run onboarding (Doctor + permissions/why copy).
- [ ] P05-S08 — (Conditional) GRDB run index if flat-file history is slow.

## Works Test

```text
Install the notarized DMG on a clean account. First run shows Doctor: each of
the six workers reports detected/healthy or a clear reason. Save a panel preset
that uses a non-Opus draft synthesizer plus a custom synthesis-instruction
preset. Trigger the global hotkey, paste a prompt, run, get a master plan,
export. Reopen the run later from history and re-run it with the same preset. A
worker whose CLI was updated/broken shows red in Doctor with a fix hint instead
of silently disappearing.
```

## Exit Gates

- [ ] Works Test passes from a notarized DMG on a clean account.
- [ ] Doctor correctly classifies healthy vs missing vs unauthenticated workers.
- [ ] Presets + history persist across launches.
- [ ] Draft synthesizer is explicit per preset; Opus is a default, not a
  hardcoded code path.
- [ ] `Synthesis.instructions` records the chosen preset/custom instruction
  honestly.
- [ ] Global hotkey works system-wide.
- [ ] `xcodebuild test -scheme AllnighterMac` + `swift test` green; Code Audit CLEAN.

## Closeout

**MVP shipped and dogfooded.** Next milestone is chosen deliberately: either the
iOS floor manager (`00` § Growth Seams; `ON HOLD/08–09`) or the review-board
milestone (`RB0`-`RB4`). The review-board milestone should run the manual
activation gate in `RB0` before code starts.
