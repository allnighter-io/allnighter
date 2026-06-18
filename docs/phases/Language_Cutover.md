# Language Cutover

Status: **Cutover plan — top of list, blocks new product work**
Owner: AllnighterCore + CLI/MCP + Mac app + docs
Updated: 2026-06-18

## Why now, and the law

We locked the product model (below). The old vocabulary — `Fan out`, `Build` as a
craft, `Execute` as a composer mode, `lane` as a single run, `Workflow` as a user
noun, effort-as-team-depth — is spread across ~40 Swift files, the generated
contracts, fixtures, and the GUI. With **zero users**, we cut over **hard and
clean**:

```text
No aliases. No compatibility shims. No "old name still accepted." No dual paths.
We rename/migrate the real types and regenerate the contracts. One language,
everywhere: GUI, CLI, MCP, Core.
```

This is painful now and only harder later. It goes **before** the Project Spine
build (PRJ-S00) so that work is written in the final language, not re-cut after.

## Canonical Vocabulary (locked)

```text
HUMAN LAYER (product / GUI / docs)
  Chat       the surface. talk to your Project Manager. always there.
  Delegate   hand intent to a team.  UI label: "Send to team".   (was: Fan out)
  Execute    the green light that authorizes a make-real run.     (NOT a mode)
  Team       the actor noun. you delegate to teams.
  Crafts     Code · Design · Copy.        (Code was: Build)
  Signal     the repo-aware scout that senses outside → insights. (not "move cards")

MACHINE LAYER (CLI / MCP / Core)
  one primitive: run a team   (a solo agent is a team of one)
  a team carries:  craft (code|design|copy|signal) · posture (propose|review|execute|scout) · mutating:bool
  approval gates mutating runs   ← this IS the human "Execute"; not a separate verb
  implement = what worker agents do inside a run (internal word; never user-facing)

RESERVED
  Workflow   = a loop (repeated team runs). LATER, externally owned (Hermes/OpenClaw via MCP).
               Not user-facing now. (An internal plumbing type may keep the name; see Keep-Internal.)
```

`lane` means **craft (Code/Design/Copy)** and nothing else. It is never "a single
run."

## Rename / Retire table (hard, no alias)

| Old | New | Layer |
| --- | --- | --- |
| `Fan out` / "fanout" (product action) | **Send to team** (label) / **Delegate** (model word) | human |
| `Fanout*` types, `FanoutAttachmentMapper`, fanout vars | team-run naming (`TeamRun*` / `TeamAttachmentMapper`) | code |
| `Build` (craft/lane/tab/setup-section) | **Code** | human + code |
| `WorkLane.build` (rawValue `"build"`) | `WorkLane.code` (rawValue `"code"`) | code + data |
| `defaultBuildTeamId` | `defaultCodeTeamId` | code + data |
| `WorkOrder.lane: build` | `lane: code` | code + data |
| `Execute` as a composer route/mode | removed; Execute = the approval action | human |
| `Implement` as a user-facing word | not user-facing (workers implement, internal) | human |
| `Move Card` | **Insight** (Signal output) | docs |
| `Proof` as a lane/family | deleted (never existed; was a stray invention) | docs |
| effort = "more workers + deeper pass" | **see Open Decision** below | human + code |
| `team_deploy*` / `Fanout` run entrypoints | one primitive: `team.run` (`run`), posture+mutating as metadata | mcp/cli |

