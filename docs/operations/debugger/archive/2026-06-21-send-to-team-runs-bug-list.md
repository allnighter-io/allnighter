# Send to Team Runs Bug List

**First reported:** 2026-06-21  
**Status:** ✅ ALL 9 FIXED (2026-06-20). Archived. Commits: nav-escape `145a30dd`; Floor
title/state/hover/copy `6354058f`; Floor Next Move `563a764c`; wrong-model substitution
display `ed5ea974`; failure classification + substitution rule `21a9621b`.  
**Surfaces:** Send to Team runs, Team threads, Factory Floor, worker response cards,
custom team execution, model health/substitutions.  
**Reporter evidence:** Founder note and screenshots from the Codex turn on
2026-06-21.

## Open Bugs

- [x] **Worker cards do not show the worker job/title first.** — FIXED (6354058f)

  **Priority:** P1 / comprehension blocker.  
  **Observed:** Send to Team run/thread cards show model names such as
  `ChatGPT 5.5`, `Composer 2.5`, and `Opus 4.8`, but do not show the worker
  job/title/name clearly. The founder cannot tell who did what or which worker
  response is being inspected.  
  **Expected:** Every worker response header shows the worker job/title/name first,
  then the model name. Example shape: `Debugger - Composer 2.5` or
  `Worker name - Model name`. The model remains visible, but it is not the only
  identity.  
  **Truth owner:** Team preset worker snapshot and `TeamRunJSON.workers`
  (`skillName`, custom worker label/title, `modelName`, `sourceId`).  
  **Lie-prone layer:** SwiftUI Thread/Factory Floor cards using only the model
  display name or falling back to model identity when worker label truth exists.  
  **Fix boundary:** Presentation/read-model mapping only unless investigation
  proves the worker title is missing from the run snapshot. Do not invent
  GUI-only worker titles.  
  **Missing proof:** A presenter/unit test that a custom team worker renders
  `worker title` before `modelName`, plus a GUI fixture for a Team run with at
  least three distinct worker titles.

- [x] **Factory Floor worker cards do not show response time or worker state.** — FIXED (6354058f)

  **Priority:** P1 / live-run readability.
  **Observed:** Factory Floor cast/worker cards show the worker title/model and a
  truncated response preview, but not how long that worker took to respond and not
  a clear per-worker state indicator. The reported screenshot shows
  `Regression Guard`, `ChatGPT 5.5`, and a preview line only.
  **Expected:** Every Factory Floor worker row/card shows timing and state:
  running workers show live elapsed time plus a blue working dot; done workers
  show the final response duration plus an amber/yellow dot like a new-message
  indicator; failed/timed-out/cancelled workers show final elapsed time when
  known plus a red failure dot. Queued/skipped states need an honest neutral
  treatment, not a fabricated success or failure color.
  **Truth owner:** `WorkerAnswer.status`, `startedAt`, `finishedAt`,
  `durationMs`, and the projected `FloorWorkerLane` fields.
  **Lie-prone layer:** `FactoryFloorView` / `FloorCastMember` can discard or hide
  the status and timing that already exist in the run/Floor projection.
  **Fix boundary:** Factory Floor worker row/card presenter and layout only unless
  investigation proves the run snapshot is missing timing. Do not invent timers
  from view mount time; derive live elapsed from persisted `startedAt` and clock,
  and final duration from `durationMs` or `finishedAt - startedAt`.
  **Missing proof:** Presenter tests for running/done/failed/timed-out worker
  rows showing the right duration source and state, plus a GUI fixture with one
  running worker, one done worker, and one timed-out worker proving blue /
  amber-yellow / red dots are visible and non-overlapping.

- [x] **Factory Floor worker cards do not feel selectable on hover.** — FIXED (6354058f)

  **Priority:** P2 / navigation affordance, P1 if users miss that worker rows are
  selectable.
  **Observed:** Mousing over workers in the Factory Floor cast rail does not change
  the row appearance, so the user cannot tell the worker cards are clickable or
  selectable. Current code has selected styling for `CastCard`, but no visible
  hover state.
  **Expected:** Worker cards in the Factory Floor cast rail have a clear hover
  affordance, using the existing dark hover surface and pointer-ready row feel.
  The hover state must be distinct from selected state, and selected+hover should
  remain legible. Keyboard focus should get an equivalent visible affordance for
  accessibility and non-mouse navigation.
  **Truth owner:** Factory Floor local selection state (`selectedMemberId`) and
  the `FloorCastMember` list projected from the run.
  **Lie-prone layer:** `FactoryFloorView.CastCard` can be a real `Button` but
  still look inert because it only paints the selected row.
  **Fix boundary:** Factory Floor cast-rail row interaction styling only. Do not
  change run selection semantics, worker ordering, response content, or status
  projection while fixing hover affordance.
  **Missing proof:** A GUI fixture or watcher packet that captures an unselected
  hovered worker row, a selected row, and selected+hover state, proving the row
  looks clickable without confusing hover with active selection.

