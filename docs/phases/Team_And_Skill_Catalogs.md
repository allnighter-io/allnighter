# Team And Skill Catalogs

Status: Draft founder packet - cleanup-first feature spec
Owner: AllnighterCore + AllnighterCLI + Mac GUI
Updated: 2026-06-17

## Founder Intent

Allnighter has zero users and zero migration burden. This phase is not an
adapter layer. It is a cleanup.

The product model is simple:

```text
TeamCatalog   = every team definition Allnighter knows about
SkillCatalog  = every skill definition Allnighter knows about

TeamID        = stable machine id for one team definition
SkillID       = stable machine id for one skill definition

Team          = rows of workers for one lane
Worker        = one model wearing one skill
Skill         = the instruction/hat a worker wears
```

Do not introduce `TeamStore` or `SkillStore` as product or architecture nouns.
If implementation needs file IO, keep it behind boring private plumbing such as
`TeamCatalogPersistence`, `SkillCatalogPersistence`, or `CatalogFileIO`. Users,
docs, CLI, MCP, debug output, and most code should think in catalogs and IDs.

## Product Value

Settings becomes the Project Manager's control room for the user's lane-owned
teams and skills:

```text
CLIs

BUILD
  Teams
  Skills

DESIGN
  Teams
  Skills

COPY
  Teams
  Skills
```

The user can duplicate a built-in team, tune its workers, duplicate or create
lane-specific skills, and run the custom team without SwiftUI, prompt prose, or
hidden legacy prompt libraries inventing alternate truth.

## Trusted Workflow Slice

```text
open terminal
-> alln skills --lane build --json
-> alln teams --lane build --json
-> duplicate a built-in Build skill
-> edit the custom skill template
-> duplicate a built-in Build team
-> replace one team row with the custom SkillID
-> run the custom team
-> inspect latest run and see the worker used the custom skill snapshot
```

This is the smallest slice that proves the real feature: teams and skills are
editable together, lane-owned together, and resolved through one catalog path.

## Non-goals

- No migration code. Delete or rename old internal shapes instead of preserving
  aliases for nonexistent users.
- No `TeamStore` / `SkillStore` architecture vocabulary.
- No explicit skill version-history feature in the MLP.
- No cross-lane teams or cross-lane skills.
- No noun-first Settings nav (`Teams | Skills` with lane filters).
- No GUI-only team or skill truth.
- No import/export in the MLP.
- No cloud sync, account sync, marketplace, sharing, or permission change.
- No cost, runtime, quota, or difficulty forecast from team or skill choice.

## Current State

### Useful substrate

- Core already has a built-in team catalog shape for lane teams.
- Core already has a built-in skill catalog shape for prompt templates.
- Built-in teams already reference `skillId` rows.
- `TeamRunJSON` already carries worker skill identifiers and names.
- CLI M1 already has team-run contracts, contract registry generation, and proof
  gates.

### Cleanup targets

These are not compatibility promises. They are deletion or rename targets for
this feature:

| Current shape | Problem | Cleanup target |
| --- | --- | --- |
| `Skill.laneTags: [WorkLane]` | Implies cross-lane skill membership | `Skill.lane: WorkLane` |
| Skill `version` as run-history mechanism | Adds version-history machinery before value is proven | Snapshot resolved skill content into the run |
| `AllnighterEngine.SkillLibrary` | Parallel hard-coded prompt truth | Delete; route through `SkillCatalog` |
| `DesignPersonaLibrary` | Persona is old skill language and parallel design prompt truth | Fold design skills into `SkillCatalog` |
| SwiftUI/local skill arrays or templates | GUI can drift from Core | Delete; GUI reads catalog APIs |
| `TeamStore` / `SkillStore` doc language | Splits the mental model | Use `TeamCatalog` / `SkillCatalog` |
| Quick / Standard / Deep or Low / Med / High as generic team-depth UI | Hides team shape behind a second selector | Named Team variants; provider reasoning effort only inside model/worker config |

## Truth Owner

