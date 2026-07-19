# CLI Agent Surface Fidelity — stop teaching a CLI we no longer ship

Status: **Active — APPROVED (founder dogfood 2026-07-20). Hardened same day after
full-surface audit: ASF-S00 inventory DONE (kill list below), scope expanded —
the drift is in the transactional JSON, not just help prose.**
Owner: AllnighterCore (`HelpTopicRegistry`, `HelpService`, `HelpContract`,
`ContractRegistry`, `AgentBootstrap`, `AsyncTeamService`) + AllnighterCLI
(`HelpCLI`, `version`) + living ops docs agents still open
Updated: 2026-07-20 (hard review pass)

Related: archived `Agent_Front_Door.md` / `Agent_Onboarding.md` /
`Agent_Intent_Router.md` (gates 1–3 shipped — **not** the gap) · living
`CLI_Product_Spine.md` + `CLI_Implementation_Contract.md` ·
`docs/operations/GLM_Worker_Best_Practices.md` ·
`docs/workflows/SSOT_Feature_Workflow.md` §Teaching Surface Rule (added
2026-07-20, the process fix) · `SSOT_Founder_Input_Workflow.md` §Agent-facing help

## The gap (named precisely — three drift classes, not one)

We keep shipping **power** (`hello --for`, preflight, JSON `nextActions`,
contract hash, Teach your CLIs) and then agents still invent MCP flags, miss
OpenCode/GLM in help search, and paste dead `pair slice` recipes.

The 2026-07-20 audit found **three distinct classes** of agent-facing drift.
The original packet named only the first:

1. **Help corpus prose** — `HelpTopicRegistry` bodies still teach MCP tool-call
   grammar (`team_start(dryRun:true)`, `pair_relay(action:resume)`, `run_get`).
   8 of 17 topics are dirty; 10 `relatedToolIds` resolve to **no command at all**.
2. **Transactional JSON grammar (worse — missed by the original packet).** The
   *action* surfaces agents actually poll emit MCP tool ids live today:
   `alln team preflight` returns `nextAction.tool: "team_start"`;
   `alln team start --json` returns `nextActions[].tool: "team_status"/"team_result"`;
   `alln team status --json` the same; help envelopes emit
   `nextToolPlan[].tool: "help_get"/"help_search"`; and plain-text
   `alln help search` prints `next: help_get …`, `alln help get` prints
   `tools: team_run, team_ask, run_get`. An agent that obeys these literally
   types `alln team_start` and gets `CLI_USAGE_ERROR`. This is the product
   telling the agent to fail, mid-transaction.
3. **Living docs** — active playbooks/spec docs teach deleted verbs
   (`pair slice`/`pair status` procedures, `alln mcp serve` examples presented
   as live) and carry broken archive links.

That is not a missing feature. It is **agent-facing surface drift**: the whole
teaching-and-guidance surface still speaks a retired product while the command
surface speaks the current one. Agents trust `alln help *`, envelope
`nextActions`, and checked-in playbooks more than phase archives. When those
lie, agents do not adopt Allnighter — they reinvent `opencode run --attach …`
and burn cycles.

> Front door V1 made Allnighter findable and routable. This phase makes the
> **entire guidance surface honest** — prose AND structured — so adoption does
> not die one stale paragraph (or one stale JSON field) later.

### Founder dogfood packet (2026-07-20) — what landed as feedback

No separate raw transcript exists (audited `docs/debuglog/`, DEBUGLOG, git log
2026-07-14→20); **this section is the capture of record.**

Loved (do not regress): agent-first JSON + `nextActions`; `team hello --for`;
preflight-before-spend; `contractHash` / generated docs / `doctor explain`;
hello → preflight → start/status/result lifecycle.

Adoption blockers (this phase owns them):

1. **Discovery holes** — `help search "opencode"` / `"glm"` returns nothing useful.
2. **Stale MCP vocabulary in live help** — `team_run_loop` still teaches MCP tools
   and `team_start` with `dryRun:true`; CLI has no `--dry-run` (preflight is the
   verb). Agents invent flags that do not exist.