- [x] **Factory Floor Next Move actions are confusing and not wired to composers.** — FIXED (563a764c)

  **Priority:** P1 / product workflow blocker.
  **Observed:** The Floor shows `Save to Pending` and `Send to another team`.
  `Save to Pending` is conceptually wrong here because Pending is an outcome/state,
  not the user's next intent. `Send to another team` is currently inert from the
  user's report: pressing it does nothing. The card also does not say what payload
  will be sent, so the user cannot tell whether the synthesis, original prompt, or
  Floor receipt is included.
  **Expected:** Collapse the Floor's user-facing next moves to exactly two
  composer-opening actions:
  - `Ask Another Team`: opens the Send to Team composer with the Floor synthesis
    attached as starting context, plus enough receipt metadata to avoid making the
    next team start from scratch. The user chooses the team and writes the next
    instruction.
  - `Continue with Auto`: opens the normal Auto/default composer in the current
    Project/thread with the same synthesis attached as starting context. The user
    continues the conversation from the Floor result.
  Remove `Save to Pending`, `Draft follow-up`, and generic `Run when ready` from
  this Floor card unless a later action has a named runner, visible payload, and
  clear execution semantics.
  **Truth owner:** Floor next-action contract (`FloorNextAction` /
  `FloorProjector`) plus the shared composer/send contract. Pending remains the
  lifecycle state for already-submitted work, not the button label for this path.
  **Lie-prone layer:** `FactoryFloorView.nextMove` can render destination labels
  as if they are real actions while no composer opens and no payload is visible.
  **Fix boundary:** Floor next-action projection and composer handoff only. Do not
  invent a GUI-only payload, do not auto-run work, and do not silently route to
  Pending. Both actions must show the attached synthesis before sending.
  **Missing proof:** A contract/presenter test that Floor next actions are only
  `Ask Another Team` and `Continue with Auto` for a normal synthesized return; a
  GUI or integration proof that each action opens the correct composer with a
  visible `Synthesis from <team>` attachment chip/card and editable prompt; a
  negative test that `Save to Pending` no longer appears on the Floor card.

- [x] **Top Inbox/Teams navigation does not escape deep surfaces.** — FIXED 2026-06-20 (RootRouteState reducer + onRoute route command; floorRun lifted to RootView; RootRouteStateTests)

  **Priority:** P1 / app navigation trust.
  **Observed:** Pressing the top `Inbox` or `Teams` control often appears to do
  nothing when a deep surface is visible. The founder called out Factory Floor and
  Settings specifically: the Floor does not yield, Settings does not yield, and
  the buttons feel broken. In the reported screenshot the top bar still shows
  `Inbox` selected while the main area is a Factory Floor result.
  **Expected:** Top-level `Inbox` and `Teams` are route commands, not passive tab
  labels. Pressing `Inbox` must close/dismiss any non-default surface above the
  workspace and show the default Inbox view unless the default Inbox view is
  already visible. Pressing `Teams` must close/dismiss the same deep surfaces and
  show the default Teams launcher unless the default Teams launcher is already
  visible. Deep surfaces include Factory Floor, Settings/Team Studio, Pending,
  readiness/doctor overlays, and any proof/demo overlays.
  **Truth owner:** Root app route state: `workspaceMode` plus the modal/deep
  surface flags that currently gate Root/Home content (`showTeamStudio`,
  `showPending`, `showReadiness`, `showDoctor`, Factory Floor state, and related
  overlays). The top bar should express one route truth, not only mutate
  `workspaceMode`.
  **Lie-prone layer:** `InboxTeamsSwitch` can visually accept a click while an
  overlay or deeper route still wins the ZStack/body branch, making the button
  look inert. Home-owned Factory Floor state is especially risky because `Inbox`
  may already be selected, so setting `.inbox` again does not dismiss it.
  **Fix boundary:** Navigation/state reset only. Do not change thread selection,
  run records, Team run truth, Settings content, or Factory Floor rendering while
  fixing the escape behavior.
  **Missing proof:** A navigation-state test or GUI fixture that opens Factory
  Floor, presses `Inbox`, and proves the default Inbox is visible; opens Factory
  Floor, presses `Teams`, and proves Teams launcher is visible; opens Settings,
  presses `Inbox`/`Teams`, and proves Settings is dismissed. Include the no-op
  case: pressing the already visible default route should not destroy useful
  thread state beyond closing deep surfaces.