```text
AllnighterCore.TeamCatalog
AllnighterCore.SkillCatalog
AllnighterCore.TeamID
AllnighterCore.SkillID
AllnighterCore.TeamDefinition
AllnighterCore.SkillDefinition
```

Catalogs own both built-in and custom definitions:

```text
TeamCatalog
  list(lane)
  get(TeamID)
  duplicateBuiltIn(TeamID, name)
  saveCustom(TeamDefinition)
  deleteCustom(TeamID)

SkillCatalog
  list(lane)
  get(SkillID)
  duplicateBuiltIn(SkillID, name)
  saveCustom(SkillDefinition)
  deleteCustom(SkillID)
```

Built-ins are shipped product assets. They are read-only at runtime. Editing a
built-in always creates a custom definition with a new ID.

Persistence is private plumbing under the catalog, not a second source of truth.

## Definitions

### TeamID

`TeamID` is a stable machine identifier for one team definition.

Rules:

- Global namespace across all lanes.
- Lowercase snake case: `^[a-z][a-z0-9_]{2,63}$`.
- Built-in IDs are reserved forever while the built-in exists.
- Custom IDs are generated by default.
- Custom IDs should include the lane when generated, e.g.
  `custom_build_mikes_bug_hunt`.
- CLI may accept `--id` only for tests/import-style workflows, and must reject
  invalid or colliding IDs.

### SkillID

`SkillID` is a stable machine identifier for one skill definition.

Rules:

- Global namespace across all lanes.
- Lowercase snake case: `^[a-z][a-z0-9_]{2,63}$`.
- Built-in IDs are reserved forever while the built-in exists.
- Custom IDs are generated by default.
- Custom IDs should include the lane when generated, e.g.
  `custom_copy_mikes_proof_skeptic`.
- A Team row references a `SkillID`, never inline prompt prose.

### TeamDefinition

```text
id: TeamID
displayName
origin: builtIn | custom
lane: Build | Design | Copy
outputKind
defaultEffort: low | med | high
typeTags: optional subtype metadata
workerRows: [TeamWorkerDefinition]
synthesisPolicy
createdAt: custom only
updatedAt: custom only
```

Every team belongs to exactly one lane.

### TeamWorkerDefinition

```text
id
skillId: SkillID
preferredModelId
fallbackPolicy
purpose: answer | review | planWriter
minEffort: low | med | high
required: Bool
```

At save time and run time, `skillId` must resolve to a skill in the same lane as
the team.

### SkillDefinition

```text
id: SkillID
displayName
origin: builtIn | custom
lane: Build | Design | Copy
purpose: answer | review | planWriter
template
createdAt: custom only
updatedAt: custom only
```

Every skill belongs to exactly one lane.

## Semantic Rules

### Catalogs

- `TeamCatalog` and `SkillCatalog` are the only lookup surfaces for teams and
  skills.
- Catalogs include built-in and custom definitions.
- Built-ins cannot be edited or deleted in place.
- Custom definitions are mutable through catalog APIs only.
- Catalog list APIs are lane-scoped.
- Catalog detail APIs are ID-scoped.
- Similar display names across lanes are separate IDs and separate definitions.

### Lane ownership

Teams and skills are lane-owned, not lane-tagged.

```text
team.lane: Build | Design | Copy
skill.lane: Build | Design | Copy
```

There are no shared teams, shared skills, multi-lane teams, or multi-lane skills.
If the same posture belongs in another lane, duplicate and tune it there.

### Built-in vs custom

| Rule | Built-in | Custom |
| --- | --- | --- |
| Editable | No | Yes |
| Deletable | No | Yes, with reference checks |
| ID | Product-owned stable ID | Generated stable ID |
| Lane | Exactly one | Exactly one, immutable after create |
| Persistence | App bundle / Core source | Catalog persistence |

### No skill versioning in the MLP

Versioning answers this question:

```text
Which historical variant of this mutable skill did the run use?
```

For the MLP, snapshotting answers that question with less machinery.

Every run should snapshot the resolved worker skill data needed for history:

```text
skillId
skillDisplayName
skillTemplateSnapshot or resolvedWorkerPromptSnapshot
```

