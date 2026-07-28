# Seat / Skill Sharing

Status: **Brainstorm — founder direction locked on vocabulary + sharing model**;
implementation packet not started
Owner: AllnighterCore + Mac app
Created: 2026-07-28
Updated: 2026-07-28
Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`

Related: `docs/archive/phases/Team_And_Skill_Catalogs.md`,
`docs/archive/phases/Ephemeral_Teams.md`, code SSOT `SkillCatalog.swift`,
`TeamEditorView.swift` (`TeamDraft.commit()`)

## Founder Intent

Define reusable instructions once — Bug Hunter, Copywriter, Documenter — and
staff them on many teams. Edit the Copywriter skill in one place; Spec Review,
an ephemeral `--seat` run, and Bug Hunt all inherit the same prompt.

Analogy: **Claude Code Skills** — a skill is a shared `SKILL.md`; sessions pick
it up. Allnighter must not fork a private copy every time someone tunes a seat.

## Vocabulary (locked)

Drop **worker** as a product noun. It collided with **skill** and **prompt** in
the UI (“First Principles Reviewer” on the roster, again under SKILL, again as
PROMPT body).

| Term | Meaning |
| --- | --- |
| **Team** | A saved lineup of seats (+ lead, scout) |
| **Seat** | One slot on a team — **model + skill** (who wears which hat) |
| **Skill** | Reusable instructions (the hat); shared across teams |
| **Model** | Which CLI/model runs the seat |
| **skill.md** | The skill’s template body (not a separate “prompt”) |

```text
Team  = roster of seats
Seat  = modelId + skillId
Skill = name + lane + purpose + skill.md
```

A team needs **seats**, not “workers.” **Staff seat** is the editor action (not
“Customize worker”).

Ephemeral runs (`alln run --team … --seat …`) inherit the team’s skill ids; only
models change per run — no new skill files.

## Target UX (locked)

Roster row (unchanged shape, clearer meaning):

```text
First Principles Reviewer · Auto
         ↑ skill name          ↑ model
```

**Staff seat** editor — field order and labels:

```text
MODEL
[ Auto ▼ ]

SKILL
[ First Principles Reviewer ▼ ]     [ Restore default ]

skill.md
┌─────────────────────────────────────┐
│ Read the spec from first principles…│
└─────────────────────────────────────┘
Shared across every team that uses this skill.

[ Cancel ]  [ Save ]
```

Changes from today:

1. **Model first** — primary staffing decision.
2. **Skill** — pick the shared hat (catalog dropdown).
3. **`skill.md`** — replaces the PROMPT label; editing here must mean editing the
   **shared skill**, not a seat-local string.
4. Footer copy: shared-skill scope (all teams on this skill id).
5. **Restore default** on edited built-in skills (mirror team overrides).

**Guardrail:** `skill.md` labeling is honest only after fork-on-save is removed
and save writes an override at the same skill id (see B1 below). Until then,
the label would lie.

## Sharing Model (locked)

**Option B — shared skill entity** (Claude Code mental model):

- Tune = edit the skill once at its id.
- Teams keep referencing `skillId`; many teams, one hat.
- Explicit **Duplicate skill** when the user wants a fork, not silent fork-on-save.

Rejected as the default product story:

- **Option A** — fork per team on every prompt edit (today’s mess).
- **Option C / B3** — prompt override on the team row (team-local unless we add
  a second shared layer; more concepts).

**B1 — skill overrides (mirror teams)** is the preferred implementation path:

- `SkillCatalog.get(id)` → user override file at same id ?? built-in seed.
- GUI Save / `alln skills edit <id>` write the override; **Restore** deletes it.
- Bug Hunt Min / Default / Max keep `skillId: bug_reproducer` → all pick up the edit.
- Runs snapshot resolved prompt at dispatch (history stays readable).

**B2 — named shared customs** remains for intentional forks only (`Duplicate
skill…` → new id → assign seats).

## What Works Today

**Built-ins already share by id.** Bug Hunt Min / Default / Max reference the same
skill ids (`bug_reproducer`, …). One seed in `SkillCatalog` → all seats with
that id get the same assembled prompt.

**Teams can override at the same id** (restore to seed). Skills cannot —
`builtInImmutable` / `idCollision`; no override layer.

## What Breaks Sharing

### 1. Fork-on-save (`TeamDraft.commit()`)

Staff seat → edit text → Save calls `SkillCatalog.createCustom()`, repoints
**one** seat to a new id (`"<Skill> for <Team>"`). Sharing gone. Produced 86
orphan lab files (73 GC’d 2026-07-28 via `alln skills gc`; 13 still referenced
by lab teams).

### 2. No skill override-at-same-id

Teams: override at `code_bug_hunt.json`. Skills: built-in always wins lookup.

### 3. Vocabulary collision in the editor

SKILL dropdown + PROMPT field implied two things; PROMPT was the skill body.
Roster “worker” label was the skill display name again.

### 4. Standalone Skills settings tab (removed 2026-07-28)

Orphan junk drawer; removed. Tune at the seat. Picker: built-ins + this team’s
referenced customs only.

## Implementation Phases (proposed)

### Phase 1 — Stop the bleeding

- Kill fork-on-save; default Save → skill override at same id.
- `SkillCatalog.saveOverride` / `restore` (mirror `TeamCatalog`).
- CLI: `alln skills edit` / `restore` on built-in ids.

### Phase 2 — Staff seat UI

- Rename “Customize worker” → **Staff seat**.
- Reorder: Model → Skill → `skill.md`.
- Restore default + “shared across teams” footer.

### Phase 3 — Skill library (optional surface)

- Lane list of skills (built-in + customs); not a duplicate of seat editor.
- Entry from seat editor (“manage skills…”) if needed.

Code names (`skillId`, `TeamWorkerSpec`, `alln skills`) can stay; user-facing
copy uses **seat** and **skill**.

## Open Questions (remaining)

1. **Auto GC:** run `alln skills gc` on app launch, or CLI/manual only?
2. **Lab skills:** separate storage root (like `lab-teams`) so product pickers
   never see lab customs?
3. **Seat label ≠ skill name:** support cosmetic seat labels later, or keep
   seat label = skill display name for v1?

## Answered (founder, 2026-07-28)

| Question | Answer |
| --- | --- |
| Edit shared or fork per team? | **Shared** (override at same skill id). Fork only via explicit Duplicate. |
| Bug Hunt family shares one Bug Reproducer? | **Yes** — requirement. |
| Worker vs skill vs prompt? | **Seat** = model + skill; body is **skill.md**. Retire “worker” in UI. |
| Agent path? | `alln skills edit <id>` + seat/team edits; agents tune skills, teams staff them. |

## Non-Goals (this packet)

- Cross-lane skills.
- Skill marketplace / import-export.
- Version history UI.

## Smallest Proof Slice

```text
1. Staff seat → edit skill.md for bug_reproducer → Save (override, not fork).
2. Run Bug Hunt Min and Bug Hunt Max on the same fixture.
3. Both seats receive the updated template.
4. Restore default → both teams revert to shipped seed.
```

## Shipped Adjacent (2026-07-28)

- Removed Settings → Skills tab.
- Seat skill picker: built-ins + this team’s referenced customs only.
- `alln skills gc` — delete custom skills not referenced by any product or lab team.