- [x] **Factory Floor worker responses are missing the bottom copy button.** — FIXED (6354058f)

  **Priority:** P1 for missing action, P2 for polish.  
  **Observed:** The Factory Floor does not put a copy button at the bottom of every
  worker response. A thread copy-footer fixture already proves this behavior for
  normal assistant replies, but that proof does not cover Factory Floor worker
  answers.  
  **Expected:** Every worker answer has a bottom copy footer/button that copies
  the exact worker response body. The control should live below the answer, not in
  the header.  
  **Truth owner:** Worker answer text in the run record/artifact.  
  **Lie-prone layer:** Factory Floor response card layout and copy action wiring.  
  **Fix boundary:** Factory Floor worker-answer card only. Do not regress the
  existing thread reply copy footer.  
  **Missing proof:** A `factory-floor-copy-footer` GUI fixture or equivalent proof
  showing the copy button at the bottom of each worker answer, plus a focused test
  that the action copies the selected worker answer text.

- [x] **Custom team model selection appears to resolve or display the wrong model.** — FIXED wrong-display: substitution now shown per worker (ed5ea974)

  **Priority:** P1 / trust blocker.  
  **Observed:** A custom team named `Bug Hunt MAX` was configured with
  `Composer 2.5 Fast`, but the Factory Floor showed `Opus 4.8` for a worker. The
  founder suspects the run may have been sent to the wrong CLI, and that this may
  explain the timeout.  
  **Expected:** A custom team run uses the exact worker selection saved for each
  row: worker title, source/CLI, model, and effort. If substitution changes the
  model, the UI must say that substitution happened rather than silently showing a
  different model.  
  **Truth owner:** `TeamPreset` worker rows, `TeamResolver`, run snapshot workers,
  and `TeamRunJSON.workers`.  
  **Lie-prone layer:** Custom team resolution, run snapshot projection, or Factory
  Floor display fallback.  
  **Fix boundary:** First determine whether this is a wrong-spawn bug or a
  wrong-display bug. Do not patch labels until the run snapshot and spawned driver
  are compared.  
  **Missing proof:** A regression test with a custom `Bug Hunt MAX` style team
  containing `Composer 2.5 Fast`, asserting the resolved worker `sourceId`,
  `modelId`, `modelName`, and spawn path match the saved row; GUI proof that the
  Factory Floor displays the same worker/model pair.

- [x] **A large number of workers timed out or produced no output.** — FIXED classification surfaced (21a9621b)

  **Priority:** P1 if reproducible on healthy models, P2 if caused by external
  provider/runtime conditions.  
  **Observed:** The reported Team run had many workers time out, including a worker
  card that showed `Timed out` and `no output for 300s`. The founder asks why the
  app did not do better.  
  **Expected:** Worker failures should be classified honestly: auth required,
  provider busy/rate limited, unsupported model flag, wrong CLI, timeout, no
  output, or interrupted. Partial output should be preserved when available.
  Generic timeout should not hide a routing/configuration bug.  
  **Truth owner:** `WorkerRunner`, driver manifests, capacity/admission health, and
  run lifecycle settlement.  
  **Lie-prone layer:** Timeout classification, no-output handling, and UI status
  projection collapsing different causes into one timeout label.  
  **Fix boundary:** Investigate classification and routing before increasing
  timeouts. Do not hide failed workers or fabricate success.  
  **Missing proof:** Tests for no-output timeout classification, wrong-model or
  wrong-CLI failure classification, and partial-output preservation. Dogfood proof
  should repeat a small custom team run and report per-worker failure causes.

