# Worker / Skill Sharing

Status: **Founder direction locked** — vocabulary + sharing model + no-fork rule;
implementation packet not started
Owner: AllnighterCore + Mac app
Created: 2026-07-28
Updated: 2026-07-28 (new-skill affordances)
Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`

Related: `docs/archive/phases/Team_And_Skill_Catalogs.md`,
`docs/archive/phases/Ephemeral_Teams.md`, code SSOT `SkillCatalog.swift`,
`TeamEditorView.swift` (`TeamDraft.commit()`)

## Founder Intent

Define reusable instructions once — Bug Hunter, Copywriter, Documenter — and
staff them on many teams. Edit the Copywriter skill in one place; Spec Review,
Bug Hunt Min, and Bug Hunt Max all inherit the same `skill.md`.

Analogy: **Claude Code Skills** — a skill is a shared `SKILL.md`; workers pick
it up. **No silent forking.** Editing a skill changes the skill for every team
that uses it.

## Vocabulary (locked)

Two surfaces, two words — not one noun for everything.

### Team / staffing view → **Worker**

The team editor is a crew roster. Keep user-facing copy:

- **WORKERS** section
- **+ Add worker**
- **N workers + 1 lead** footer
- **Team Lead** (synthesizer; same model + skill shape, separate section)

A **worker** on a team = **skill + model** (who wears which hat, on which CLI).

```text
First Principles Reviewer · Auto
         ↑ skill (display name)   ↑ model
```

The row label is the skill name because that is how you identify the role. The
worker is the staffed row; the skill is the shared hat it wears.

### Drill-in → **Model · Skill · skill.md**

Tap a worker to **edit worker** — assign model, pick skill, edit the shared body.

| Field | Meaning |
| --- | --- |
| **Model** | Who runs this worker |
| **Skill** | Which shared hat (catalog picker) |
| **skill.md** | The skill’s template body — **not** a separate “prompt” |

### Catalog / sharing → **Skill**

Reusable across teams. Many workers on many teams can reference the same
`skillId`. One edit → all of them.

### Internal / code (optional)

`TeamWorkerSpec`, `skillId`, CLI `alln skills` — implementation names can stay.
**Seat** is fine in architecture docs; not required in the team staffing UI.

```text
Team    = workers + lead (+ scout)
Worker  = skillId + modelId (one roster row)
Skill   = name + lane + purpose + skill.md (shared catalog entry)
```

Ephemeral runs (`alln run --team … --seat …`) inherit the team’s skill ids; only
models change per run — no new skill files.

## No forking (locked — the mess is gone)

**Fork-on-save is retired.** Saving an edited `skill.md` writes a **skill
override at the same id** (mirror team overrides), not `createCustom()` and not
`"<Skill> for <Team>"` repointing.

| Action | Behavior |
| --- | --- |
| Edit skill.md on a worker | Updates the **shared skill**; every team with that skill id inherits |
| Restore default | Drops override; shipped seed returns |
| Duplicate skill… | **Explicit only** — new id, user assigns workers manually |

The 86 orphan lab forks were a symptom of the old rule (73 GC’d 2026-07-28;
`alln skills gc` remains for cleanup). Do not reintroduce silent fork-on-save.

## Target UX (locked)

### Team editor (keep “worker”)

```text
TEAM LEAD
  Spec Review Writer · Fable 5

WORKERS
  First Principles Reviewer · Auto
  Doc Hygiene Reviewer · Auto
  …

+ Add worker

5 workers + 1 lead · saved as a code team you can pick in the composer
```

### Edit worker (drill-in)

```text
Edit worker · Spec Review

MODEL
[ Auto ▼ ]

SKILL                                          [ + ]
[ First Principles Reviewer ▼ ]     [ Restore default ]
  └─ popover footer: + New skill…  (always visible)
  └─ or type to filter: + Create "Your Name"

skill.md
┌─────────────────────────────────────┐
│ Read the spec from first principles…│
└─────────────────────────────────────┘
Shared across every team that uses this skill.

