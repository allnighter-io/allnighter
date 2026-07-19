# CLI Agent Surface Fidelity — stop teaching a CLI we no longer ship

Status: **Active — APPROVED as polish phase (founder dogfood 2026-07-20).**
Owner: AllnighterCore (`HelpTopicRegistry`, `HelpService`, `ContractRegistry`) +
AllnighterCLI (`version`, help/bootstrap) + living ops docs that agents still open
Updated: 2026-07-20

Related: archived `Agent_Front_Door.md` / `Agent_Onboarding.md` /
`Agent_Intent_Router.md` (gates 1–3 shipped — **not** the gap) · living
`CLI_Product_Spine.md` + `CLI_Implementation_Contract.md` ·
`docs/operations/GLM_Worker_Best_Practices.md` (stale pair-slice lead)

## The gap (named precisely)

We keep shipping **power** (`hello --for`, preflight, JSON `nextActions`,
contract hash, Teach your CLIs) and then agents still invent MCP flags, miss
OpenCode/GLM in help search, and paste dead `pair slice` recipes.

That is not a missing feature. It is **agent-facing surface drift**: the help
corpus, first-contact prose, and living ops docs still speak a retired product
while the CLI speaks the current one. Agents trust `alln help *` and checked-in
playbooks more than phase archives. When those lie, agents do not adopt
Allnighter — they reinvent `opencode run --attach …` and burn cycles.

> Front door V1 made Allnighter findable and routable. This phase makes the
> **help surface honest** so adoption does not die one stale paragraph later.

### Founder dogfood packet (2026-07-20) — what landed as feedback

Loved (do not regress): agent-first JSON + `nextActions`; `team hello --for`;
preflight-before-spend; `contractHash` / generated docs / `doctor explain`;
hello → preflight → start/status/result lifecycle.

Adoption blockers (this phase owns them):

1. **Discovery holes** — `help search "opencode"` / `"glm"` returns nothing useful.
2. **Stale MCP vocabulary in live help** — `team_run_loop` still teaches MCP tools
   and `team_start` with `dryRun:true`; CLI has no `--dry-run` (preflight is the
   verb). Agents invent flags that do not exist.
3. **Bootstrap / first paste confusion** — feedback claimed panel/pilot-first paste;
   **ONB-S01 already rewrote bootstrap** to the router reflex (verified on current
   binary). Residual risk: old installed snippets, help topics that still say MCP,
   and unused `panelWorkflowLines` sitting next to the live SSOT.
4. **No obvious self-build** — agents must know `Packages/AllnighterCore` +
   `swift build -c release --product alln`. Need a documented one-liner (and/or a
   thin `alln self-build` later).
5. **Version freshness** — `binaryVersion` was stuck at `0.1.0` (only
   `contractHash` proved rebuilds). **Bumped to `0.9.0` on 2026-07-20** (CLI +
   Mac marketing version). ASF-S05 still adds git SHA / build id beside it.
6. **Too many send verbs** — `run` / `team` / `team start` / `thread send` without a
   first-contact decision tree.
7. **Living docs that teach dead commands** — e.g. GLM playbook still leads with
   deleted `pair slice` (disclaimer exists; agents still pattern-match the verbs).
8. **Empty search silence** — miss → empty `results` + empty `nextToolPlan`. Violates
   the same no-empty-silence law as the front door.

### Why this kept happening (not "we forgot to bump version")

`binaryVersion` was never the docs-sync trigger. Regenerated contract docs are
gated by `ContractRegistry` + `export-contracts --check`. **Hand-authored
`HelpTopicRegistry` prose is not on that gate** — so MCP-era teaching survived
retirement while hashes kept flipping. Full write-up:
`docs/workflows/SSOT_Founder_Input_Workflow.md` §Agent-facing help / Why drift
was still possible. ASF-S01–S03 close the hole mechanically.

### Verified still broken on this machine (2026-07-20)

Run against the workspace `alln` after front-door V1:

