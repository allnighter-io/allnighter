> **Vocabulary (2026-06-15).** Current product language lives in
> `docs/phases/Work_Order_Team_Model.md`. This doc uses team/model/worker/plan
> terms only.

# 05 — History, Presets, Doctor + Distribution

Status: **Daily-driver slices shipped (S01–S05).** Distribution (S06–S07)
deferred by founder — internal use only for now; GRDB (S08) not yet needed.
Depends on: 01, 02, 03, 04
Owner: Mac
Created: 2026-06-14
Updated: 2026-06-14

## Goal

Turn the working loop into something the founder reaches for every day and
trusts: browse past runs, save team + explicit synthesis presets, choose which
worker writes the plan, use a one-click global hotkey to capture a
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

- **Run history**: a list of past `TeamRun`s (from the Runs folder, `00` §7),
  reopen any to view members + plan; re-run with the same prompt/team.
- **Presets**: save named teams with explicit fields:
  `panelWorkerIds`, `draftPlanWriterWorkerId`, and
  `draftSynthesisInstructionPresetId`. Pick a preset before running. Ship the
  Founder's Six-worker default as a built-in preset, with Opus as the default
  plan writer only by configuration.
- **Synthesis instruction presets**: named, editable prompt templates for the
  draft plan. Fix the current roundtrip seam so `run.json` records the
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

- [x] P05-S01 — Run history list + detail reopen + "run again". History sidebar
  section (`store.list()`), read-only `HistoryDetailView`, and `runAgain(_:)`
  reconstructs prompt + team + plan writer + instructions + preset.
- [x] P05-S02 — Team presets (`TeamPreset`: `panelWorkerIds`,
  `draftPlanWriterWorkerId`, `draftSynthesisInstructionPresetId`, `builtIn`) +
  `TeamPresetStore` + built-in six-worker default derived from the live team.
  Opus is the default plan writer *by configuration*, not a code path.
- [x] P05-S03 — Synthesis-instruction presets (`SynthesisInstructionPreset` +
  `SynthesisInstructionStore`); **honest persistence** via
  `SynthesisInstructionChoice` — `Synthesis.instructions` records the chosen
  preset id or the literal custom text, never always `default_master_plan_v1`.
  Rerun from history restores the same instructions.
- [x] P05-S04 — Doctor (`Doctor` + `WorkerDiagnosis`): detect presence, capture
  version, smoke test, classify health, and emit copy-able fix hints
  (missing binary / not authenticated / bad flags / manual). Doctor sheet UI.
- [x] P05-S05 — Global hotkey quick capture (Carbon `RegisterEventHotKey`,
  ⌥⌘Space, no Accessibility permission) + optional clipboard prefill.
- [ ] P05-S06 — Notarized DMG (Developer ID, hardened runtime, entitlements).
  **Deferred by founder — internal use only; revisit before external launch.**
- [ ] P05-S07 — First-run onboarding (Doctor + permissions/why copy).
  **Deferred with S06** (onboarding pairs with distribution).
- [ ] P05-S08 — (Conditional) GRDB run index if flat-file history is slow.
  Not triggered — flat-file history is fast at current volume.

## Works Test

```text
Install the notarized DMG on a clean account. First run shows Doctor: each of
the six workers reports detected/healthy or a clear reason. Save a team preset
that uses a non-Opus draft plan writer plus a custom synthesis-instruction
preset. Trigger the global hotkey, paste a prompt, run, get a plan,
export. Reopen the run later from history and re-run it with the same preset. A
worker whose CLI was updated/broken shows red in Doctor with a fix hint instead
of silently disappearing.
```

## Exit Gates

- [x] Doctor correctly classifies healthy vs missing vs unauthenticated workers
  (unit-tested via `MockCommandRunner`; on-device confirmation pending a founder
  run).
- [x] Presets + history persist across launches (file-backed under
  `Config/TeamPresets`, `Config/InstructionPresets`, `Runs/`).
- [x] Draft plan writer is explicit per preset; Opus is a default, not a
  hardcoded code path (`TeamPreset.draftPlanWriterWorkerId` +
  `AppModel.planWriterWorker`).
- [x] `Synthesis.instructions` records the chosen preset/custom instruction
  honestly (`SynthesisInstructionChoice`).
- [x] Global hotkey works system-wide (Carbon, no Accessibility permission).
- [x] `xcodebuild test -scheme AllnighterMac` + `swift test` green (73 Core/Engine
  tests + Mac app suite).
- [ ] Works Test passes from a **notarized DMG** on a clean account.
  **Deferred** — distribution is out of scope for now (internal use). The Works
  Test passes from a local `xcodebuild`/Run build today.
- [ ] Code Audit CLEAN (run at milestone closeout).

## Closeout

**Daily-driver slices (S01–S05) shipped and green; runs from a local build.**
Distribution (notarized DMG + first-run onboarding, S06–S07) is intentionally
deferred — the founder uses the tool internally for now and will revisit
signing/notarization before any external launch. GRDB (S08) is untriggered.

Next milestone is the review-board milestone (`RB0`-`RB4`), whose specs are
finalized alongside this phase. Before RB1 code starts, run the manual
**activation gate** in `RB0` on three real prompts.
