# Worker / Skill Sharing

Status: **Code Complete (WSS-S01)** — archive when founder signs Works Test
Owner: `SkillCatalog` (semantic truth); `ContractRegistry`, `RunService`, and the
Mac app project or consume it
Created: 2026-07-28
Updated: 2026-07-28 (WSS-S01 shared-skill cutover shipped)
Next work order: none (archive after Works Test sign-off)

Process:
`docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`

Related history:
`docs/archive/phases/Team_And_Skill_Catalogs.md`,
`docs/archive/phases/Ephemeral_Teams.md`

## Founder Intake

**Raw request:** Define a reusable instruction once — Bug Hunter, Copywriter,
Documenter — and staff it on many Teams. Editing that Skill in one place must
change every Worker that references it. The current silent per-Team copies are
unworkable.

**Product value:** A human or agent can understand and tune the bench without
maintaining a pile of almost-identical prompt forks.

**Trusted workflow slice:**

```text
edit Bug Reproducer once
→ Bug Hunt Min / Bug Hunt / Bug Hunt Max keep one skillId
→ later runs use the edited body
→ Restore default returns all three to the shipped body
```

**Current truth owner:** `SkillCatalog.swift`.

**CLI surface:** `alln skills edit`, `alln skills restore`, and the existing
`skills` / `skills show` / `skills new` / `skills duplicate` commands.

**Help surface:** `HelpTopicRegistry.teams_and_workers`; search terms `edit
skill`, `shared skill`, `restore skill`, `skill.md`, and `worker skill`;
ordinary `nextToolPlan` recovery remains the fallback.

**Risk:** Local catalog data and prompt instructions only. No privacy,
credentials, Keychain, permission, session-kill, distribution, billing, iOS, or
protocol change. The shared-edit blast radius must be visible before the Mac app
commits it.

**Blocking questions:** None. Founder decisions are recorded below.

## Prior Art

