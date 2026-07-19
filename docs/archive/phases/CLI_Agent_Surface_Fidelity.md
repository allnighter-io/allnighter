# CLI Agent Surface Fidelity — stop teaching a CLI we no longer ship

Status: **Complete (archived 2026-07-20).** ASF-S00–S08 delivered. Works Test
green on release binary from committed HEAD. Code SSOT:
`HelpTopicRegistry` / `HelpDiscoveryIndex` / `RetiredVocabulary` /
`AgentSurfaceNextAction` pattern / `BuildInfo` / `scripts/check.sh` gates.
Commit SHAs: S01 `ddd6cc39` · S02 `5b1f27ba` · S03/S04 `791d591e` ·
S05/S06 `02819c6b` · S07/S08 `ce65caf3`. PARKED remain parked (unified `send`,
hosted CI runner, full comment archaeology).
Owner: AllnighterCore (`HelpTopicRegistry`, `HelpService`, `HelpContract`,
`ContractRegistry`, `AgentBootstrap`, `RetiredVocabulary`) + AllnighterEngine
(`AsyncTeamService`, `AsyncTeamStatusMapper`) + AllnighterCLI (`HelpCLI`,
`version`) + living ops docs agents still open
Updated: 2026-07-20 (archived after Works Test)

**Closeout:** Help prose + transactional `nextAction`/`nextToolPlan` speak CLI
only; catalog search finds opencode/glm; misses recover; version carries
0.9.0 + gitSha; living docs tombstoned; `RetiredVocabulary` + `check.sh` deny
reintroduction. GUI proof waiver recorded for TeachYourCLIsView comment-only
hash drift during ASF closeout.

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
| `alln help get team_run_loop --format md` | **Lies** — body prose carries `team_start(dryRun:true)`, `team_run`/`team_ask`/`run_get`. (Precision: `--format md` renders `relatedCommandNames` only — `HelpService.topicMarkdown:167-179` never prints `relatedToolIds`. The `tools: …` line is the *default text* path, `HelpCLI.swift:61`. Two different lies, two different fixes.) |
| `alln help get team_run_loop --json` | **Also dirty** — `HelpTopic` is `Codable` and encoded whole, so all 10 dead `relatedToolIds` ship in the machine envelope, not just the text projection. |
| `alln docs team_run_loop` | **Same dirty prose, second projection** — `HelpService.docsMarkdown:182-186` reuses `topicMarkdown`. Any S01 golden must cover `docs`, not only `help get`. |
| `alln help search <anything>` (text) | Prints `next: help_get topic=… detail=machine` — not a runnable command. |
| `alln team preflight --team code_bug_hunt` | `nextAction: {kind: "startTeamRun", tool: "team_start"}` — literal `alln team_start` errors. |
| `alln team start … --json` | `nextActions[].tool: "team_status"/"team_result"` — underscore, not runnable. |
| `alln version --json` | `binaryVersion: "0.9.0"` **(fixed + committed + rebuilt 2026-07-20)**; no git SHA / build id yet. |
| `alln team result` / `spec` / `show` / `history` / `team preflight` | All resolve — `tool_selection` topic verbs are clean. |
| `alln run get` | **Does not exist** (an earlier draft of this table listed it as resolving — wrong). `RunCLI` has no `get`; registry has `run` + `run resume` only. This is precisely why `run_get` is on the dead-id list. |

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
  traps). Verified by resolving all 29 distinct ids across 20 `relatedToolIds`
  arrays against the 108 `CommandSpec` names.
- **11th non-resolving id (missed by the first pass): `help`** (L101, L117,
  L461). `ContractRegistry.resolveCommandName("alln help")` → nil; only
  `help get` / `help search` / `help topics` exist. Softer than the other 10
  (bare `alln help` *is* a live dispatch case in `HelpCLI.run`) — so S01 either
  contracts it or stops advertising it. Do not let "it works when typed" hide
  that it is uncontracted.
