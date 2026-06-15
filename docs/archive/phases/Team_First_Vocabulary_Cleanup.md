# Team-First Vocabulary Cleanup

Status: **Complete** (2026-06-15). Archived to `docs/archive/phases/`.
Owner: Founder + Shared Core + Mac + CLI + iOS
Updated: 2026-06-15

Durable vocabulary owner going forward: `docs/phases/Work_Order_Team_Model.md`.
Machine contract owner: `docs/phases/CLI_Product_Spine.md` +
`docs/phases/CLI_Implementation_Contract.md`.

## Founder Intent

Allnighter has zero users and zero migration obligations. This is the cheap
moment to replace confusing old words instead of preserving them.

Do not gradually retire `council` / `panel` / `seat` as public product language.
Rip the old words out now, before the GUI, CLI, iOS pairing, docs, fixtures, and
mentor feedback calcify around the wrong frame.

## Product Value

The product promise is:

```text
You already pay for the models. Allnighter turns them into a team.
```

So the command surface, Mac app, iOS app, docs, and demos should all speak the
same language:

```text
ask the team
customize the team
watch the team run
read each worker answer
turn the team result into a work order
```

`Council` sounds like a meeting. `Panel` sounds like implementation plumbing.
`Seat` sounds like invented admin jargon. `Team` sounds like the product.

## Trusted Workflow Slice

```bash
alln team "Pressure-test this launch plan."
```

Same operation in the GUI:

```text
Prompt -> Team -> Run
```

Same operation from iOS:

```text
Pick Mac -> Ask team -> Watch run -> Act
```

## Canonical Vocabulary

| Use | Meaning |
| --- | --- |
| **Source** | How Allnighter reaches a model. Setup/internal language: Claude Code, Codex CLI, Gemini CLI, Grok, local runtime. |
| **Model** | The AI identity users recognize: Opus, Sonnet, Grok, Gemini, ChatGPT image, etc. |
| **Bench** | The available models. |
| **Skill** | A reusable hat/instruction a model wears. |
| **Worker** | One `model + skill` assignment for this run. A model at work. |
| **Team** | The worker lineup selected for a run. Primary public word. |
| **Team run** | One execution of a prompt by a team. |
| **Worker answer** | One worker's output from a team run. |
| **Plan** | The synthesized result from the team run. |
| **Work order** | An editable instruction packet created from a plan/result. |
| **Thread** | The durable product container for chat, team runs, work orders, dispatch, and review. |
| **Floor manager** | The Mac/iOS role that watches and controls active work. |

Boundary rule:

```text
Model at rest. Worker at work.
```

The Bench holds models. A Team holds workers. A team row is a worker, displayed
as `Skill + Model`.

## Words To Remove

| Remove from public copy | Replace with |
| --- | --- |
| council | team |
| council run | team run |
| ask panel | ask team |
| panel | team |
| panel member | worker |
| member answer | worker answer |
| seat | worker |
| worker meaning a bare AI/tool | model |
| master plan | plan |
| synthesizer | plan writer |
| judge | reviewer or plan writer, based on the stage's actual job |

`Design board` and `Copy board` remain valid output-surface words. The removed
word is `Design Council`; use `Design team` for the lineup and `Design board`
for the generated options.

## Symbol Rename Map

The biggest risk is not the product vocabulary. It is a half-migrated codebase
where the same word means different things in different layers. Use this map for
implementation slices and JSON/API reviews.