3. **Bootstrap / first paste confusion** — feedback claimed panel/pilot-first paste;
   **ONB-S01 already rewrote bootstrap** (verified clean in `Bootstrap.swift` /
   `TeachingSnippet.swift`: router reflex only). Residual risk: old installed
   snippets (staleness IS mechanized — version+hash markers, Mac repair path)
   and orphaned `panelWorkflowLines`/`pilotWorkflowLines` (0 callers) beside the
   live SSOT.
4. **No obvious self-build** — agents must know `Packages/AllnighterCore` +
   `swift build -c release --product alln`. (Audit found `~/.local/bin/alln` is
   a **symlink to the workspace release build** via `alln install-cli`, so the
   whole story is `swift build -c release --product alln` + `alln install-cli`
   — it just isn't taught anywhere.)
5. **Version freshness** — `binaryVersion` stuck at `0.1.0`. **Landed for real
   2026-07-20** (commit `25ab39c2` — the bump had been sitting *uncommitted and
   unbuilt* while this doc claimed it shipped; see meta-lesson below). Rebuilt +
   verified `0.9.0` on installed binary. ASF-S06 still adds git SHA / build id.
6. **Too many send verbs** — `run` / `team` / `team start` / `thread send` without a
   first-contact decision tree (`tool_selection` exists and is CLI-honest but
   covers none of `run` / `thread send`).
7. **Living docs that teach dead commands** — e.g. GLM playbook still leads with
   deleted `pair slice` (disclaimer exists; agents still pattern-match the verbs;
   no live replacement path appears anywhere in its 253 lines).
8. **Empty search silence** — miss → empty `results` + empty `nextToolPlan`.
   Audit refinement: the miss behavior is also **inverted** — a nonsense query
   fuzzy-hits `current_setup` with a populated plan, while real product words
   (`opencode`, `glm`) return total silence.

### Why this kept happening (root cause, found 2026-07-20 — worse than "no gate")

The gate was not missing. **It was inverted to defend the drift.**

When MCP was retired, the tool catalog was deleted from `ContractRegistry` —
and `HelpTopicRegistryTests.swift:11-19` **froze a hardcoded copy of the dead
MCP vocabulary** ("frozen here in the interim…") so cross-link validation would
keep passing. The promised "MCP_Retirement.md docs/help-content sweep" never
ran. Worse, `testEveryAdvertisedMCPToolIsReachableFromATopic`
(`HelpTopicRegistryTests.swift:44-48`) **requires** every dead tool id to be
taught by some topic — deleting the stale grammar would have FAILED the suite.

Compounding facts:

- `testEveryTopicReferenceResolvesToTheRegistry` validates only the typed
  `related*` arrays — literal `alln …` strings in `bodyMarkdown`/`sections`
  prose are never checked, though `ContractRegistry.resolveCommandName`
  (`ContractRegistry.swift:54-62`) + `CommandSpec.flags` exist to check them.
- The retired-vocabulary gate is a hardcoded 4-word list
  (`HelpTopicRegistryTests.swift:76`) that nobody extends at retirement time.
- There is **no CI** (no `.github/workflows`); `scripts/check.sh` runs
  `swift test` but never `alln dev export-contracts --check` — contract drift
  is only caught opportunistically by `StandingInvariants` during team runs.
- `binaryVersion` is a hand-edited literal with no build identity; and the
  **meta-lesson**: this very doc claimed the `0.9.0` bump "landed + verified"
  while it sat uncommitted in a working tree and both binaries reported
  `0.1.0`. A fidelity doc drifting from reality is the same disease.
  → codified in `SSOT_Feature_Workflow.md`: "shipped/verified" claims require
  committed + built state.

Process fix (landed 2026-07-20): `SSOT_Feature_Workflow.md` now carries the
**Teaching Surface Rule** + **Retirement Rule** — teaching surfaces are a
default lie-prone layer in every packet; retirement is not done until surfaces
are swept AND the dead grammar joins the test-enforced deny-list.

### Verified live (2026-07-20 audit, installed binary — post version-bump)

| Probe | Result |
| --- | --- |
| `alln bootstrap --host claude` | **Honest** — router reflex + auth law (ONB-S01), marker + content hash present. |
| `alln help search "opencode" --json` / `"glm"` | **Empty** results + empty `nextToolPlan`. `alln models --json` knows both. |
| `alln help search "asdfqwerty…" --json` | **Fuzzy-hits `current_setup`** with populated plan — miss behavior inverted vs real terms. |
| `alln help get team_run_loop --format md` | **Lies** — `team_start(dryRun:true)`, `team_run`/`team_ask`/`run_get`; prints `tools: team_start, …, run_get`. |
| `alln help search <anything>` (text) | Prints `next: help_get topic=… detail=machine` — not a runnable command. |
| `alln team preflight --team code_bug_hunt` | `nextAction: {kind: "startTeamRun", tool: "team_start"}` — literal `alln team_start` errors. |
| `alln team start … --json` | `nextActions[].tool: "team_status"/"team_result"` — underscore, not runnable. |
| `alln version --json` | `binaryVersion: "0.9.0"` **(fixed + committed + rebuilt 2026-07-20)**; no git SHA / build id yet. |
| `alln team result` / `spec` / `show` / `history` / `run get` / `team preflight` | All resolve — `tool_selection` topic verbs are clean. |

**Pattern-of-record (already correct, generalize it):** `AgentSurfaceNextAction`
(`AgentFrontDoor.swift:5-17`) carries a full literal
`command: "alln doctor --json"` string; used by `alln models` / `alln teams` /
intent router / `team hello` (`AgentHello.build` discards the stale
`verdict.nextAction` and emits a clean `nextCommandPlan.command`). Every other
next-action shape migrates to this.

## ASF-S00 kill list (inventory DONE 2026-07-20 — this is the SSOT)

**`HelpTopicRegistry.swift`** (`Packages/AllnighterCore/Sources/AllnighterCore/`):
- `team_run_loop` L123–141: body + sections teach `team_start(dryRun:true)`,
  `team_result`, `team_cancel`, `team_run`/`team_ask`, `run_get`;
  `relatedToolIds` carries 6 MCP ids, 3 dead.
- `pm_relay` L157, L182: `pair_relay(action:resume)` call syntax; L186 dead
  `project_get`, `run_get`.
- Bodies also dirty: `pending` (L279–291, `pending_run` prose), `projects_and_threads`
  (L299–308), `results_and_history` (L355–362, `run_get` prose), `schemas` (L416–423),
  `auto_fix` (L409).
- **10 outright-dead `relatedToolIds`** (resolve to nothing): `team_run`,
  `team_ask`, `run_get`, `pending_update`, `project_get`, `stalled_update`,
  `teams_get`, `skills_get`, `defaults_get`, `error_explain`. (`pending_update`
  and `stalled_update` never existed even under MCP — authoring bugs.) All
  remaining ids are underscore spellings of two-word CLI verbs (invented-flag
  traps).

**`HelpContract.swift`**: L21–31 orphaned `panelWorkflowLines` /
`pilotWorkflowLines` (0 callers — delete); L125, L163, L167, L175, L180
`tool: "help_get"/"help_search"/"team_hello"` in `nextToolPlan` steps.

**`HelpCLI.swift`** (AllnighterCLI): L34–35 prints `next: <tool_id>`; L61 prints
`tools: <relatedToolIds>` verbatim.

**Transactional surfaces**: `AllnighterCLI.swift:1120` (preflight retryLater →
`tool: "team_start"`); `AgentBootstrap.swift:199` (preflight nextAction), `:63`
(dead — hello discards it); `AsyncTeamService.swift:1065-1066` (team start
nextActions); `AsyncTeamStatusMapper.swift:63,65` (team status nextActions).

**Frozen dead vocabulary**: `HelpTopicRegistryTests.swift:11-19` (the inverted
gate) + `:44-48` (`testEveryAdvertisedMCPToolIsReachableFromATopic`).

**Living docs**:
- `docs/operations/GLM_Worker_Best_Practices.md` — 3× broken link
  `../phases/PM_Relay.md` (moved to `docs/archive/phases/`); L96 instructional
  dead `pair status` inside the default-posture procedure; L104 copy-pasteable
  dead `scripts/run_cr_phase1.sh` block; **no live replacement path**
  (`alln run --worker model_opencode_glm_5_2 …`) anywhere.
- `docs/phases/CLI_Product_Spine.md` L214, L215, L550 — `alln mcp serve --stdio` /
  `alln mcp install` presented as live; no `mcp` subcommand exists.
- `docs/phases/CLI_Implementation_Contract.md` L69, L72, L881–884, L907–911 —
  MCP async-tool contract presented as planned; moot since retirement,
  unannotated.
- `docs/mvp/RB6_Team_As_Tool.md` — MCP-first spec, historical only via
  AGENTS.md routing; no in-file tombstone.
- Cleanup debt (not teaching): `StalledWorkDetector.swift:234` vestigial
  `pair slice` prompt match.

## Insight

The product spine is already something agents will love. The adoption blockers
are **guidance fidelity** — prose AND structured — not missing power.

Laws for this phase:

1. **Help is product.** `HelpTopicRegistry` + search hits are agent UX. A topic
   that teaches a flag that does not resolve in `ContractRegistry` is a P0 bug.
2. **Every next action is a runnable command.** Any `nextAction` /
   `nextActions` / `nextToolPlan` step, JSON or text, carries a literal
   `alln …` string that resolves in `ContractRegistry`
   (`AgentSurfaceNextAction` pattern). Underscore tool ids never appear in
   agent-visible output.
3. **No MCP grammar on the live agent surface.** Live help, bootstrap,
   `--help`, doctor recovery text, envelope guidance, and living ops docs speak
   **CLI verbs only**. Historical archives are exempt but must be tombstoned
   and correctly linked.
4. **No empty silence on help miss.** Empty search returns concrete recovery
   (`models --json`, `teams --json`, `doctor --json`, `team hello --for` — as
   runnable commands) — same law as the front door.
5. **Gates derive from live registries, never frozen copies.** A test that
   validates against a hand-frozen vocabulary of a retired product is worse
   than no test. Deny-lists (what must NOT appear) and allow-sources (what may
   be taught = `ContractRegistry`) both live in ONE place each.
6. **Freshness is observable.** Agents prove they are on the binary they just
   built without archaeology; docs may claim "shipped" only for committed +
   built state.

## Anti-goals

- Do not invent a second product surface (no MCP revival; no parallel JSON).
- Do not replace `hello --for` / preflight / start with a new mega-command —
  teach the decision tree in help first; unified `send` stays PARKED.
- Do not rewrite archived phase history; fix **live** surfaces + living docs
  (tombstones/links on archives are allowed and required where broken).
- Do not keep compat `tool` ids next to the new `command` strings "just in
  case" — foundation-first, one grammar (`kind` stays; `tool` dies).
- Do not broaden into Team Lab / Field Reports scope.
- Do not claim adoption fixed without the reproducible Works Test below green
  on a binary built from committed HEAD.

## Truth owner / lie-prone layers

| Layer | Role |
| --- | --- |
| **Truth owner** | `ContractRegistry` (what exists) · `HelpTopicRegistry`/`HelpService` (what is taught) · `AgentSurfaceNextAction.command` (what to do next) · one `RetiredVocabulary` deny-list (what may never be taught again) · `version` JSON (identity) |
| **Lie-prone** | Topic prose + `relatedToolIds`; `nextAction`/`nextToolPlan` `tool` fields; `HelpCLI` text projections; living ops/spec docs; frozen test vocabularies; hand-edited version literals; stale installed snippets |
| **Proof** | Golden transcripts of the dogfood probes; prose-command resolution test; deny-list test + active-docs grep gate in `check.sh`; `export-contracts --check` in `check.sh`; version probe on fresh build |

## Slices

| Slice | Deliverable |
| --- | --- |
| **ASF-S00 ✅ DONE (2026-07-20)** | Inventory + kill list — see §ASF-S00 above (file:line, contract-resolution table, root cause). No separate debuglog file; this doc is the SSOT. |
| **ASF-S01** | **Help corpus CLI cutover + honest gate.** Rewrite all dirty topic bodies/sections (`team_run_loop`, `pm_relay`, `pending`, `projects_and_threads`, `results_and_history`, `schemas`, `auto_fix`) to CLI verbs. Retire `relatedToolIds` in favor of `relatedCommandNames` (or map ids → command names); `HelpCLI.swift:61` prints commands. **Delete the frozen vocabulary + `testEveryAdvertisedMCPToolIsReachableFromATopic`; re-point reference tests at `ContractRegistry`.** Delete `panelWorkflowLines`/`pilotWorkflowLines`. Golden: `help get team_run_loop` never contains `dryRun`/`MCP`/`team_start(`/underscore tool ids; does contain `alln team preflight` + `alln team start`. |
| **ASF-S02** | **Next-action grammar cutover (P0 — transactional surfaces).** Migrate `AgentNextAction` / `AsyncTeamNextAction` / `HelpNextToolStep` to the `AgentSurfaceNextAction` full-`command` pattern. Call sites: `AllnighterCLI.swift:1120`, `AgentBootstrap.swift:199` (delete dead `:63`), `AsyncTeamService.swift:1065-1066`, `AsyncTeamStatusMapper.swift:63,65`, `HelpContract.swift:125,163,167,175,180`, `HelpCLI.swift:34-35`. `kind` stays; `tool` field dies (foundation-first, no dual grammar). Golden: preflight/start/status JSON contains runnable `alln team start`/`status`/`result` strings; no `"tool"` key. |
| **ASF-S03** | **Discovery: catalog→search bridge.** Derive a search index from `ModelCatalog.builtIns` (id, displayName, modelLabel, driverId) + `TeamCatalog` families + driver ids — programmatic, not hand aliases (`aliasRedirects` is the hook point, fed from the catalogs). `help search "opencode"`/`"glm"` return useful hits + runnable next steps (`models --json`, `run --worker model_opencode_glm_5_2 …`). |
| **ASF-S04** | **Empty-search recovery + miss-consistency.** `planForSearch` (`HelpContract.swift:161-171`) returns non-empty recovery on zero hits (models/teams/doctor/hello --for as runnable commands). Fix the inversion: nonsense and real-term misses behave identically. Golden: miss ⇒ `nextToolPlan`/recovery non-empty, always. |
| **ASF-S05** | **First-contact decision tree.** Expand `tool_selection` (already CLI-honest) to the full verb tree: `run` vs `team` vs `team start` vs `thread send` vs `pending` — one page, routed from bootstrap + hello. No new CLI verb. |
| **ASF-S06** | **Freshness identity.** `0.9.0` ✅ landed (commit `25ab39c2`, rebuilt, installed symlink verified). Remaining: git SHA + build timestamp in `version --json` via a generated `BuildInfo.swift` (net-new: prebuild step in `dev.sh`/`check.sh` or SwiftPM plugin — nothing exists to extend); teach self-build in help (`swift build -c release --product alln` + `alln install-cli`; note install-cli symlinks the workspace release build). Thin `alln self-build` stays PARKED. |
| **ASF-S07** | **Living docs purge.** GLM playbook: current `alln run --worker model_opencode_glm_5_2` path first, fix 3× `PM_Relay.md` links → `docs/archive/phases/`, rewrite L96 dead-verb procedure step, fence L104 as historical-non-runnable. `CLI_Product_Spine.md` + `CLI_Implementation_Contract.md`: annotate/remove `alln mcp *` examples and moot MCP contract sections. In-file tombstone on `RB6_Team_As_Tool.md`. Optional: drop `StalledWorkDetector.swift:234` vestigial match. |
| **ASF-S08** | **Durable mechanical gates (the "never again" slice).** (a) **Prose-command resolution test**: every `` `alln …` `` string in topic bodies/sections/summaries resolves via `ContractRegistry.resolveCommandName` + flag check against `CommandSpec.flags`. (b) **`RetiredVocabulary` deny-list as ONE Swift source** consumed by the XCTest gate AND a `check.sh` grep gate over active agent-facing docs (`docs/operations/**` + docs this phase names); seeded from the kill list (`dryRun`, `team_start(`, `pair_relay(action`, all 10 dead ids, `pair slice`, `alln mcp`); Retirement Rule (SSOT Feature Workflow) appends here forever. (c) **Underscore-tool-id ban** on all agent-visible output (JSON keys + text projections) as golden transcripts of the dogfood probes. (d) Wire `alln dev export-contracts --check` into `scripts/check.sh` (today it is only opportunistic via `StandingInvariants`). Gates (a)–(c) land WITH S01/S02, not after — this slice is the checklist that proves they exist and that `check.sh` fails on reintroduction. |
| **PARKED** | Unified `alln send --mode …` sugar · auto-rewrite of installed snippets beyond current marker stale/repair (mechanism exists: version+hash markers + Mac `GlobalTeachingInstaller` repair) · full comment archaeology · CI runner (no `.github/workflows` exists; `check.sh` is the gate of record — founder call whether hosted CI is wanted) |

## Works test

Reproducible harness on a binary built from **committed HEAD** (not anecdote,
not a working-tree build):

```bash
swift build -c release --package-path Packages/AllnighterCore --product alln
B=Packages/AllnighterCore/.build/release/alln

$B help search "opencode" --json   # ≥1 result; next steps are runnable alln commands
$B help search "glm" --json        # ≥1 result; points at models / run --worker
$B help search "asdfqwerty-no-such-topic-999" --json
                                   # recovery non-empty; same shape as any miss
$B help get team_run_loop --format md \
  | grep -E 'dryRun|team_start\(|team_run|team_ask|run_get' && echo FAIL || echo OK
$B help get team_run_loop --format md | grep -q 'alln team preflight' && echo OK
$B team preflight --team code_bug_hunt --json      # nextAction carries "alln team …" command; no "tool" key
$B team start … --json                             # nextActions carry runnable commands (cancel the run)
$B version --json                                  # 0.9.0+ AND git SHA / build id (after S06)
scripts/check.sh                                   # includes export-contracts --check + deny-list doc grep (after S08)
```

Plus the XCTest gates from ASF-S08: prose-command resolution, deny-list,
underscore-ban goldens — all failing CI (`check.sh`) on reintroduction.

**Already green (do not "fix" again):** bootstrap teaching block (ONB-S01
router reflex, verified in source AND live); `tool_selection` verb honesty;
snippet staleness markers + Mac repair path; `binaryVersion` 0.9.0. If an agent
still pastes panel/pilot, that is install freshness — re-run Teach your CLIs.

## Done when

- ASF-S00 ✅ · S01–S08 checked or explicitly waived with founder note.
- Works test green on a fresh release binary built from committed HEAD.
- No agent-visible surface (help prose, JSON `nextActions`, text projections)
  teaches a verb/flag `ContractRegistry` cannot resolve; no underscore tool ids
  anywhere agent-visible.
- `check.sh` fails if retired grammar is reintroduced in `HelpTopicRegistry`
  OR the named active docs (deny-list gate), or if generated contracts drift.
- Founder dogfood items: 1 → S03 · 2 → S01+S08 · 3 → ✅ (+S01 orphan delete) ·
  4+5 → S06 (0.9.0 ✅) · 6 → S05 · 7 → S07 · 8 → S04. Plus audit-found item
  9 (transactional grammar) → S02.

## Open questions (non-blocking)

1. Help search indexes the full `ModelCatalog` built-ins statically (S03
   direction); live on-Bench filtering can come later if noise appears.
2. `origin: mcp` in historical JSON enums stays as wire archaeology (display
   mapping only if it ever confuses an agent — none observed).
3. Hosted CI: `check.sh` is the enforcement point of record for S08; whether a
   `.github/workflows` runner wraps it is a founder call, PARKED.

## Routing

| Work | Read first |
| --- | --- |
| Stale MCP / dryRun / invented flags in help | **This doc §kill list** → `HelpTopicRegistry.swift` |
| `nextAction`/`nextToolPlan` tool-id grammar | **This doc** ASF-S02 → `AgentFrontDoor.swift` (pattern) + kill-list call sites |
| Empty help search / model discovery | **This doc** ASF-S03/S04 → `HelpService.swift`, `HelpContract.swift` |
| Never-again gates / deny-list | **This doc** ASF-S08 + `SSOT_Feature_Workflow.md` §Teaching Surface Rule |
| Bootstrap teaching content | archived `Agent_Onboarding.md` (ONB-S01 shipped; verified clean) |
| Intent routing | archived `Agent_Intent_Router.md` |
| Contract / generated docs | `CLI_Implementation_Contract.md` |