| Probe | Result |
| --- | --- |
| `alln bootstrap --host claude` | **Honest** — teaching block is `hello --for` + auth law (ONB-S01). Not the panel paste the feedback remembered. |
| `alln help search "opencode" --json` | **Empty** `results` + empty `nextToolPlan`. |
| `alln help search "glm" --json` | **Empty** `results` + empty `nextToolPlan`. |
| `alln help get team_run_loop --format md` | **Lies** — `team_start` with `dryRun:true`, MCP-era tool grammar. |
| `alln version --json` | `binaryVersion: "0.9.0"` (bumped 2026-07-20); ASF-S05 still wants git SHA / build id beside it. |

So: the feedback is directionally right. Some items are **already fixed but not
felt** (bootstrap / Teach your CLIs — agent may be reading old paste or stale
help). The live failures above are **amateur-hour** because they are exactly the
surfaces agents hit after the front door works.

## Insight

The product spine is already something agents will love. The adoption blockers
are **discovery fidelity** and **doc/help drift** — not missing power.

Law for this phase:

1. **Help is product.** `HelpTopicRegistry` + search hits are agent UX, not
   internal notes. A topic that teaches a flag that does not resolve in
   `ContractRegistry` is a P0 bug.
2. **No MCP grammar on the live agent surface.** Historical archive docs may
   mention MCP. Live help, bootstrap, `--help`, doctor recovery text, and
   living ops playbooks agents are told to open must speak **CLI verbs only**
   (`alln team preflight`, never `team_start(dryRun:true)`).
3. **No empty silence on help miss.** Empty search returns concrete
   `nextToolPlan` / `nextActions` (models, teams, doctor, hello --for examples)
   — same law as `Agent_Front_Door` / intent router.
4. **One SSOT per artifact class.** Help body text is owned by
   `HelpTopicRegistry` (or generated from ContractRegistry where possible).
   Do not hand-maintain parallel MCP tool names in relatedToolIds without an
   explicit CLI mapping table — prefer CLI command names.
5. **Freshness is observable.** Agents must be able to prove they are on the
   binary they just built without archaeology.

## Anti-goals

- Do not invent a second product surface (no MCP revival; no parallel JSON).
- Do not replace `hello --for` / preflight / start with a new mega-command in V1
  of this phase — teach the decision tree in help first; a unified `send` is
  optional later.
- Do not rewrite archived phase history; fix **live** help + living ops docs.
- Do not broaden into Team Lab / Field Reports scope.
- Do not claim cold-agent adoption fixed without a reproducible help-corpus
  Works Test (golden transcripts on the dogfood queries).

## Truth owner / lie-prone layers

| Layer | Role |
| --- | --- |
| **Truth owner** | `ContractRegistry` (flags/commands that exist) + `HelpTopicRegistry` /
  `HelpService` (what agents are taught) + `version` JSON (identity) |
| **Lie-prone** | Help topic bodies with MCP tool ids; empty search with no recovery;
  living ops docs that name deleted verbs; code comments saying "CLI/MCP"
  that get copy-pasted into agent answers; old Teach-your-CLIs installs with
  pre-ONB snippets |
| **Proof** | Golden help-search / help-get transcripts; registry cross-check that
  every flag named in help resolves; `rg` gate for forbidden live MCP-teach
  patterns in HelpTopicRegistry + active ops docs |

## Slices

