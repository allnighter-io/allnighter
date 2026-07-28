# Worker / Skill Sharing

Status: **Founder direction locked** — vocabulary + sharing model + no-fork rule;
**Phase 1 (skill overrides) not yet implemented** in GUI or CLI
Owner: AllnighterCore + Mac app
Created: 2026-07-28
Updated: 2026-07-28 (CLI/GUI parity audit)
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

## No forking (locked — not yet enforced in code)

**Fork-on-save is retired by policy** but **still active** in `TeamDraft.commit()`
until Phase 1 ships. Today, editing a worker prompt and saving the team still
calls `SkillCatalog.createCustom()` (silent fork). Phase 1 removes that path.

**Target behavior** once Phase 1 ships: saving an edited `skill.md` writes a
**skill override at the same id** (mirror team overrides), not `createCustom()`
and not `"<Skill> for <Team>"` repointing.

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

## Save boundaries (locked)

Team edits and skill edits are **separate transactions**. Do not stage skill
catalog writes inside `TeamDraft` until team Save — that would mix two owners.

| Action | Commits |
| --- | --- |
| **Worker Done** (edit-worker drill-in) | `skill.md` → `SkillCatalog` when changed (override at same id, Phase 1) |
| **Team Save** | Roster only: worker `skillId` picks + `modelId` assignments |
| **Team Cancel** | Discards roster draft only; does **not** undo skill catalog writes the user already committed with Worker Done |

Canceling a team edit must not roll back a shared skill the user explicitly saved.
Show blast radius before/alongside skill edits so Worker Done is an informed
catalog write.

### Blast radius (required UX — Phase 2)

Passive “shared across teams” is not enough. When editing `skill.md`, show exact
impact:

```text
Shared across 3 teams: Bug Hunt Min · Bug Hunt Max · Security Audit
```

List team **names** (not just a count). Optional confirm when `teamCount > 1` and
`skill.md` changed — prefer visibility first; avoid modal theater.

## Lab teams and skills (locked — never in catalog)

Team Lab is **retired**. Lab artifacts must not appear in product pickers or
survive on disk:

- **Lab teams** (`typeTags` contains `"lab"`): reject on save; delete strays from
  `Catalogs/teams/`; purge `Catalogs/lab-teams/` on catalog read.
- **Lab skills** (id contains `_lab_`, e.g. `custom_code_lab_*`): never listed;
  deleted on read; reject on save.

Code SSOT: `CatalogLabRetirement.swift` (`purgeRetiredLabArtifacts()`). Called
from `SkillCatalog.list`, `TeamCatalog` migration, and `alln skills gc`.

No separate `lab-skills/` root — lab ids in the product catalog are the mistake;
purge them.

## CLI / GUI parity (audit 2026-07-28)

Shared catalog rules live in **AllnighterCore** (`SkillCatalog`, `TeamCatalog`,
`CatalogLabRetirement`). GUI and CLI both call the same APIs — no parallel truth.

| Capability | CLI | GUI (Mac) | Parity |
| --- | --- | --- | --- |
| List skills (lane) | `alln skills --lane <lane>` | Edit worker → skill picker (built-ins + this team’s customs) | **Intentional diff:** CLI lists all product customs; GUI picker is curated so orphans do not pollute the dropdown |
| Show skill + template | `alln skills show <id>` | Edit worker → PROMPT field (→ `skill.md` in Phase 2) | CLI today; GUI shows template in drill-in |
| Create skill | `alln skills new` / `duplicate` | Edit worker → **+** / **+ New skill…** | Both paths; GUI discoverability shipped |
| Edit skill | `alln skills edit <id>` (custom only) | Edit worker → change prompt → **Team Save** forks today | **Gap:** built-in edit + shared override blocked until Phase 1; GUI still forks on team Save |
| Delete skill | `alln skills delete <id>` | — | CLI only (manual GC) |
| Purge lab + orphans | `alln skills gc` | Automatic on `SkillCatalog.list` / team catalog read | Lab purge on both; orphan GC is **CLI/manual only** (no GUI button — by policy) |
| Lab teams/skills | Rejected on save; purged on read | Never listed (`isLabTeam` filtered; lab skills purged) | **Aligned** |
| Tune team roster | `teams edit` / `definition` | Settings → Teams | Aligned |
| Skills settings tab | — (removed) | — (removed) | Skills are tuned per worker, not a global browser |

**Worker Done → skill saved:** locked in doc; **not implemented** — worker Done
still stages `promptDraft` on the team row; skill write happens at **Team Save**
via fork. Phase 1 moves skill body commit to Worker Done (catalog override).

**Contract registry:** `alln skills gc` registered in `ContractRegistry` (was
CLI-only before this audit).

### Shipped in this slice (both surfaces)

- Lab retirement (`CatalogLabRetirement`) — any `SkillCatalog.list` / team load
- Orphan + lab purge via `alln skills gc`
- GUI: Skills settings tab removed; worker skill picker filtered; **+ New skill**

### Phase 1 closes remaining gaps

- `SkillCatalog.saveOverride` / `restore` (built-in ids)
- Kill `TeamDraft.commit()` fork path
- Worker Done writes changed `skill.md` to catalog
- `alln skills edit` on built-in ids (override, not `builtInImmutable`)

### Phase 2 GUI-only (CLI N/A)

- Model → Skill → `skill.md` field order and labels
- Blast-radius team name list
- Restore default button on edit worker

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
id work; skill overrides do not yet (`builtInImmutable`). **Fork-on-save still
runs on team Save** — doc policy ahead of code until Phase 1.

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

_None — policy locked below._

## Answered (founder, 2026-07-28)

| Question | Answer |
| --- | --- |
| Worker vs skill vs prompt? | **Worker** on team roster (skill + model). **Skill** = shared hat. Body = **skill.md**. |
| Edit shared or fork? | **Shared.** No silent forking. Duplicate skill is explicit only. |
| Bug Hunt family shares Bug Reproducer? | **Yes.** |
| “Seat” in team UI? | **No** — keep **worker** for staffing view; seat is internal if needed. |
| Agent path? | `alln skills edit <id>` + team/worker staffing via GUI or `teams edit`. |
| How to create a new skill? | **+** on SKILL row + **+ New skill…** in dropdown; type-to-create remains as **+ Create "…"**. |
| Worker Done vs Team Save? | **Worker Done** commits changed `skill.md` to catalog. **Team Save** commits roster only. |
| Auto GC? | **Manual / CLI only** (`alln skills gc`). Never on app launch — user skills are data. |
| Lab teams/skills? | **Never in product catalog.** Purge on read; reject saves. Shipped `CatalogLabRetirement`. |
| Stage skill edits in TeamDraft until team Save? | **No** — wrong transaction boundary. |

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
- `alln skills gc` — delete unreferenced custom skills (+ lab skills).
- Edit worker: **+** on SKILL row + persistent **+ New skill…** in skill dropdown
  (`TeamEditorView`, `ALSearchableDropdown`).
- **Lab retirement:** `CatalogLabRetirement` purges `lab-teams/` and `_lab_` skills;
  lab saves rejected (`TeamCatalog`, `SkillCatalog`).