- **`relatedToolIds` is a JSON leak, not only a text one.** `HelpTopic` is
  `Codable` and encoded whole by `help get --json` / `help topics --json` —
  every dead id ships in the machine envelope agents parse. Killing
  `HelpCLI.swift:61` alone does NOT fix this.
- **`--tool` is a contract-blessed *input* keyed to the dead vocabulary**:
  `ContractRegistry+Milestone1.swift:894` (`help get` summary) and `:898-899`
  (`FlagSpec("tool", … "Find the topic that documents this tool/action id.")`),
  backed by `HelpService.get(tool:)` and `HelpRef.tool` → `alln://tool/<id>`
  (`HelpService.swift:22`). The CLI still *invites* agents to speak MCP ids.
  S01 owns retiring or re-keying this flag — an output-only sweep misses it.
- **`alln docs <topic>`** (`HelpService.docsMarkdown:182-186`) reuses
  `topicMarkdown` — a second projection of the same prose. Goldens must cover it.

**`HelpContract.swift`**: L21–31 orphaned `panelWorkflowLines` /
`pilotWorkflowLines` (0 callers — delete); L125, L163, L167, L175, L180
`tool: "help_get"/"help_search"/"team_hello"` in `nextToolPlan` steps.

**`HelpCLI.swift`** (AllnighterCLI): L34–35 prints `next: <tool_id>`; L61 prints
`tools: <relatedToolIds>` verbatim.

**Transactional surfaces**: `AllnighterCLI.swift:1120` (preflight retryLater →
`tool: "team_start"`); `AgentBootstrap.swift:199` (preflight nextAction), `:63`
(dead — verified end to end: `AgentReadiness.Verdict` is built only at
`AllnighterCLI.swift:1078`, its consumers `AgentHello.build:72-91` and
`AgentIntentRouter:265-268` read only `canStartTeamRun`/`readyTeams`/
`blockedReason`, and `Verdict` is never encoded → `nextAction` has **zero**
readers); `AsyncTeamService.swift:1065-1066` (team start nextActions, in
**AllnighterEngine**); `AsyncTeamStatusMapper.swift:63,65` (team status).

**Six more `tool:` emissions that S02 MUST include** — not underscore ids, but
the same field that S02 deletes, so omitting them means the cutover does not
compile: `AllnighterCLI.swift:1125`, `AgentBootstrap.swift:68, 72, 166, 200`,
`HelpContract.swift:127` (all `tool: "doctor"`). `:68`/`:72` are dead alongside
`:63`. A sweep scoped to "underscore ids" would have shipped a half cutover.

**Known-benign underscore ids (exempt explicitly, do not "discover" later):**
`AgentHello.defaultWorkflows` (`AgentHello.swift:94-108`) emits
`workflows[].id` = `run_async` / `diagnose` / `resolve_stalls` in every
`team hello` payload. These are workflow *labels*, not callable ids, and their
`steps` are clean runnable `alln …` strings. The S08(c) underscore ban must
carve these out by name — otherwise the "never again" gate lands red on day one
and gets weakened to make it pass, which is how the original inversion started.

**Frozen dead vocabulary**: `HelpTopicRegistryTests.swift:11-19` (the inverted
gate) + `:44-48` (`testEveryAdvertisedMCPToolIsReachableFromATopic`).

**Living docs**:
- `docs/operations/GLM_Worker_Best_Practices.md` (253 lines) — 3× broken link
  `../phases/PM_Relay.md` at **L15, L54, L242** (real file: `docs/archive/phases/PM_Relay.md`);
  L96 instructional dead `pair status` inside the default-posture procedure;
  L104 copy-pasteable `scripts/run_cr_phase1.sh` block — **the script no longer
  exists on disk**, so this is a guaranteed-fail paste; **no live replacement
  path** — zero occurrences of `model_opencode_glm` in the whole file.