The public run summary may show only ID/name. The local run journal or audit data
must retain the resolved prompt/template that was actually used. After a custom
skill is edited, old runs stay readable because they carry their own snapshot.

Do not add `skillVersion` as required MLP truth. If version history later becomes
a product feature, add it deliberately with a history browser and old-version
retrieval. Do not smuggle it into this cleanup.

### Deletion

- Built-in teams and skills cannot be deleted.
- Deleting a custom team does not affect past runs; past runs carry snapshots.
- Deleting a custom skill fails if any current team definition references it.
- The error must name the referencing TeamIDs.
- If the user wants to delete the skill, they first remove or replace those team
  rows.

Because custom teams and custom skills live under the same catalog feature, this
reference check is part of the MLP. It is not deferred to a separate TeamStore.

### Run resolution

Run assembly is:

```text
TeamID -> TeamCatalog.get
team.workerRows[].skillId -> SkillCatalog.get
same-lane validation
model/fallback resolution
resolved workers
run snapshot
```

No run path may assemble prompts through `SkillLibrary`, `DesignPersonaLibrary`,
SwiftUI arrays, fixture data, or inline team prompt strings.

## Settings Navigation

Settings is lane-first:

```text
CLIs                         <- lane-agnostic; sources/models feed every lane

BUILD
  Teams
  Skills

DESIGN
  Teams
  Skills

COPY
  Teams
  Skills
```

Default landings:

| Entry | Lands on |
| --- | --- |
| Health badge / `N ready` | CLIs |
| Settings gear | CLIs |
| Composer Manage team | Current lane's Teams |
| Composer Customize | Current selected team editor/drawer, not the generic Settings landing |

`Customize` and `Manage team` are not the same action. `Customize` edits the
current team in context. `Manage team` opens the lane's Teams catalog.

## CLI Contract

Catalog commands use plural nouns:

```bash
alln teams --lane build|design|copy [--json]
alln teams show <team-id> [--json]
alln teams duplicate <team-id> [--name <displayName>] [--json]
alln teams new --lane build|design|copy --name <displayName> [--json]
alln teams edit <team-id> [--file <path>] [--json]
alln teams delete <team-id> [--json]

alln skills --lane build|design|copy [--json]
alln skills show <skill-id> [--json]
alln skills duplicate <skill-id> [--name <displayName>] [--json]
alln skills new --lane build|design|copy --name <displayName> --purpose answer|review|planWriter [--template-file <path>] [--json]
alln skills edit <skill-id> [--name <displayName>] [--template-file <path>] [--json]
alln skills delete <skill-id> [--json]
```

The existing run command can remain owned by the CLI spine. This phase owns the
catalog management nouns. Avoid awkward catalog shapes such as `team teams` in
new docs and MCP tools.

List responses omit full templates by default. Show responses include template
details for skills and worker row details for teams.

### CLI errors

| Code | When |
| --- | --- |
| `TEAM_NOT_FOUND` | Unknown TeamID |
| `TEAM_BUILTIN_IMMUTABLE` | Edit/delete built-in team |
| `TEAM_ID_COLLISION` | New custom team ID collides |
| `TEAM_INVALID` | Missing lane/name/rows or invalid effort/output kind |
| `SKILL_NOT_FOUND` | Unknown SkillID |
| `SKILL_BUILTIN_IMMUTABLE` | Edit/delete built-in skill |
| `SKILL_ID_COLLISION` | New custom skill ID collides |
| `SKILL_IN_USE` | Delete custom skill referenced by team definitions |
| `SKILL_LANE_MISMATCH` | Team row references a skill from another lane |
| `SKILL_INVALID` | Empty template, missing lane, unknown purpose |
| `CATALOG_ID_INVALID` | ID fails canonical ID rules |

## MCP Contract

MCP tools should mirror the catalog nouns:

```text
teams_list
teams_show
teams_duplicate
teams_save
teams_delete
skills_list
skills_show
skills_duplicate
skills_save
skills_delete
```

Tools must use the same JSON schemas as the CLI registry. Do not maintain a
separate MCP-only team or skill schema.