| Today / legacy | New term | Notes |
| --- | --- | --- |
| `DriverManifest` / driver | Source | Mostly internal; setup may say CLI/tool to users. |
| `Worker` meaning a bare callable model/tool | Model | Bench entry. |
| `WorkerRegistry` if it stores bare callables | Model registry | Name by what it contains. |
| `WorkerHealth` for install/auth/probe status | Source/model setup status | Exact split depends on implementation; do not call bare models workers. |
| `PanelSeat` / `PanelSeatSpec` | Worker | Runtime assignment: model + skill + optional instance index. |
| `stance` / persona / lens / role / hat | Skill | Reusable prompt profile. |
| `PanelPreset` / panel preset | Team preset | Saved worker lineup. |
| `CouncilRun` / `CouncilRequest` | TeamRun / TeamRequest | Durable run unit. |
| `MemberResponse` | WorkerAnswer | One worker's output. |
| `masterPlan` | plan | Synthesized result. |
| `WorkerRole.synthesizer` | Plan Writer skill / capability | Do not expose as `synthesizer`. |
| `panel_default.json` | `team_default.json` | Rename when fixtures move. |
| `copy_option_<seatId>.md` | `copy_option_<workerId>.md` | Artifact naming follows runtime worker ids. |
| `ArtifactRef.kind.masterPlan` / `master_plan` | `ArtifactRef.kind.plan` / `plan` | Artifact naming follows product language when the run schema moves. |
| `allnighter ask` | `alln team` | Replace as part of the CLI cutover; no public alias. |
| `allnighter detect` | `alln doctor` | Doctor owns detection, auth, and recovery. |
| `council_ask` MCP tool | `team_ask` | Rename before advertising MCP again. |

Thread turn names should follow the same contract:

```text
teamRun
designBoard
copyBoard
workOrder
dispatch
returnReview
```

New JSON output from `alln team --json` must use the new names from day one.
Do not ship machine-readable fields such as `panelSeats`, `memberResponses`, or
`masterPlan` and expect the GUI to translate them away later.

## Rename Mechanics

The `Worker` change is the high-risk part. Today, many code symbols named
`Worker` represent a bare callable model/tool. In the new language, that is a
Model. A Worker is a runtime assignment: `model + skill`.

Do not try to rename old `Worker` to new `Worker` in one pass. Use a two-step
mechanical plan:

1. Introduce `Model` for the current bare callable entries on the Bench. Classify
   every `Worker*` symbol as model/setup plumbing or team-runtime plumbing.
2. Introduce the new `Worker` from the old `PanelSeat` / `PanelSeatSpec` shape:
   `modelId + skillId + optional instanceIndex`.

Then rename the run types and public fields in the same implementation slice:

```text
PanelPreset     -> TeamPreset
CouncilRun      -> TeamRun
MemberResponse  -> WorkerAnswer
masterPlan      -> plan
panelSeats      -> workers
memberResponses -> workerAnswers
```

Fixtures move with the types. Do not keep `panel_default.json` feeding
`teamRun` output under a new display label.

## Machine Contract Freeze

Before the core rename lands, publish one checked-in `TeamRunJSON` fixture that
uses:

```text
schemaVersion
teamRun
models
workers
workerAnswers
stages
plan
```

The CLI, Mac GUI presenter tests, MCP tool descriptors, and iOS snapshot fixtures
must target that same shape. `CLI_Implementation_Contract.md` owns the exact
schema; `CLI_Product_Spine.md` owns the product posture.

For v1, the plan writer is a designated worker in the team snapshot: one model
wearing the Plan Writer skill. The plan stage points to `planWriterWorkerId`.
Do not expose `synthesizer` as a product noun or leave plan attribution as
free-form copy.

## No Compatibility Window

- Do not add public aliases such as `alln council` or `alln panel`.
- Do not preserve GUI labels like `Run council` while adding `Run team`.
- Do not expose `Seat` / `Add seat` / `seat count` in public copy.
- Do not call a bare Opus/Sonnet/Grok/Gemini entry a worker. That is a model.
- Do not write new docs that describe the same action with both old and new
  words.
- Do not expose old vocabulary in command names, menu items, onboarding, pairing
  text, marketing copy, or screenshots.
- Internal symbol renames may land in more than one commit, but each cleanup
  slice must reduce old-word surface area and must not create new user-facing
  old-word strings.

## Current Known Cleanup Surface

Docs already known to need replacement:

