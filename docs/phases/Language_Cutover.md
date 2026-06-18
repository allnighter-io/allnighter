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

## Open Decision (must resolve before the effort slice)

**Effort is the one thing not yet locked.** The built GUI tooltip says *"Higher
effort = more workers + a deeper pass"* — that is **team depth**, which contradicts
the rule that effort = the per-worker **model reasoning level** and depth = **named
team variants**. Pick one before touching `EffortLevel`/`minEffort`:

- **(A) Effort = model reasoning level (recommended, matches the locked model).**
  `EffortLevel` becomes the per-worker model reasoning setting only (routed Claude
  `--effort` / Codex `-c model_reasoning_effort` / Antigravity variant / Grok none).
  Worker-count/depth differences move to **named team variants** (Bug Hunt Lite /
  Bug Hunt / Exterminator). Requires migrating `minEffort`-gates-activation out.
- **(B) Keep effort = depth** (more workers + deeper pass) and drop the
  "model reasoning level" framing. Simpler migration, but contradicts the locked
  two-axis model and the founder's earlier statement.

Everything else in this doc is locked and can proceed without this decision; the
effort slice (CUT-S05) is gated on it.

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
- **Rename + rewrite:** `Fanout_Team_Catalog.md` (→ team catalog; drop "fanout"
  framing), and every active phase doc that says `Fan out` / `Build` lane / Execute
  mode in product copy (`CLI_Product_Spine`, `Work_Order_Team_Model`,
  `Team_And_Skill_Catalogs`, `Project_Spine_And_Project_Manager`, copy/*, wiring/*).
- **Strategy:** `Allnighter_Deploy_Teams_Wedge` (Deploy → Delegate/Send-to-team),
  `Allnighter_Public_Signal_Wedge` (Move Card → Insight).
- **Leave as historical:** `docs/mvp/*`, `docs/archive/*`, `docs/qa/*` (snapshots of
  past state; do not rewrite history — only active forward docs).

## Cutover slices (ordered, green-wall after each)

- [ ] **CUT-S00 — Vocabulary SSOT.** This doc is the canonical word list. Add a
  one-line pointer from `AGENTS.md` and `docs/phases/README.md` so all agents use it.
- [ ] **CUT-S01 — Core craft rename.** `WorkLane.build → .code` (rawValue),
  `defaultBuildTeamId → defaultCodeTeamId`, `WorkOrder.lane` values, built-in team
  lane tags. Migrate fixtures; regenerate contracts. Green wall.
- [ ] **CUT-S02 — Core run rename.** `Fanout*` → team-run naming; collapse run
  entrypoints toward the single `run a team` primitive (posture + `mutating`
  metadata). Internal only; no behavior change. Green wall.
- [ ] **CUT-S03 — CLI + MCP surface.** Retire `Fan out`/deploy phrasing; one
  `team.run` shape with `mutating`/approval; regenerate `docs/generated/alln/*`.
  Parity test (MCP ⊆ CLI). Green wall.
- [ ] **CUT-S04 — GUI labels.** Composer "Fan out" → "Send to team"; remove the
  Execute route (Execute becomes the approval on a make-real card); `Build` tab +
  setup rail → `Code`; work-order filter `Build/Running` → `Code/Running`. Layout
  proof gate.
- [ ] **CUT-S05 — Effort reconciliation (gated on Open Decision).** Apply (A) or (B);
  fix the GUI tooltip; migrate `EffortLevel`/`minEffort` accordingly. Green wall.
- [ ] **CUT-S06 — Docs sweep.** Rewrite active forward docs to the canonical
  vocabulary; rename `Fanout_Team_Catalog.md`; Move Card → Insight; delete any
  "Proof lane". Leave mvp/archive/qa as historical. `rg` confirms no old term
  remains in active product surfaces.

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