## Implementation Slices

### S00 - Cleanup current catalog vocabulary

- Replace `Skill.laneTags` with `Skill.lane`.
- Remove skill `version` as required run-history truth.
- Add `TeamID` and `SkillID` types or typealiases.
- Rename code and docs away from `SkillStore` / `TeamStore`.
- Replace Quick / Standard / Deep or Low / Med / High team-depth UI references
  with named Team variants.
- Tests: every built-in skill has exactly one lane; every built-in team row
  references a same-lane skill.

### S01 - Unified built-in catalogs

- Make `TeamCatalog` expose built-in team definitions through the final API.
- Make `SkillCatalog` expose built-in skill definitions through the final API.
- Fold design personas into lane-owned design skills.
- Delete `AllnighterEngine.SkillLibrary`.
- Delete `DesignPersonaLibrary` or reduce it to a compatibility-free facade only
  if removed in the same slice.
- Tests: no run path imports old prompt/persona libraries.

### S02 - Custom catalog persistence behind the catalog

- Add private persistence under `TeamCatalog` and `SkillCatalog`.
- Persist custom definitions under Application Support.
- Atomic writes.
- Catalog APIs merge built-ins + customs into one lookup/list surface.
- Built-in IDs always win and are reserved.
- Tests: custom team/skill round-trip, restart reload, ID collision rejection,
  lane immutability after create.

### S03 - Catalog CLI + MCP

- Add `alln teams` and `alln skills` commands.
- Register schemas, examples, and errors in `ContractRegistry`.
- Add MCP tools from the same registry/schema source.
- Tests: list/show/duplicate/edit/delete for teams and skills.
- Contract check: `alln dev export-contracts --check`.

### S04 - Resolver integration

- Run assembly resolves team and skill IDs only through catalogs.
- Team save and run resolve reject wrong-lane SkillIDs.
- Skill delete scans current TeamCatalog references.
- Run journals snapshot resolved skill content used by each worker.
- Tests: wrong-lane skill rejected at save and run; custom skill prompt reaches
  worker; editing a custom skill after a run does not alter that run snapshot.

### S05 - Mac Settings GUI

- Settings nav is lane-first: CLIs, then Build/Design/Copy, each with Teams and
  Skills.
- Teams and Skills lists read catalog APIs.
- Detail/edit views mutate through catalog APIs.
- `Customize` edits the current selected team in context.
- `Manage team` opens the current lane's Teams catalog.
- GUI proof gate applies because this changes visible navigation and edit flows.

## Mac App Impact

- Remove skill/team template truth from view-local state except edit drafts.
- Settings owns catalog browsing and editing.
- Composer owns lane/team selection and may open contextual team editing.
- The GUI must never write catalog files directly.

## iOS App Impact

- iOS can read catalog summaries later for floor-manager context.
- Editing remains Mac-first in the MLP.
- iOS must not create parallel skill/team definitions.

## Driver / Protocol Impact

- Worker drivers receive resolved prompts as they do today.
- Prompt assembly moves behind catalog resolution.
- Public run JSON should expose worker `skillId` and `skillName`.
- Local run journal/audit should retain resolved prompt or template snapshot for
  history.

## Auth / Privacy / Permission Impact

- No new macOS permissions.
- Custom skill templates are local user-authored prompt content.
- Run snapshots may include skill prompt text locally; do not sync or export them
  without an explicit future export/privacy spec.

## Lie-prone Layers

| Layer | Lie risk | Guard |
| --- | --- | --- |
| SwiftUI Settings | Local arrays become fake catalog truth | Views read catalog APIs only |
| Composer customize drawer | Shows skills from wrong lane | Skill picker uses `SkillCatalog.list(team.lane)` |
| Run assembly | Old prompt libraries survive | Import/test ban on old libraries |
| CLI docs | Advertise commands before registry handlers exist | Contract export check |
| MCP tools | Separate JSON schema | Registry-derived tools only |
| Run history | Shows latest skill template as if historical | Snapshot resolved skill content at run time |
| Delete flow | Deletes a skill still used by a team | Catalog reference check |