```text
docs/phases/README.md
docs/phases/Persistent_Work_Threads.md
docs/phases/Utilization_Admission_Control.md
docs/phases/setup/
docs/phases/ios/01a_Pairing_Ceremony.md
docs/gui/
docs/mvp/README.md
docs/mvp/03_Mac_App_And_Run_Loop.md
docs/mvp/04_Synthesis_And_Master_Plan.md
docs/mvp/06_Fusion_Grade_Synthesis_And_Evals.md
docs/design-system/uploads/RB6_Council_As_Tool.md
```

`docs/design-system/uploads/RB6_Council_As_Tool.md` is useful architecture
input, not current vocabulary authority. If revived, translate `council_*`
operations to `team_*` operations per `CLI_Product_Spine.md`.

Code and generated fixtures likely need rename planning:

```text
CouncilRun
PanelPreset
PanelSeat / PanelSeatSpec
MemberResponse / member answer fields
ArtifactRef.kind.masterPlan / master_plan artifacts
Worker types that actually represent bare models
Run council buttons and accessibility labels
panel_* fixtures
ui_kits/council
allnighter ask / detect / presets / recall
council_ask MCP descriptors
```

This list is a starting inventory, not permission to keep the old words.

## Execution Order

1. **Docs router first.** Update phase/router docs so new work starts from Team.
2. **Patch drift docs.** Copy, Setup, Threads, GUI briefs, iOS pairing, and
   AGENTS must stop teaching the old entity model before implementation starts.
3. **Freeze the machine contract.** Add the first `TeamRunJSON` fixture before
   the core rename so CLI, GUI, MCP, and iOS converge on one shape.
4. **Core rename + CLI milestone together.** Do not build `alln team` on old
   public JSON. Rename public/core surfaces as the CLI proof loop lands: old
   Worker-as-model becomes Model; old Seat becomes Worker.
5. **MCP cutover.** If MCP is touched during the CLI slice, rename `council_ask`
   and related descriptors to `team_*` immediately. Otherwise defer public MCP
   advertising until the CLI JSON/NDJSON, doctor, docs, and export-check surfaces
   are stable. Do not leave a public old tool name beside the new CLI.
6. **GUI language pass.** Replace labels, empty states, window titles,
   accessibility labels, and design briefs.
7. **iOS language pass.** Pairing and remote control copy must say team/run, not
   council/panel.
8. **MVP docs archival note.** Historical MVP docs may mention what shipped, but
   every forward pointer must say the old language was superseded.

## Works Test

Run:

```bash
rg -n "\b(council|Council|panel|Panel|seat|Seat|member answer|Member answer|master plan|Master plan|synthesizer|Synthesizer|judge|Judge)\b" docs Apps Sources Tests
```

Every hit must be one of:

- a historical note explicitly saying the term is superseded;
- a private implementation symbol scheduled in the active rename checklist;
- a false positive.

No user-facing string may remain.

Additional public API proof after the core rename starts:

```bash
rg -n "CouncilRun|PanelSeat|PanelPreset|MemberResponse|masterPlan|panelSeats|memberResponses" Packages Apps Tests
```

Every remaining hit must be explicitly legacy/internal and scheduled in the
active rename checklist.

Agent-surface proof after the CLI/MCP cutover:

```bash
rg -n "allnighter ask|allnighter detect|council_ask|council_|masterPlan|panelSeats|memberResponses" docs Packages Apps Tests
```

Every remaining hit must be historical, private, or scheduled for deletion.

## Done When

- `docs/phases/README.md` routes vocabulary work here and to
  `Work_Order_Team_Model.md`.
- CLI product docs use `alln team` as the primary operation and `alln models`
  for Bench management.
- New GUI/iOS work cannot copy old `council` / `panel` labels from older briefs.
- New GUI/iOS work cannot expose `seat`; team customization says `Skill | Model`
  and `Add worker`.
- `TeamRunJSON` exists before GUI/iOS wire contracts depend on runs.
- A follow-up implementation slice has an explicit rename checklist and proof
  command.