| Slice | Deliverable |
| --- | --- |
| **ASF-S00** | **Inventory + kill list (no behavior change beyond listing).** `rg`-backed inventory of live MCP-teach strings, `dryRun:true`, `team_start(` MCP grammar, `pair slice`, empty-search paths. Publish the kill list in this doc (or `docs/debuglog/ASF_kill_list.md`) with file:line owners. |
| **ASF-S01** | **Help corpus CLI cutover.** Rewrite `team_run_loop` and every live help topic that still teaches MCP tool grammar to CLI verbs (`alln team preflight`, `alln team start`, …). Map or retire `relatedToolIds` that are MCP tool names. Golden tests: `help get team_run_loop` never contains `dryRun`, `MCP`, or bare `team_start(` call syntax. |
| **ASF-S02** | **Discovery: models/drivers in help search.** Index model display names, driver ids (opencode, glm, …), and team family names into help search (or a dedicated topic + search synonyms). `help search "opencode"` and `"glm"` return useful hits + next steps to `models --json` / `run --worker …`. |
| **ASF-S03** | **Empty-search recovery.** When results are empty, return non-empty `nextToolPlan` / suggested actions: `models --json`, `teams --json` / `team show`, `doctor --json`, `team hello --for "…"`. Never silent miss. |
| **ASF-S04** | **First-contact decision tree topic.** New (or expanded) help topic: when to use `run` vs `team` vs `team start` vs `thread send` — one page agents hit from bootstrap / hello. No new CLI verb required in this slice. |
| **ASF-S05** | **Freshness identity.** `binaryVersion` already **0.9.0** (2026-07-20). Remaining: git SHA and/or build timestamp in `version --json`; document the one-liner to rebuild+install `alln` in `--help` / help topic `install` or `bootstrap` (thin `alln self-build` is optional PARKED if a documented script is enough). |
| **ASF-S06** | **Living docs purge.** Rewrite lead of `GLM_Worker_Best_Practices.md` (and any other **active** ops/playbook agents are routed to) so deleted `pair slice` is not the first verb they see — tombstone at top, current `alln run --worker model_opencode_glm_5_2` path first. Sweep Core comments that assert "CLI and MCP" on agent-facing projections only where they confuse (prefer "CLI / GUI / iOS"; historical origin enum `mcp` may remain as wire archaeology). |
| **PARKED** | Unified `alln send --mode …` CLI sugar · automatic rewrite of already-installed Teach-your-CLIs snippets on app update beyond current marker stale/repair · full comment archaeology across all Core files |

## Works test

Reproducible harness (not anecdote):

```bash
alln help search "opencode" --json   # ≥1 result; nextToolPlan non-empty
alln help search "glm" --json        # ≥1 result; points at models / worker id
alln help get team_run_loop --format md
# must NOT contain: dryRun, MCP tool call syntax, team_start( 
# must contain: alln team preflight, alln team start
alln help search "asdfqwerty-no-such-topic-999" --json
# results may be empty; nextToolPlan / recovery MUST be non-empty
alln version --json                  # exposes build id / git SHA (after S05)
```

Plus a unit/golden suite that fails CI if HelpTopicRegistry reintroduces the
forbidden MCP-teach patterns (ASF-S01 gate).

**Already green (do not "fix" again):** current `alln bootstrap` teaching block
matches ONB-S01 router reflex. If an agent still pastes panel/pilot, tell them
to re-run Teach your CLIs / re-paste bootstrap — that is install freshness, not
a missing rewrite.

## Done when

- ASF-S00–S06 checked or explicitly waived with founder note.
- Works test commands above green on a fresh release binary.
- No live help topic teaches a flag/command that ContractRegistry cannot resolve.
- Founder dogfood packet items 1–3, 5, 7–8 closed; item 4 closed by docs or
  `self-build`; item 6 closed by help decision tree (unified send PARKED).

## Open questions (non-blocking for S00–S01)

1. Is a thin `alln self-build` worth a ContractRegistry command, or is a help
   topic + script enough for V1?
2. Should help search index the full `ModelCatalog` always, or only on-Bench
   models (live) + all built-ins (static)?
3. Keep `origin: mcp` in historical JSON enums forever, or eventually map to
   `system`/`cli` for display only?

## Routing

| Work | Read first |
| --- | --- |
| Stale MCP / dryRun / invented flags in help | **This doc** → `HelpTopicRegistry.swift` |
| Empty help search / model discovery | **This doc** ASF-S02/S03 → `HelpService.swift` |
| Bootstrap teaching content | archived `Agent_Onboarding.md` (ONB-S01 already shipped) |
| Intent routing | archived `Agent_Intent_Router.md` |
| Contract / generated docs | `CLI_Implementation_Contract.md` |