Keep (do not touch):
- `Team`, `Skill`, `Project`, `Pending`, `Chat`, `Signal`, `Scout`, `Code/Design/Copy`.
- Vendor product names (e.g. a CLI literally named "Grok Build CLI" — verify before
  renaming; do not rename a vendor's product, only our craft labels).

## Effort — DECIDED (2026-06-18)

**Effort = the model's reasoning level. Full stop.** `low | med | high` is the
per-worker **model reasoning setting** (routed Claude `--effort` / Codex
`-c model_reasoning_effort` / Antigravity model-name variant / Grok none — already
wired). It is the only definition that is simple and honest.

**Depth is not effort.** If you want a deeper/bigger pass, that is a different
**Team** (more workers) — a named variant (Bug Hunt Lite / Bug Hunt / Exterminator),
never an effort dial. So in CUT-S05:

- `EffortLevel` stays, meaning model reasoning only.
- Remove the worker-activation gating: `minEffort`, `effortPolicy`,
  `outputCountByEffort`, `synthesisPolicyByEffort`, and any "effort picks how many
  workers" path. Teams have a fixed lineup; size differences are separate teams.
- Fix the GUI tooltip to "the reasoning level the model uses," never "more workers."

This is more work and that is fine — it is the only model that makes sense.

## Surface inventory (where the old words live)

Code (Swift) — anchor files, full lists via `grep`:
- **Fanout (~34 files):** `FanoutAttachmentMapper.swift`, `TeamRunCoordinator`,
  `CatalogRunCoordinator`, `TeamService`, `StageEngine`, `TeamCatalog`, `TeamRun`,
  `ContractRegistry+Milestone1`, `DriverManifest`, `SkillCatalog`, `TeamResolver`,
  `TeamRequestResolver`, `TeamTool`, `BuiltInTeams`, `StageOutput`, `NDJSONStreamProjector`;
  GUI: `RoutingComposer` (the "Fan out" control), `HomeView`, `AppModel`,
  `ThreadsViewModel`, `RootView`, `ThreadView`, `GUIFixture`.
- **WorkLane/`build` (~30 files):** `TeamCatalog`, `BuiltInTeams`, `TeamResolver`,
  `TeamRequestResolver`, `SkillCatalog`, `TeamRun`, `ThreadTurn`, `TeamTool`,
  `CatalogPersistence`, `AsyncTeamContracts`, `ContractRegistry+Milestone1`,
  `AgentBootstrap`, `MCPServer`, `AllnighterCLI`, `TeamService` + tests; GUI tabs +
  setup rail (`BUILD/DESIGN/COPY`).
- **Effort (~30 files, gated on Open Decision):** `EffortLevel`/`minEffort`/
  `defaultEffort`/`effortPolicy` in `TeamCatalog`, `TeamResolver`, `BuiltInTeams`,
  `Model`, `ModelCatalog(Types)`, `DriverManifest`, `WorkerRunner`,
  `CatalogRunCoordinator`, `TeamRun`, CLI + MCP + GUI (`TeamStudioView`,
  `TeamEditorView`, `ThreadsViewModel`).
- **Keep-internal:** `Workflow.swift` / `PanelPreset.swift` are MVP plumbing — see
  Keep-Internal. Verify they never surface as user nouns.

Generated / data:
- `docs/generated/alln/alln-contract.json`, `help_alln_cli_spec.md` — **regenerate**
  after the Core renames (never hand-edit; they come from the contract registry).
- Fixtures and persisted catalogs that encode `lane: "build"` / fanout shapes —
  migrate to new rawValues; with zero users, no back-compat reader.

Docs:
- **Rename + rewrite:** `Team_Catalog.md` (→ team catalog; drop "fanout"
  framing), and every active phase doc that says `Fan out` / `Build` lane / Execute
  mode in product copy (`CLI_Product_Spine`, `Work_Order_Team_Model`,
  `Team_And_Skill_Catalogs`, `Project_Spine_And_Project_Manager`, copy/*, wiring/*).
- **Strategy:** `Allnighter_Deploy_Teams_Wedge` (Deploy → Delegate/Send-to-team),
  `Allnighter_Public_Signal_Wedge` (Move Card → Insight).
- **Leave as historical:** `docs/mvp/*`, `docs/archive/*`, `docs/qa/*` (snapshots of
  past state; do not rewrite history — only active forward docs).

## Cutover slices (ordered, green-wall after each)

- [x] **CUT-S00 — Vocabulary SSOT.** This doc is the canonical word list; pointers
  added in `AGENTS.md` and `docs/phases/README.md` (done 2026-06-18).
- [x] **CUT-S01 — Core craft rename (DONE 2026-06-18).** `WorkLane.build → .code`
  (rawValue); built-in team ids `build_* → code_*`; custom-id + lane block-reason
  derive `code`; CLI usage strings `code|design|copy`; `team_run` fixture; Mac enums
  `ComposeLane`/`RailFilter` `.build → .code`. Regenerated `docs/generated/alln/*`.
  `TurnFamily.build` (execution-turn family) intentionally left for the Execute work.
  Full green wall passes (Core tests + Mac build/test); GUI gate satisfied with a
  non-visible waiver (labels still render "Build"; visible relabel is CUT-S04).
- [x] **CUT-S02 — Core run rename (DONE 2026-06-18).** `FanoutAttachmentMapper` →
  `TeamRunAttachmentMapper` (+ file, `fanoutSeatPrompt` → `teamRunSeatPrompt`);
  `TeamRunCoordinator.fanOut` → `runTeam`. Core tests green. (Deeper
  one-`team.run`-primitive consolidation is separate MCP Solidity work.)
- [x] **CUT-S03 — CLI + MCP surface language (DONE 2026-06-18).** Scrubbed
  user-facing `Fan out`/`fanout` from CLI/MCP surface: tool `whenToUse`, the
  `--team` flag summary ("public team selector"), and the lane-required error
  ("Sending to a team requires a lane…"); renamed the internal
  `TeamRunCoordinator.fanOut` → `runTeam`; regenerated `docs/generated/alln/*`;
  Core tests green. (The architectural one-`team.run`-primitive + posture/`mutating`
  + approval gate + MCP⊆CLI parity test is the separate MCP Solidity Plan M-A..M-D,
  not the language cutover. Internal comment refs to the doc filename are swept in
  CUT-S06 with the doc rename.)
- [~] **CUT-S04 — GUI labels (code DONE 2026-06-18; render-proof pending).** Composer
  lane label Build→Code; `ComposeMode.fanout` → `.sendToTeam` ("Send to team"); effort
  tooltip → "more reasoning time"; ReadinessView "Code · Design · Copy"; work-order
  filter labels derive "Code" from rawValue. Execute route KEPT (the make-real mode,
  per the locked model). Mac build + tests green. **Remaining:** GUI render-proof seal
  for the changed surfaces (HomeView, RoutingComposer, ReadinessView, TeamEditorView,
  TeamStudioView) to clear the visual-proof gate.
- [x] **CUT-S05 — Effort = reasoning level (DONE 2026-06-18).** Ripped out
  `minEffort`, `TeamEffortPolicy`, `effortPolicy`, `outputCountByEffort`,
  `activeRows`, `workerCountByEffort` — all effort→worker-count gating. `EffortLevel`
  stays as the per-worker model reasoning level only; teams have a fixed lineup
  (built-in teams unchanged in membership, just no longer effort-gated). CLI/MCP team
  output shows a fixed `workerCount` (was per-effort); regenerated contracts. Core +
  Mac build/test green. Obsolete effort tests deleted. (GUI tooltip "more workers + a
  deeper pass" and the TeamEditor/TeamStudio render proof are folded into CUT-S04.)
- [x] **CUT-S06 — Docs sweep (DONE 2026-06-18).** Renamed `Fanout_Team_Catalog.md`
  → `Team_Catalog.md` and updated all refs (Swift comments + active docs); Move Card →
  Insight in the strategy wedges; README index vocab (Send to team, Code/Design/Copy);
  no "Proof lane" exists. The `Team_Catalog.md` body still carries some legacy Fan-out/
  effort-tier prose superseded by this doc + the code; mvp/archive/qa left as historical.

## Keep-Internal (not part of the cutover)

- `Workflow.swift` / `PanelPreset.swift` and similar MVP plumbing may keep their
  names **as long as they never surface as a user-facing noun**. "Workflow" is
  reserved for the future *loop* concept; internal plumbing using the word is fine.
- "implement" as a verb inside worker/run code is fine; it is the workers' action.

## Done When

- No active product surface (GUI label, CLI command/help, MCP tool, Core public
  type, forward doc) uses `Fan out`, `Build`-as-craft, `Execute`-as-mode,
  `Move Card`, `Proof`-as-lane, or `lane`=single-run. `rg` proves it.
- `WorkLane` is `code | design | copy`; generated contracts + fixtures regenerated.
- One run primitive (`team.run`) with posture + `mutating`; approval gates mutating;
  no `team_deploy`/`fanout` parallel entrypoints remain.
- The effort Open Decision is resolved and applied; the GUI tooltip matches it.
- The green wall passes after every slice; zero aliases or back-compat shims exist.