- [x] **Healthy substitution is not used when a selected model does not respond.** — RESOLVED: rule is preflight-only, made explicit (21a9621b)

  **Priority:** P1 / broken product promise.  
  **Observed:** The product has an `Allow healthy substitutions` setting, but the
  reported run timed out instead of apparently using a healthy substitute when a
  worker did not respond.  
  **Expected:** The runtime policy must be explicit and visible. If substitutions
  are enabled and a selected model is known unhealthy before spawn, resolve to a
  ready same-tier substitute or show that no healthy substitute exists. If a model
  starts and then times out, the product must either retry with a substitute or
  clearly say substitutions are preflight-only and do not apply after spawn.  
  **Truth owner:** Default model/substitutions settings, tier rosters, readiness
  observations, and team resolver/admission policy.  
  **Lie-prone layer:** GUI copy promising substitution broadly while runtime only
  applies Auto/default substitution, preflight substitution, or no substitution
  for custom team rows.  
  **Fix boundary:** Define the substitution rule first. Do not silently reroute a
  custom worker to another model without recording and displaying that substitution
  in the run snapshot.  
  **Missing proof:** A resolver/admission test for unhealthy selected model ->
  same-tier substitute; a no-substitute test; and a timeout-after-spawn test that
  proves the documented behavior, whether retry or honest no-retry.

## Repro Sketch

1. Create or open a custom Team named `Bug Hunt MAX`.
2. Configure at least one worker to use `Composer 2.5 Fast`.
3. Send a Team run from the Composer.
4. Open the Team thread and Factory Floor.
5. Verify every worker card shows `worker title/name - model name`.
6. Verify every worker card shows elapsed/final response time and a state dot:
   blue running, amber/yellow done, red failed/timed out.
7. Hover an unselected worker card and verify it visibly reads as selectable;
   verify selected and selected+hover states remain distinct.
8. In `TAKE THE NEXT MOVE`, verify only `Ask Another Team` and `Continue with
   Auto` appear; each opens the correct composer with the synthesis attached.
9. From Factory Floor and Settings, press the top `Inbox` and `Teams` controls
   and verify they load the default target route instead of appearing inert.
10. Verify every worker response has a bottom copy button.
11. Compare the saved custom team row to the run snapshot and spawned CLI/model.
12. For timed-out workers, inspect whether the runtime classified the failure cause
   and whether substitution was attempted or explicitly skipped.

## Related Prior Art

- `docs/archive/phases/Team_Run_Load_Performance.md` - Factory Floor vs thread receipt
  ownership and lazy run rendering.
- `docs/archive/phases/CLI_Implementation_Contract.md` - `TeamRunJSON.workers`,
  `workerAnswers`, status vocabulary, and timeout status.
- `Packages/AllnighterCore/Sources/AllnighterCore/FloorRun.swift` -
  `FloorWorkerLane` already carries status/timing fields for Factory Floor
  projection.
- `Packages/AllnighterCore/Sources/AllnighterCore/FloorProjector.swift` -
  currently emits `savePending` and `sendTeam` Floor next actions.
- `Apps/AllnighterMac/Sources/FactoryFloorView.swift` - currently renders Floor
  next-action rows; this path must open composers with visible synthesis context.
- `Apps/AllnighterMac/Sources/FactoryFloorView.swift` - `CastCard` is the
  current worker row/button touchpoint; it paints selected state but no hover
  state.
- `Apps/AllnighterMac/Sources/RootView.swift` - owns top-level workspace routing
  and deep-surface flags such as Team Studio, Pending, Readiness, and proof Floor.
- `Apps/AllnighterMac/Sources/HomeView.swift` - owns the production Factory Floor
  overlay via `floorRun`, which top-level navigation must be able to dismiss.
- `Apps/AllnighterMac/Sources/WorkspaceMode.swift` / `RootTitleBar.swift` - owns
  the visible `Inbox | Teams` top-bar control.
- `docs/phases/Pending_Work_And_Drain.md` - Pending is durable submitted work
  intent/lifecycle state; it should not be used as a vague Floor next-move label.
- `docs/workflows/Product_Vocabulary.md` - worker = model wearing a skill; models
  sit on the Bench, workers do jobs.
- `docs/phases/wiring/design_handoff_default_substitutions/README.md` - healthy
  substitution product promise and tier policy.
- `docs/gui/surfaces/threads/brief.md` - thread timeline field ownership and
  never-fake-state rules.
- `docs/qa/gui/thread/2026-06-20-copy-footer/watcher.md` - prior copy-footer proof
  for ordinary thread replies, not Factory Floor worker answers.