Claude Code uses a stable named Skill with one required `SKILL.md`; consumers
discover and reuse that Skill, and edits are picked up without minting a copy for
each caller. See [Extend Claude with
skills](https://code.claude.com/docs/en/slash-commands).

Allnighter adopts the same useful convention: **reference a stable identity;
copy only through an explicit Duplicate action.** It does not adopt Claude's
filesystem layout. Allnighter must send the same Skill through many vendor CLIs,
so its Markdown body remains `Skill.template` in the Core-owned JSON catalog.
`skill.md` is the honest UI label for that Markdown body, not a promised
filesystem path or import/export format.

## Current State (Verified Against Code)

| Area | Current truth | Gap WSS-S01 closes |
| --- | --- | --- |
| Built-in Skills | Compiled seeds in `SkillCatalog.builtIns` | `SkillCatalog.skill` returns the seed before checking disk, so a same-ID override cannot take effect |
| Custom Skills | `Catalogs/skills/<id>.json`; edit-in-place works | No change to custom identity semantics |
| Built-in sharing | Bug Hunt Min / Bug Hunt / Bug Hunt Max already reference `bug_reproducer` | Shared IDs work only while the seed is immutable |
| Team overrides | Same-ID override + Restore already work in `TeamCatalog` | Skill catalog needs the same merge model |
| Mac Worker editor | `promptDraft` is staged on `TeamDraft.Row`; Team Save calls `createCustom()` and repoints the row | This is the silent fork to delete |
| Auto rows | Core uses `preferredModelId == nil` for Auto; the drill-in says `Pick a model` and blocks Done | Skill-only work must preserve valid Auto staffing |
| CLI | `alln skills edit` calls `saveCustom`, so built-ins fail with `SKILL_BUILTIN_IMMUTABLE` | Built-in edit must write an override; add Restore |
| Read JSON | Skill list/show expose `builtIn` but not `origin` or `restoreAvailable` | Agents cannot distinguish seed / override / custom reliably |
| Help | Says built-in Teams are immutable and omits shared edit/Restore | Teaching is stale and must change in the same slice |
| Lab cleanup | `CatalogLabRetirement` rejects/purges retired lab artifacts; `alln skills gc` purges orphans manually | Already shipped; do not reopen or mix it into WSS-S01 |

The old fork behavior is also asserted by
`Apps/AllnighterMac/Tests/TeamDraftTests.swift`; those tests are evidence of the
current defect, not desired behavior.

Implementation preflight: current HEAD already has contract drift from the
recent `skills gc` registration (`CONTRACT_VERSION_NOT_BUMPED` at 5.1.0) and
unsealed GUI-proof debt, including unrelated surfaces. WSS-S01's 5.2.0 export
must absorb the contract drift. Do not sweep unrelated GUI files into this
slice; WSS-S01 must seal the Worker editor it changes, while the other surface
owners resolve their own proof debt before the repository-wide wall can be
green.

## Locked Product Semantics

### Vocabulary

The standing nouns remain those in
`docs/workflows/Product_Vocabulary.md`:

```text
Team   = Workers + Lead (+ optional Scout)
Worker = modelId + skillId for one staffed roster row
Model  = who runs the row
Skill  = the shared instruction profile the Model wears
```

Team staffing UI uses **AGENTS** with **MODEL | SKILL** column headers,
**+ Add agent**, **Team Lead**, and the `N agents + 1 lead` summary. Model is
staffed on the roster row; the skill cell opens **Edit skill** (Skill →
skill.md). Do not add Prompt as a fourth concept. `Seat` and `Worker` remain
internal architecture words, not staffing labels.

`TeamWorkerSpec.preferredModelId == nil` is the existing **Auto** staffing
choice. It is valid on the roster row and must remain nil when the user edits
only a Skill; never relabel it `Pick a model` or force a concrete Model as the
price of saving Skill work.

Ephemeral `alln run --team … --seat …` changes Models for that invocation. It
does not create, duplicate, or edit Skills.

### One identity, seed + override

For a built-in Skill ID:

```text
effective Skill = same-ID user override, when present
               ?? shipped seed
```

- Editing a built-in Skill writes a file at the **same ID**. It may change
  `displayName` and `template`; it may not change `id`, `lane`, or `purpose`.
- Editing a custom Skill updates that custom Skill at its existing ID.
- Updating an override never repoints a Team row and never creates a
  `"<Skill> for <Team>"` Skill.
- **Restore** removes the built-in's override and reveals the current shipped
  seed. Restore is idempotent.
- **Duplicate Skill** and **New Skill** are the only actions that mint a new ID.
- `skills delete` remains custom-only. It is not a hidden alias for Restore.
- A future app update may change a shipped seed. An existing user override
  continues to mask it until Restore.

`Skill.builtIn` alone cannot represent all three effective origins. The public
derived origin is:

```text
seed | override | custom
```

Code and UI must use the derived origin / `hasOverride`, not infer origin from
`builtIn == false`.

### Transaction boundaries

Skill changes and Team roster changes have different owners and therefore
different commit points:

| Gesture | Commit |
| --- | --- |
| Cancel Worker changes | Discard local Model / Skill / skill.md edits; write nothing |
| Worker **Done**, existing Skill body changed | Save that Skill at the same ID |
| Worker **Done**, explicit New Skill | Create the named custom Skill immediately, then stage its new `skillId` on the roster row |
| **Restore default** | Remove the same-ID override immediately and reload the shipped body |
| Team **Save** | Save roster facts only: Team fields, `skillId`, and `modelId` assignments |
| Team **Cancel** | Discard the roster draft only; do not roll back a Skill already committed with Worker Done |

This deliberately resolves a contradiction in the prior draft: a New Skill
cannot wait for Team Save while Skill and Team writes are separate transactions.
An explicitly created Skill may become unreferenced if the user later cancels
the Team. That is honest user data, not a failed transaction; manual
`alln skills gc` remains the cleanup path. Never auto-GC on launch.

If Worker Done cannot save or create the Skill, stay in the Worker editor, show
the observed error, and leave the roster row unchanged.

### Blast radius

Before Skill Done commits a changed existing Skill, the Mac app shows every
saved Team that currently references the ID, by display name:

```text
Shared across 3 teams: Bug Hunt Min · Bug Hunt · Bug Hunt Max
```

The list includes Worker, Lead, and Scout references, deduplicated by Team ID and
sorted by display name. Empty copy is explicit: `Not used by a saved team yet.`
For a new Skill: `New skill — it is not used until you save this team.`

No confirmation modal is required. Exact, persistent visibility is the guard;
the primary action remains Worker Done.

### Run boundary

`RunService` resolves and snapshots the effective Skill name/body for every
Worker, Lead, and Scout before the run spawns its first provider process. An edit
affects runs accepted afterward. It must not mutate the prompt or history of an
already accepted run.

Persisted `resolvedWorkerPromptSnapshot` remains the historical proof. Replaying
or rendering an old run reads its snapshot, never today's catalog body.

## CLI Contract

### Commands

| Command | Behavior |
| --- | --- |
| `alln skills [--lane <lane>] [--json]` | List effective Skills once per ID, including origin and Restore availability |
| `alln skills show <skill-id> [--json]` | Show the effective Skill body and origin |
| `alln skills edit <skill-id> [--name <name>] [--template-file <path>] [--json]` | Update a custom Skill or write a same-ID built-in override |
| `alln skills restore <skill-id> [--json]` | Idempotently remove a built-in override |
| `alln skills duplicate <skill-id> [--name <name>] [--json]` | Explicitly mint a custom copy |
| `alln skills new …` | Explicitly mint a new custom identity |

No alias is added for the retired fork-on-Team-Save behavior.

### Read / mutation receipt

Replace the anonymous CLI-local detail encoder with one Core-owned
`SkillDetailJSON` projection used by show, new, duplicate, and edit:

```json
{
  "schemaVersion": 2,
  "contractVersion": "5.2.0",
  "id": "bug_reproducer",
  "displayName": "Bug Reproducer",
  "lane": "code",
  "purpose": "answer",
  "builtIn": false,
  "origin": "override",
  "seedId": "bug_reproducer",
  "restoreAvailable": true,
  "template": "Reproduce from the smallest...",
  "createdAt": "2026-07-28T20:59:00Z",
  "updatedAt": "2026-07-28T21:00:00Z"
}
```

`SkillCatalogJSON.Entry` adds the same `origin`, `seedId`, and
`restoreAvailable` fields (without `template`) and advances to schema version 2.
`origin` is authoritative; `builtIn` stays for compatibility and is true only
for an effective unedited seed.

Restore JSON:

```json
{
  "schemaVersion": 1,
  "contractVersion": "5.2.0",
  "id": "bug_reproducer",
  "restored": true,
  "origin": "seed"
}
```

Text output:

```text
restored bug_reproducer to shipped version
bug_reproducer already at shipped version
```

### Errors and exits

| Condition | Error | Exit |
| --- | --- | --- |
| Success, including already-restored seed | — | 0 |
| Missing ID / unknown flag / bad lane | `CLI_USAGE_ERROR` / `UNKNOWN_FLAG` | 2 |
| Unknown Skill ID | `SKILL_NOT_FOUND` | 1 |
| Restore requested for a custom Skill | `SKILL_RESTORE_UNSUPPORTED` | 1 |
| Empty body / changed seed lane or purpose / invalid definition | `SKILL_INVALID` | 1 |
| Catalog write failure | observed operational error; never success | 1 |

Retire `SKILL_BUILTIN_IMMUTABLE` from the edit path. It remains valid for
`skills delete <built-in-id>`. Do not reuse `TEAM_RESTORE_UNSUPPORTED` for a
Skill error.

This is an additive command plus JSON-shape change: bump the contract from
5.1.0 to 5.2.0 (or the next unused minor if HEAD moved), regenerate contracts,
and bump the binary patch version at closeout.

## Mac Presentation

The existing skill drill-in is the only Skill editing surface:

```text
Edit skill · Bug Reproducer
Auto · Bug Hunt

SKILL                                           [ + ]
[ Bug Reproducer ▼ ]                 [ Restore default ]

skill.md
┌──────────────────────────────────────────────┐
│ Reproduce from the smallest failing case... │
└──────────────────────────────────────────────┘
This skill is used by 3 teams: Bug Hunt Min · Bug Hunt · Bug Hunt Max
Model applies to this team only — change it on the roster row.

[ Cancel skill changes ]  [ Done ]
```

Roster (parent screen):

```text
AGENTS
MODEL              SKILL
[ Auto ▼ ]         [ Bug Reproducer › ]
[ + Add agent ]
```

Rules:

- Field order in the drill-in is Skill → skill.md. Model is roster-only.
- Model nil renders as Auto and does not block Worker Done.
- Restore appears only for an overridden built-in and refreshes the editor to
  the seed after a successful Core write.
- **+** on the Skill label and persistent **+ New skill…** in the picker enter
  the same explicit new-Skill flow. Typed **+ Create "…"** remains.
- Existing Skill edits do not show a fork name field.
- The picker contains effective built-in seed/override entries plus the custom
  Skills already referenced by this Team. An override must not disappear merely
  because its effective `builtIn` value is false.
- The removed Settings → Skills page stays removed.
- No iOS or shared SwiftUI work is in scope.

## WSS-S01 — Shared-Skill Cutover

One work order closes the invariant across Core, CLI, teaching, and Mac. Commits
may be incremental, but do not release or close a partial state in which the CLI
shares while the Mac app still silently forks.

### Core and run truth

1. Make `SkillCatalog.get/list` merge same-ID overrides ahead of seeds, exactly
   once per ID.
2. Add Core-owned `SkillOrigin`, `hasOverride`, unified save, Restore, and
   Team-reference projection APIs. Keep explicit create/duplicate APIs.
3. Validate immutable built-in `id` / `lane` / `purpose`; keep atomic file
   writes and lab-retirement guards.
4. Snapshot effective Skill bodies at the `RunService` acceptance boundary.
5. Correct comments in `SkillCatalog.swift` and `TeamCatalog.swift` that still
   teach fork-on-edit.

### CLI and teaching

1. Register and implement `skills restore`; update `skills edit` for seed IDs.
2. Add the Core-owned JSON projections and generated schemas.
3. Register `SKILL_RESTORE_UNSUPPORTED`; keep exit-code ownership in
   `ContractRegistry`.
4. Update `teams_and_workers` to teach edit / shared effect / Restore / explicit
   Duplicate. Add related commands and the search aliases named in Founder
   Intake.
5. Delete the stale help claim that built-in Teams require duplication; Team
   same-ID edit/Restore already shipped.
6. No retired-vocabulary deny-list entry is appropriate for the generic word
   `PROMPT`. Protect this cutover with focused help and GUI tests instead.
7. Regenerate checked-in contract artifacts from `ContractRegistry`.

### Mac app

1. Delete `promptDraft`, `promptBaseSkillId`, `customSkillName`, save-time
   `resolveSkill`, and fork rollback from `TeamDraft`.
2. Make `TeamDraft.commit()` roster-only and preserve nil = Auto.
3. Put Skill save/create behind a small testable Worker-Done action; do not bury
   catalog semantics in SwiftUI-local state.
4. Implement the field order, honest labels, exact blast radius, Restore, and
   explicit new-Skill transaction above.
5. Update `TeamDraftTests`; delete every test whose desired result is a silent
   fork.

### Duplicate truth to delete

- Team-local prompt bodies in `TeamDraft.Row`.
- `"<Skill> for <Team>"` auto-fork naming.
- GUI copy that says an edit “will save as a custom skill.”
- CLI/help claims that a built-in Skill must be duplicated before edit.
- Phase prose that re-specifies already-shipped lab cleanup.

## Inference Bans

| Junction | Owner | Bad inference | Ban | Negative proof |
| --- | --- | --- | --- | --- |
| Skill file → effective catalog | `SkillCatalog` | A built-in ID always means compiled seed wins | Same-ID file is an override and wins effective lookup | Save override; `get/list/assemblePrompt` all return it once |
| Effective Skill → origin | `SkillCatalog` | `builtIn == false` means custom | Use derived `seed/override/custom` | Overridden seed remains picker-visible with Restore |
| Worker Done → Team draft | Worker-Done action + `TeamDraft` | Parent Cancel rolls back a committed shared Skill | Team Cancel owns roster draft only | Done edit, cancel Team, reopen another Team and see edit |
| Team Save → Skill catalog | `TeamDraft.commit()` | A changed body should be copied during Team Save | Team Save performs zero Skill writes | Compare Skill directory before/after roster-only save |
| Worker Model field → roster | `TeamWorkerSpec.preferredModelId` | nil means incomplete | nil means Auto and is a valid unchanged staffing choice | Edit only skill.md on an Auto row; Done succeeds and model stays nil |
| Accepted run → later catalog edit | `RunService` | A live run can reread today's Skill mid-flight or from history | Snapshot before first spawn; history reads snapshot | Block runner, edit Skill, release runner; accepted run keeps old sentinel |
| GUI picker → effective list | Core origin projection | Filter `builtIn == true` to find shipped identities | Seed and override are both built-in identities | Override does not vanish from an unrelated Team's picker |
| Restore → custom Skill | `SkillCatalog.restore` | Any Skill can restore | Only IDs with shipped seeds restore | Custom ID returns `SKILL_RESTORE_UNSUPPORTED` and remains intact |

## Proof

### Deterministic tests

Add focused coverage for:

- override precedence, one-entry merge, Restore idempotence, seed field
  validation, custom edit stability, and reference-name projection;
- one `bug_reproducer` override reaching Bug Hunt Min / Bug Hunt / Bug Hunt Max
  without any Team row ID changing;
- accepted-run prompt snapshot isolation;
- `skills edit` built-in round trip, `skills restore` twice, JSON origin fields,
  custom Restore refusal, registered exits, schemas, and contract examples;
- help search for `edit skill`, `shared skill`, and `restore skill`;
- roster-only `TeamDraft.commit`, Worker Done / Worker Cancel / Team Cancel, new
  Skill creation, Restore, Auto preservation, and picker visibility.

Focused commands:

```text
swift test --package-path Packages/AllnighterCore --filter SkillCatalog
swift test --package-path Packages/AllnighterCore --filter CatalogCLI
xcodebuild test -project Apps/AllnighterMac/AllnighterMac.xcodeproj \
  -scheme AllnighterMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

### CLI smoke (isolated catalog)

Use an `ALLNIGHTER_SUPPORT_DIR` created under `/tmp`; never mutate the user's
real catalog for proof.

```text
export ALLNIGHTER_SUPPORT_DIR="$(mktemp -d /tmp/alln-wss-s01-XXXXXX)"
printf 'WSS_SENTINEL: shared override.\\n' > "$ALLNIGHTER_SUPPORT_DIR/override.md"
Packages/AllnighterCore/.build/debug/alln skills edit bug_reproducer \
  --template-file "$ALLNIGHTER_SUPPORT_DIR/override.md" --json
Packages/AllnighterCore/.build/debug/alln skills show bug_reproducer --json
Packages/AllnighterCore/.build/debug/alln skills restore bug_reproducer --json
Packages/AllnighterCore/.build/debug/alln skills restore bug_reproducer --json
```

Assertions: first edit receipt is `origin=override`, show contains the sentinel,
first Restore says `restored=true`, second says `restored=false`, and both exit
0.

### Owner-visible Works Test

1. Open Settings → Teams → Bug Hunt Min → Bug Reproducer.
2. Confirm the impact line names Bug Hunt Min, Bug Hunt, and Bug Hunt Max.
3. Add a unique sentinel to skill.md and press Worker Done.
4. Cancel the parent Team editor.
5. Open Bug Hunt Max → Bug Reproducer; the sentinel is present and no new Skill
   exists.
6. Press Restore default; reopen Bug Hunt Min and confirm the shipped body is
   back.
7. Create a named Skill through **+**, press Worker Done, then cancel the Team.
   Confirm the Skill remains explicit user data and `alln skills gc --json`
   reports it as unreferenced.

No provider run or quota spend is required; Core tests prove all three Team IDs
assemble the effective shared body.

### GUI visual proof

This is Tier B visible GUI work. Render:

```text
bash scripts/gui_proof.sh studio-worker-editor
```

A separate layout-watcher must return P1 none, then seal the proof packet under
`docs/qa/gui/studio/`. The fixture must visibly cover Model → Skill → skill.md,
the exact impact line, Restore, and New Skill entry. Build success is not visual
proof.

### Green wall

```text
bash scripts/check.sh
```

## Done When

- Editing an existing Skill never mints or repoints to a new ID.
- Bug Hunt Min / Bug Hunt / Bug Hunt Max resolve one edited
  `bug_reproducer`, then all revert through Restore.
- Team Save performs no Skill writes.
- Worker Done and both Cancel boundaries behave exactly as specified.
- CLI commands, JSON, exits, generated artifacts, help search, and Mac behavior
  agree.
- No stale fork-on-save test, comment, help sentence, or GUI copy remains.
- Mac visual proof is sealed with layout-watcher P1 none.
- `docs/workflows/Product_Vocabulary.md` receives the keepable shared-identity /
  `skill.md` wording; code remains runtime truth.
- This packet is archived and `docs/phases/README.md` routes to the successor
  code/docs.

## Non-goals

- Cross-lane Skills.
- Skill marketplace, import/export, or physical `SKILL.md` directories.
- Skill version-history UI.
- A separate Skills settings/library page.
- Automatic orphan deletion.
- iOS presentation or protocol work.
- Reopening Team Lab or its cleanup.

## Open Questions

None.