## Works Tests

### WT-CAT01 - Read lane catalogs

```bash
alln teams --lane build --json | jq -e '.teams | length > 0'
alln skills --lane build --json | jq -e '.skills | length > 0'
alln skills --lane build --json | jq -e 'all(.skills[]; .lane == "build")'
```

### WT-CAT02 - Duplicate skill and team

```bash
SKILL_ID=$(alln skills duplicate contrarian_reviewer --name "WT Build Contrarian" --json | jq -r '.id')
alln skills edit "$SKILL_ID" --template-file ./fixtures/skills/wt_contrarian.txt --json
TEAM_ID=$(alln teams duplicate build_core --name "WT Build Team" --json | jq -r '.id')
alln teams edit "$TEAM_ID" --file ./fixtures/teams/wt_build_team_with_custom_skill.json --json
alln teams show "$TEAM_ID" --json | jq -e --arg sid "$SKILL_ID" '.workerRows[] | select(.skillId == $sid)'
```

### WT-CAT03 - Wrong-lane skill rejected

```bash
alln teams edit "$TEAM_ID" --file ./fixtures/teams/wrong_lane_skill.json --json 2>&1 | grep -q SKILL_LANE_MISMATCH
```

### WT-CAT04 - Skill delete reference guard

```bash
alln skills delete "$SKILL_ID" --json 2>&1 | grep -q SKILL_IN_USE
```

### WT-CAT05 - Run snapshot survives edit

```bash
alln team "catalog proof" --lane build --team "$TEAM_ID" --json > /tmp/catalog_run.json
alln skills edit "$SKILL_ID" --template-file ./fixtures/skills/wt_contrarian_v2.txt --json
RUN_ID=$(jq -r '.teamRun.id' /tmp/catalog_run.json)
alln show "$RUN_ID" --json | jq -e '.workers[] | select(.skillId == env.SKILL_ID)'
# Local journal/audit assertion: resolved skill prompt snapshot is the v1 prompt, not v2.
```

## Proof Command

```bash
swift test --filter Catalog
swift test --filter TeamCatalog
swift test --filter SkillCatalog
swift test --filter CatalogCLI
alln dev export-contracts --check
```

GUI slice proof additionally requires the GUI visual proof gate.

## Done When

- No `TeamStore` / `SkillStore` terminology remains in active catalog specs.
- `TeamCatalog` and `SkillCatalog` include built-in and custom definitions.
- Every team and skill has exactly one lane.
- Custom teams and custom skills can be duplicated, edited, persisted, listed,
  shown, and deleted through catalog APIs.
- Built-ins are duplicate-to-edit only.
- Team rows reference `SkillID`, never inline skill prompt prose.
- Wrong-lane SkillIDs are rejected at save and run resolve.
- Deleting an in-use custom skill fails with referencing TeamIDs.
- All run prompt assembly uses catalog-resolved skills.
- Old prompt/persona libraries are deleted, not adapted.
- Runs snapshot the resolved skill content they used; no MLP skill-version
  machinery is required.
- Settings nav is lane-first and all seven destinations are reachable.

## Open Questions

1. Should `alln teams edit` accept a full replacement JSON file only for MLP, or
   also offer row-level commands?
2. Should custom generated IDs include a short random suffix by default to avoid
   name collision noise?
3. Should local run journals expose skill prompt snapshots in normal `alln show
   --json`, or only in `alln show --full --json`?

## Routing

| Work | Read first |
| --- | --- |
| Catalog semantics, custom team/skill editing, lane-first Settings | This doc |
| Product vocabulary | `Work_Order_Team_Model.md` |
| Existing built-in team packs | `Fanout_Team_Catalog.md` |
| CLI registry and generated contracts | `CLI_Implementation_Contract.md` |
| Settings GUI implementation | `docs/gui/GUI_Workflow.md` + `GUI_Visual_Proof_Gate.md` |
| Bench/source setup | `setup/README.md` + `wiring/design_handoff_bench_and_wiring/WIRING.md` |
