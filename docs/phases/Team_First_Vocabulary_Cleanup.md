# Team-First Vocabulary Cleanup

Status: Immediate cleanup contract
Owner: Founder + Shared Core + Mac + CLI + iOS
Updated: 2026-06-15

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
| synthesizer | plan writer or selected worker, depending on context |
| judge | reviewer or plan writer, depending on context |

`Design board` and `Copy board` remain valid output-surface words. The removed
word is `Design Council`; use `Design team` for the lineup and `Design board`
for the generated options.

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
```

Code and generated fixtures likely need rename planning:

```text
CouncilRun
PanelPreset
PanelSeat / PanelSeatSpec
MemberResponse / member answer fields
Worker types that actually represent bare models
Run council buttons and accessibility labels
panel_* fixtures
ui_kits/council
```

This list is a starting inventory, not permission to keep the old words.

## Execution Order

1. **Docs router first.** Update phase/router docs so new work starts from Team.
2. **CLI contract next.** Ship the `alln` command grammar with `team` as the
   primary verb/noun.
3. **Core semantic rename.** Rename public/core surfaces before GUI wiring
   deepens: old Worker-as-model becomes Model; old Seat becomes Worker. Keep
   compatibility only inside private migration code needed to finish the rename.
4. **GUI language pass.** Replace labels, empty states, window titles,
   accessibility labels, and design briefs.
5. **iOS language pass.** Pairing and remote control copy must say team/run, not
   council/panel.
6. **MVP docs archival note.** Historical MVP docs may mention what shipped, but
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

## Done When

- `docs/phases/README.md` routes vocabulary work here and to
  `Work_Order_Team_Model.md`.
- CLI product docs use `alln team` as the primary operation and `alln models`
  for Bench management.
- New GUI/iOS work cannot copy old `council` / `panel` labels from older briefs.
- New GUI/iOS work cannot expose `seat`; team customization says `Skill | Model`
  and `Add worker`.
- A follow-up implementation slice has an explicit rename checklist and proof
  command.
