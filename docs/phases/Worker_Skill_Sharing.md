# Worker / Skill Sharing

Status: **Brainstorm** — seeking founder feedback before a build packet
Owner: AllnighterCore + Mac app
Created: 2026-07-28
Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`

Related: `docs/archive/phases/Team_And_Skill_Catalogs.md`,
`docs/archive/phases/Ephemeral_Teams.md`, code SSOT `SkillCatalog.swift`,
`TeamEditorView.swift` (`TeamDraft.commit()`)

## Founder Intent

A skill is a reusable “hat” — Bug Reproducer, Contrarian Root Cause, Copywriter,
etc. If you tune that hat once, every team and worker wearing it should inherit
the update. Today that breaks the moment anyone customizes a worker prompt.

Analogy: Claude Code skills are shared across sessions. Allnighter has the same
bug across teams — tune Bug Reproducer on Bug Hunt Min and Bug Hunt Max still
runs the old template.

## What Works Today

**Shipped built-ins already share by id.**

Bug Hunt Min, Bug Hunt, and Bug Hunt Max all reference the same skill ids
(`bug_reproducer`, `truth_owner_mapper`, `correct_fix_planner`, …). One built-in
template in `SkillCatalog` → all teams that point at that id get the same prompt
at run time (`SkillCatalog.assemblePrompt`).

**Teams can override at the same id** (restore to seed). Editing `code_bug_hunt`
in Settings → Teams saves an override file at the same team id; restore brings
back the shipped roster.

**Skills cannot.** `alln skills edit bug_reproducer` fails (`builtInImmutable`).
There is no skill override layer.

## What Breaks Sharing

### 1. Fork-on-save in the team editor

Teams → Customize worker → edit prompt → Save calls
`SkillCatalog.createCustom()` and repoints **only that team’s row** to the new id.
Name defaults to `"<Skill> for <Team>"`.

- Built-in `bug_reproducer` is never mutated.
- Each save mints a new file even when the template is unchanged.
- Other teams keep the built-in id until separately edited → N forks for the same
  logical hat.

This is how 86 orphan `custom_code_lab_*` files accumulated during Team Lab
dogfood (now GC’d via `alln skills gc`; lab teams still hold 13 references).

### 2. No skill override-at-same-id

Teams: `saveCustom` at `code_bug_hunt` → override, list shows one entry, restore
works.

Skills: `saveCustom` rejects built-in ids (`idCollision` / `builtInImmutable`).
Lookup is `builtIn byID[id] ?? custom file` — a file at `bug_reproducer.json`
would never win.

### 3. Standalone Skills settings tab (removed 2026-07-28)

The lane Skills browser listed every custom file on disk, including orphans, with
no edit/delete and a misleading “Duplicate to tune one” subtitle. Removed; tune
at the worker. Orphan GC: `alln skills gc`.

## User-Visible Symptoms

| Symptom | Cause |
| --- | --- |
| Seven “Lab Contrarian Root Cause” rows in Skills | Seven fork files, same display name |
| Tune worker on Min, Max unchanged | Fork repoints one team only |
| Agent cannot “edit Bug Reproducer for all Bug Hunt tiers” | No shared custom skill path without manual team row surgery |
| Skill picker polluted with lab orphans | `SkillCatalog.list()` included all customs (fixed: picker shows built-ins + this team’s refs) |

## Product Question

**What is the unit of reuse?**

```text
Option A — Team-scoped prompt (current fork model)
  Tune = new skill per team. Sharing is accidental (built-ins only).

Option B — Shared skill entity (Claude Code skill mental model)
  Tune = edit the skill once. Teams reference skillId. Many teams, one hat.

Option C — Hybrid
  Built-ins + explicit “shared custom” skills; team rows can optionally pin a
  local override without forking the catalog entry.
```

Founder lean from dogfood: **B or C**. A fork-per-team is an implementation
artifact, not a product story.

## Brainstorm Directions

### B1 — Skill overrides (mirror teams)

- `alln skills edit bug_reproducer` / GUI “Save” writes
  `Catalogs/skills/bug_reproducer.json` (override).
- `SkillCatalog.get` merges override over built-in seed; `teams restore` analogue
  for skills.
- Bug Hunt Min / Default / Max keep `skillId: bug_reproducer` → all pick up the
  override.

**Pros:** Minimal id churn; matches team override mental model.
**Cons:** Need restore, list UX, and “edited built-in” badge.

### B2 — Named shared customs only

- Keep built-ins immutable.
- `alln skills duplicate bug_reproducer --name "Mike Bug Reproducer"` →
  `custom_code_mike_bug_reproducer`.
- Reassign team rows (manually or “apply to all Bug Hunt teams”).
- Edit the custom once → all rows pointing at that id update.

**Pros:** Clear separation of shipped vs user assets.
**Cons:** Requires reassignment workflow; easy to leave teams on built-in id.

### B3 — Stop forking; store prompt on the team row

- `TeamWorkerSpec` carries optional `promptOverride: String?`.
- Run resolver: override ?? `SkillCatalog.template(skillId)`.
- No new skill file per edit; sharing stays on skillId.

**Pros:** No orphan skills; sharing is natural for built-ins.
**Cons:** Custom prompts are team-local unless we add a shared override table;
  run snapshots must record resolved prompt (already partially true).

### B4 — Dedup on fork

- On save, if edited template matches an existing custom skill (hash or exact),
  repoint row to that id instead of `createCustom()`.

**Pros:** Stops orphan explosion; cheap incremental fix.
**Cons:** Does not fix “tune once, all teams update”; display-name collisions.

## Open Questions for Founder

1. **Default stance:** Should editing a built-in worker prompt affect every team
   using that skill id (override), or only this team (fork)?

2. **Cross-variant families:** Bug Hunt Min / Default / Max — is “one Bug
   Reproducer for the whole family” a requirement or nice-to-have?

3. **Agent workflow:** Is `alln skills edit <id>` the right headless path, or
   should agents only ever call `teams edit` and we fix sharing underneath?

4. **GC policy:** Auto-run `alln skills gc` on app launch, or manual/CLI only?
   (Lab left 73 orphans; 13 remain referenced by lab teams.)

5. **Lab storage:** Should lab skills live under a separate root (like
   `lab-teams`) so product pickers never see them?

## Non-Goals (this packet, until decided)

- Cross-lane skills.
- Skill marketplace / import-export.
- Version history UI.

## Smallest Proof Slice (when we pick a direction)

```text
1. Edit bug_reproducer once (GUI or CLI).
2. Run Bug Hunt Min and Bug Hunt Max on the same prompt fixture.
3. Both workers receive the updated template in the assembled prompt.
4. Restore returns the shipped seed; both teams revert.
```

## Shipped Adjacent (2026-07-28)

- Removed Settings → Skills tab (tune at worker only).
- Worker skill picker: built-ins + this team’s referenced customs only.
- `alln skills gc` — delete custom skills not referenced by any product or lab team.