[ Cancel worker changes ]  [ Done ]
```

Changes from today:

1. **Model first** — primary staffing decision.
2. **Skill** — shared catalog picker (not a duplicate of the row label).
3. **`skill.md`** — replaces PROMPT; edits the shared skill.
4. **Restore default** on edited built-in skills.
5. Footer: scope of sharing (all teams on this skill id).

### Creating a new skill (locked)

Users must not have to discover type-to-create by accident. Two affordances:

| Affordance | Behavior |
| --- | --- |
| **+** on the SKILL row (right-aligned, label row) | Starts blank new-skill flow: name field + empty `skill.md`; persists as an explicit new catalog entry on team Save |
| **+ New skill…** in the skill dropdown footer | Always visible when the picker opens (not only after typing) |
| **+ Create "…"** in the dropdown footer | When the user types a name that does not exactly match an existing skill |

**+** on the label row is the primary entry; the persistent footer backs up users
who open the list first. Typing to filter remains for power users.

Explicit **new skill** is not silent forking — it mints a new `skillId` the user
names and can assign to other workers/teams. Editing an existing skill’s
`skill.md` updates the shared skill (no fork) once Phase 1 ships.

## Sharing model (implementation)

**B1 — skill overrides (mirror teams)** — preferred path:

- `SkillCatalog.get(id)` → user override at same id ?? built-in seed.
- GUI Done / `alln skills edit <id>` write override; restore deletes it.
- Bug Hunt Min / Default / Max keep `skillId: bug_reproducer` → all pick up edits.
- Runs snapshot resolved prompt at dispatch.

**B2 — explicit duplicate** only when the user chooses “Duplicate skill…”.

Rejected: fork per team on save (old `TeamDraft.commit()` behavior).

## What works today

Built-in skills already share by id across team variants. Team overrides at same
id work; skill overrides do not yet (`builtInImmutable`).

## What was broken (being fixed)

1. **Fork-on-save** — `TeamDraft.commit()` → `createCustom()`; sharing destroyed.
2. **No skill override-at-same-id** — unlike teams.
3. **SKILL + PROMPT UI** — looked like two concepts; PROMPT was the skill body.
4. **Skills settings tab** — orphan junk drawer (removed 2026-07-28).

## Implementation phases

### Phase 1 — No forking (required)

- Remove fork-on-save from `TeamDraft.commit()`.
- `SkillCatalog.saveOverride` / `restore` (mirror `TeamCatalog`).
- CLI: `alln skills edit` / `restore` on built-in ids.

### Phase 2 — Edit worker UI

- Keep **Workers** / **Add worker** on team editor.
- Drill-in: Model → Skill → `skill.md`; shared-skill footer + Restore default.
- Drop PROMPT label; honest `skill.md` once Phase 1 ships.
- **Discoverable new skill:** + on SKILL row; persistent **+ New skill…** dropdown
  footer (shipped 2026-07-28 in `CustomizeWorkerView` / `ALSearchableDropdown`).

### Phase 3 — Skill library (optional)

- Browse lane skills (built-in + customs); entry from edit worker if needed.
- Not a separate tuning surface that forks.

## Open questions (remaining)

1. **Auto GC:** `alln skills gc` on app launch, or CLI/manual only?
2. **Lab skills:** separate storage root (like `lab-teams`)?

## Answered (founder, 2026-07-28)

| Question | Answer |
| --- | --- |
| Worker vs skill vs prompt? | **Worker** on team roster (skill + model). **Skill** = shared hat. Body = **skill.md**. |
| Edit shared or fork? | **Shared.** No silent forking. Duplicate skill is explicit only. |
| Bug Hunt family shares Bug Reproducer? | **Yes.** |
| “Seat” in team UI? | **No** — keep **worker** for staffing view; seat is internal if needed. |
| Agent path? | `alln skills edit <id>` + team/worker staffing via GUI or `teams edit`. |
| How to create a new skill? | **+** on SKILL row + **+ New skill…** in dropdown; type-to-create remains as **+ Create "…"**. |

## Non-goals

- Cross-lane skills.
- Skill marketplace / import-export.
- Version history UI.

## Smallest proof slice

```text
1. Edit worker → change skill.md for bug_reproducer → Done (override, not fork).
2. Run Bug Hunt Min and Bug Hunt Max on the same fixture.
3. Both workers receive the updated template.
4. Restore default → both teams revert to shipped seed.
```

## Shipped adjacent (2026-07-28)

- Removed Settings → Skills tab.
- Worker skill picker: built-ins + this team’s referenced customs only.
- `alln skills gc` — delete unreferenced custom skills.
- Edit worker: **+** on SKILL row + persistent **+ New skill…** in skill dropdown
  (`TeamEditorView`, `ALSearchableDropdown`).