- `docs/phases/CLI_Product_Spine.md` L214, L215, **L218**, L550, **L655, L711** —
  `alln mcp serve --stdio` / `alln mcp install` presented as live; no `mcp`
  subcommand exists. (L218/L655/L711 were missed by the first pass — a grep for
  `alln mcp`, not a line list, is the only safe sweep. S08's deny-list gate is
  what makes this mechanical.)
- `docs/phases/CLI_Implementation_Contract.md` **L65**, L69, L72, **L732–745**,
  **L765**, L881–884, L907–911 — MCP async-tool contract presented as planned;
  moot since retirement, unannotated. **L65 is the worst line in the file**: it
  lists `alln mcp serve --stdio` as *in scope for milestone 1*. Also the
  §MCP Projection block (L732–745) and `mcp_hello` (L765).
- `docs/mvp/RB6_Team_As_Tool.md` — MCP-first spec, historical only via
  AGENTS.md routing; no in-file tombstone, and its **status line still reads
  "BUILT (engine + CLI + MCP)"** (only a June-2026 vocabulary note exists).
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
7. **Sweep by grep, never by line list.** This doc's own first pass enumerated
   line numbers and missed `CLI_Product_Spine.md` L218/L655/L711,
   `CLI_Implementation_Contract.md` L65, the `--tool` input flag, the `--json`
   `relatedToolIds` leak, and six `tool: "doctor"` sites. A hand-enumerated
   inventory is a snapshot that rots on the next edit; the deny-list grep (S08b)
   is the only sweep that stays true. **Line numbers below are navigation aids,
   not the contract — the contract is the grep.**
8. **A gate that lands red is fixed by fixing the code, never by narrowing the
   gate.** The inversion started as one reasonable-sounding accommodation
   ("frozen here in the interim"). Any future carve-out must name the exempted
   symbol explicitly and say why it is not agent-callable.

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
| **ASF-S01 ✅ DONE (`ddd6cc39`)** | Help corpus CLI cutover + honest gate. |
| **ASF-S02 ✅ DONE (`5b1f27ba`)** | Next-action grammar cutover (`command`, no `"tool"` key). |
| **ASF-S03 ✅ DONE (`791d591e`)** | Discovery: catalog→search bridge. |
| **ASF-S04 ✅ DONE (`791d591e`)** | Empty-search recovery + miss-consistency. |
| **ASF-S05 ✅ DONE (`02819c6b`)** | First-contact decision tree (`tool_selection`). |
| **ASF-S06 ✅ DONE (`02819c6b`)** | Freshness identity (`BuildInfo` gitSha/buildTime + self-build help). |
| **ASF-S07 ✅ DONE (`ce65caf3`)** | **Living docs purge.** GLM playbook leads with `alln run --worker model_opencode_glm_5_2`; PM_Relay links → `docs/archive/phases/`; historical batch script fenced non-runnable; `CLI_Product_Spine` / `CLI_Implementation_Contract` MCP examples tombstoned; `RB6_Team_As_Tool` in-file tombstone (status no longer claims live MCP); vestigial `pair slice` match dropped from `StalledWorkDetector`. |
| **ASF-S08 ✅ DONE (`ce65caf3`)** | **Durable mechanical gates.** `RetiredVocabulary` (ONE Swift deny-list) consumed by XCTest + `check.sh` living-doc grep; prose-command resolution via `ContractRegistry.resolveCommandName`; underscore-tool-id ban with explicit `AgentHello.defaultWorkflows` carve-out (`run_async`/`diagnose`/`resolve_stalls`); `alln dev export-contracts --check` wired into `scripts/check.sh`. |
| **PARKED** | Unified `alln send --mode …` sugar · auto-rewrite of installed snippets beyond current marker stale/repair (mechanism exists: version+hash markers + Mac `GlobalTeachingInstaller` repair) · full comment archaeology · CI runner (no `.github/workflows` exists; `check.sh` is the gate of record — founder call whether hosted CI is wanted) |

### Archive

Moved to `docs/archive/phases/CLI_Agent_Surface_Fidelity.md` on 2026-07-20 after
Works Test green on release binary from committed HEAD (SHAs in status header).

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
