# Allnighter — MCP Tool Upgrade

**Status:** Proposed — decision doc (implementation spec, not a survey)
**Updated:** 2026-06-27
**Owner:** AllnighterCore (ContractRegistry) + AllnighterCLI (MCPServer)
**Reference lessons:** `XTerminal/docs/phases/MCP_Hardening_Core_Upgrade.md` (64→25 clean cut),
`websitemd.studio/Docs/product/MCP_Tool_Surface_Contract.md` (frozen wire ABI + capability-as-data).
**Adjacent:** [[allnighter-agent-first-schemas]], [[allnighter-mcp-help]], `docs/phases/MCP_Agent_First_Contract.md`.

---

## Why (read this first)

Allnighter is **MCP-first by design**. "Hand work to your AI" means an external agent
(Claude, Cursor, a custom client) is the *primary operator* — the MCP tool catalog is the
front door, not a side surface. So the catalog's health **is** the product's health.

Ground truth, verified 2026-06-27:

- **61 tools** exposed by `tools/list` (`ContractRegistry.m1MCPTools`, one `MCPToolSpec`
  each, dispatched in `MCPServer.handleCall`).
- That number is the symptom of the exact mistake both reference projects made and then
  had to undo: a **1:1 "every capability becomes a wire tool" mapping**. XTerminal hit 64
  and cut to 25; website.studio hit **107** and froze to ~15. We are on the same curve.

The cost is emergent — invisible in isolation, only visible under a real client:

1. **Every turn pays for all 61.** The full tool list lives in the cached prefix and is
   re-injected on every agent turn (token tax + a selection cliff the model walks every
   turn). Several of our tools carry heavy schemas (`thread_send` alone declares ~24 error
   codes and two nested array-of-`oneOf` params).
2. **We pay the catalog tax twice.** `mcp_hello` re-embeds the **entire 61-name roster**
   (`tools: [ToolRef]`, `AllnighterCLI.swift:928`). The one tool whose job is cheap
   bootstrap is itself a second full copy of the surface.
3. **Wrong-tool retries.** 61 names with real overlap (`team_ask` vs `team_start` vs
   `team_run`; `show` vs `spec_get` vs `floor_show`; `thread_get` vs `thread_status`;
   four `pending_*` mutations; three `stall_*` mutations) make the model pick wrong and
   burn a round-trip.
4. **Client caps fail silently.** Cursor silently drops tools past ~40; thresholds are
   undocumented and vary. We are at **61 — over the cap**, so a Cursor user may already be
   getting a *silently truncated* roster, the worst failure mode for a launch.

**The win is session-level: cheaper turns, fewer iterations, no silent truncation.** It
does **not** make any individual call faster.

**Timing is the whole argument. We have zero users** ([[allnighter-mvp-state]],
[[allnighter-foundation-first]]). Once agents wire flows to tool names, every rename is a
breaking change with a deprecation cycle. Pre-launch is the only window where this is
*free*. This is a **clean cut**: delete and replace in one pass — no aliases, no shims, no
"deprecated but still works" tools ([[allnighter-working-prefs]], [[allnighter-language-cutover]]).

**Goal: world-class, done right — not a target number.** The number falls out of the
principles in §3; the cap in §6 only prevents *regression*.

---

## 1. What we already got right (lock it in)

- **All 61 names are `snake_case`, underscores only.** No dot notation — the bug that broke
  clients for the project website.studio audited. Emitted verbatim
  (`MCPServer.toolDefinitions` → `["name": tool.name]`), no namespace/prefix step.
- **No `resources/list` / `prompts/list` handlers** — no other client-facing identifiers at
  risk.
- **Contract-first already holds:** every tool has a `command` CLI projection, a typed
  `outputSchema`, a declared error set, and an idempotency rule, enforced by
  `MCPToolContractTests` ([[allnighter-agent-first-schemas]]). Returns are structured —
  we never offered a "cheaper text return."

This pass makes those conventions **enforced invariants** (§6) so they can never regress,
and adds the four guards we are missing (count cap, naming assertion, orphan scan,
schema-weight ratchet).

---

## 2. The two lessons, mapped to Allnighter

**From XTerminal (the merge discipline).** Subtraction is the discipline; bloat is the
default of a 1:1 mapping. Re-audit the *whole* surface against real client + model
behavior; consolidate genuinely-overlapping operations behind one clear
`action`/`mode`/`view` param — but never a god-tool. Demote internal plumbing and
owner-only admin off the agent catalog. Guard with a hard count cap, naming invariant,
orphan scan, and schema-weight ratchet.

**From website.studio (the architecture).** A wire tool is an *address*; a capability is a
*power*. **Many powers, few addresses.** The wire surface is a small, frozen, hand-
maintained allow-list; new capability ships **as data** (discovered through `mcp_hello` +
`project_context`), never as a new wire name. A client that connected last month must be
able to use a capability shipped today through tools it already cached.

**The synthesis for Allnighter:** do XTerminal's merge-to-lean **now** (we share its
contract-registry + CLI-parity architecture, so the merge model fits directly), and adopt
website.studio's **frozen-ABI mindset** so the cut *stays* cut: `mcp_hello` stops echoing
the roster and instead carries grouped next-tool guidance, and `project_context` is the
designated "capability as data" pack. New power → new registry behavior / enum value /
`project_context` field, **not** a new `tools/list` entry.

---

## 3. Design principles (these pick the surface, not a number)

**Final for implementation.** Every naming/merge/schema call an implementer might make
mid-build is decided here. Deviating means editing this doc with sign-off — never an
in-flight call. website.studio re-bloated to 107 *because the lesson lived in an execution
spec that got archived*; this is the durable home.

- **P1 — Agent surface ≠ engine/owner surface.** A tool is on the MCP catalog only if an
  external agent would directly call it to do the user's job. Owner-only config (Boost
  window placement, Default-model rosters) and internal mechanics stay reachable via CLI
  or engine and leave the agent catalog. Demoting them is *not* a parity loss (§P7).
- **P2 — Fewer well-named tools, never a god-tool.** Consolidate overlapping operations
  behind one clear `action`/`mode`/`view` param — never a single `team`/`pending`
  mega-tool with a 10-value enum. The line between "clear verbs via param" and "action-enum
  confusion" is thin: every merge must satisfy P5 and the union-schema rule (§7).
- **P3 — Read where you write.** An entity's `get` and `list` collapse into one tool where
  `id` omitted = lightweight summary array, `id` present = full record. The payload split
  is specified per tool, not implied.
- **P4 — Create is idempotent and absorbs its variants.** `*_edit` that updates-by-id
  absorbs save/duplicate/set-default/delete/restore via an `action`; a `dryRun` flag
  absorbs preflight/validate. Update semantics are **PATCH, not PUT**.
- **P5 — Schemas and descriptions pay rent.** For every survivor, trim the description to
  what the model needs to **choose correctly and disambiguate from adjacent tools** — state
  when to use it and when not. Merged tools inherit *more* routing responsibility, so their
  descriptions do more work, not less.
- **P6 — `snake_case`, underscores only, forever.** Tool names `^[a-z][a-z0-9_]*$`,
  params `^[a-z][a-zA-Z0-9]*$`. Never a dot in any client-facing identifier (§6, T2).
- **P7 — Parity is preserved; the registry has four exact states.** Capability is never
  lost on the user-facing side. Each tool occupies exactly one state, assigned per tool in
  §13:

  | State | In MCP catalog | CLI path | Members |
  |-------|:---:|:---:|---------|
  | **Agent tool** | yes | yes | the 28 survivors |
  | **CLI-only** (owner admin) | no | yes | `boost_window` show/set/seed/clear |
  | **Engine-only** (pure internal) | no | no | warm-worker lifecycle, stagers, coordinators (already not tools) |
  | **Removed** (merged away) | no | no | the §B "→" names |

  "User-facing GUI-only capability is a bug" still holds. Boost-window controls are
  **owner config** (the user sets a placement once from a terminal, like XTerminal's
  `monitor_launchd`), not an agent capability — demoting them honors parity. Agents are
  already **readers, not approvers** for owner config ([[allnighter-default-model-tiers]],
  project approve/edit deliberately un-projected), so this is consistent with the existing
  line.
- **P8 — Irreversible / lane-unsafe operations stay deliberate.** A tool that cannot be
  cleanly undone keeps a distinct, unambiguous entry so the model commits to it on purpose.
  This is why the **mutating execution entries are not collapsed into one god-runner**:
  `team_run` (one mutating worker in a repo) and the `pair_*` slice executor stay as clear,
  separate verbs. The execution lane is INVIOLABLE ([[allnighter-pending-execute-lane-safety]]);
  ambiguity on the mutating path is the one place we never trade for tool-count.
- **P9 — New capability ships as data, not as ABI (website.studio).** Adding a power is a
  new registry behavior / enum value / `project_context` field — **never** a new
  `tools/list` name. `mcp_hello` advertises *what's runnable now* as data; it does not grow
  a wire tool per feature. A client cached in March uses a capability shipped in June
  through the tools it already has.

---

## 4. Behavioral contracts for merged tools

Part of the spec — they determine whether a merge is safe.

- **`teams_edit` / `skills_edit` = PATCH by id, `action`-dispatched.** `action ∈
  {save, duplicate, set_default, delete, restore}` (teams) / `{save, duplicate, delete}`
  (skills). `save` with an existing id partial-merges; it never blanks a field the agent
  didn't send. Lab-team typeTag and lane-match invariants (today in `teams_save`) are
  enforced on the merged path unchanged.
- **`teams_get` / `skills_get` (P3).** `teamId`/`skillId` omitted → lane-scoped summary
  array (the old `*_list`); present → full record (`*_show`); `detail:"definition"` →
  round-trippable `TeamPreset` JSON (the old `teams_definition`). Output schema is
  discriminated by which was asked, not blindly unioned. No-arg `teams_get` also returns
  the per-lane defaults (absorbs `team_show`).
- **`team_start` absorbs preflight via `dryRun`.** `dryRun:true` resolves lane/team/effort
  against the ready bench and returns the would-be plan **without spending quota or taking
  the lane** — exactly today's `team_preflight`. `team_start` stays `keyed` (idempotency
  key); a real start is never idempotent.
- **`team_result` absorbs `team_status`.** While running it returns the lightweight state
  + `nextPollAfterMs`; when terminal it returns full `TeamRunJSON`. One read tool, output
  discriminated by terminal-ness (today's `team_status` and the `RESULT_NOT_READY`
  envelope are the two shapes).
- **`team_run` absorbs `team_ask`.** One synchronous run entry. `project` present → run in
  the repo root (today's `team_run`, may dispatch one mutating worker); `project` omitted →
  laneless answer-team run (today's `team_ask`). Output is `TeamRunJSON` either way; the
  description names which arg selects which mode. (Async lifecycle stays `team_start` /
  `team_result` / `team_cancel` — different latency contract, P8.)
- **`run_get` absorbs `show` + `spec_get` + `floor_show`.** One run reader keyed by run id
  or `latest`, `view ∈ {summary, spec, floor}` (default `summary`), mode-discriminated
  output (`TeamRunJSON` / `SpecResult` / `FloorRun`). `history` stays separate (search over
  many runs, different shape).
- **`pending_list` absorbs `pending_show` + `pending_queue`.** `pendingId` present → one
  item (`pending_show`); omitted → list; `mode:"queue"` → the render-ready armed-queue
  bundle (`pending_queue`). `pending_update` absorbs submit/edit/reorder/cancel via
  `action`; edit returns a Pending item to Draft (un-arms) exactly as today. `pending_run`
  stays separate (it executes — P8-adjacent, mutating).
- **`thread_get` absorbs `thread_status` + `thread_attachment_get`.** Base get returns the
  snapshot incl. `isRunning`/`needsAttention` (status is a projection subset);
  `attachmentId` present → that attachment record. `thread_send` (mutation) and
  `thread_rename` (mutation) stay separate.
- **`stalled_list` absorbs `project_stalled`.** `project` present → that project's
  episodes; omitted (with `all:true`) → aggregate. `stalled_update` absorbs
  check/keep-waiting/dismiss via `action ∈ {check, wait, dismiss}`.
- **`project_get` absorbs `project_list`** (`project` omitted → list). `project_workers`
  absorbs `project_recheck_workers` via `refresh:true` (runs driver-declared safe probes;
  never auto-config/auth — [[allnighter-cli-setup]], [[allnighter-no-api-keys]]).
  `project_context` stays its own tool — it **is** the website.studio "capability as data"
  pack (P9).
- **`help` absorbs `help_search` + `help_get`** (`query` → search; `topic`/`ref`/`tool`/
  `error` → fetch). Unknown selectors still return close matches + sitemap, never a dead
  end ([[allnighter-mcp-help]]).

---

## 5. The audit → target surface (61 → 28)

### §A — Demote off the MCP surface (owner admin — P1/P7). Net −4.

- `boost_window_show`, `boost_window_set`, `boost_window_seed`,
  `boost_window_observations_clear` → **CLI-only**. Boost-window placement/seeding is a
  one-time owner config from a terminal, not an agent capability. The read remains visible
  to agents through `doctor` (full). Keeps the `boost-window …` CLI path. **(−4)**

### §B — Merge overlapping operations (P2–P5). Net −29.

**Catalog (−7)**
- `teams_list` + `teams_show` + `teams_definition` → **`teams_get`** (absorbs `team_show`). (−3)
- `teams_duplicate` + `teams_save` + `teams_set_default` + `teams_delete` + `teams_restore`
  → **`teams_edit`** (`action`). (−4)
- `skills_list` + `skills_show` → **`skills_get`**. (−1)
- `skills_duplicate` + `skills_save` + `skills_delete` → **`skills_edit`** (`action`). (−2)
- `team_show` → **`teams_get`** (no-arg). (−1)

**Execution (−4)**
- `team_preflight` → **`team_start`** (`dryRun`). (−1)
- `team_status` → **`team_result`**. (−1)
- `team_ask` → **`team_run`** (`project` optional). (−1)
- `pair_slice` → **`pair_run`** (single packet vs `queueDir`). (−1)

**Run inspection (−2)**
- `show` + `spec_get` + `floor_show` → **`run_get`** (`view`). (−2)

**Threads (−2)**
- `thread_status` → **`thread_get`**. (−1)
- `thread_attachment_get` → **`thread_get`** (`attachmentId`). (−1)

**Pending (−5)**
- `pending_show` + `pending_queue` → **`pending_list`**. (−2)
- `pending_submit` + `pending_edit` + `pending_reorder` + `pending_cancel` →
  **`pending_update`** (`action`). (−3)

**Stalled (−3)**
- `project_stalled` → **`stalled_list`** (`project`). (−1)
- `stall_check_status` + `stall_keep_waiting` + `stall_dismiss` → **`stalled_update`**
  (`action`). (−2)

**Projects (−2)**
- `project_list` → **`project_get`**. (−1)
- `project_recheck_workers` → **`project_workers`** (`refresh`). (−1)

**Help (−1)**
- `help_search` + `help_get` → **`help`**. (−1)

### §C — Keep as-is (firm core)

`mcp_hello`, `doctor`, `error_explain`, `defaults_get`, `history`, `team_start`,
`team_result`, `team_cancel`, `team_run`, `pair_run`, `pair_status`, `thread_send`,
`thread_rename`, `pending_run`, `stalled_list`, `project_context`.

### Resulting target catalog (28)

```
Bootstrap & recovery: mcp_hello, doctor, error_explain, help, defaults_get, history
Catalog:              teams_get, teams_edit, skills_get, skills_edit
Execution:            team_run, team_start, team_result, team_cancel, run_get
Pair executor:        pair_run, pair_status
Threads:              thread_send, thread_get, thread_rename
Pending:              pending_list, pending_update, pending_run
Stalled:              stalled_list, stalled_update
Projects:             project_get, project_context, project_workers
```

**61 → 28** (−33: §A −4, §B −29). Under the ~40 client cap with real headroom; roughly
halved toward the ~20 model selection cliff. We stop *below* 28 only if a merge in §7
forces a split back out.

**Why 28 and not 25/15.** Allnighter genuinely carries more first-class surfaces than the
reference projects (threads, pending, stalled, projects, two catalogs, an async execution
lifecycle *and* a mutating-repo runner). The reference targets came from narrower products.
We refuse to hit a lower number by collapsing the **mutating execution path** into a god-
runner (P8) — that path's clarity is non-negotiable ([[allnighter-pending-execute-lane-safety]]).
28 is the honest floor without a god-tool.

---

## 6. Guardrails (the structural fix that prevents recurrence)

`MCPToolContractTests` today checks metadata, no-name-only, error-code existence, and
idempotency — but **no count cap, no naming assertion, no orphan scan, no schema-weight
ratchet, and nothing stops `mcp_hello` re-embedding the roster.** Add all of these.

- **T1 — Count cap.** `XCTAssertLessThanOrEqual(registry.mcpTools.count, MAX_MCP_TOOLS)`,
  `MAX_MCP_TOOLS = 30` (target 28, **two** slots headroom). Code comment: *"Raising this
  requires editing docs/phases/MCP_Tool_Upgrade.md §3 first — last-resort guardrail, not a
  budget."*
- **T2 — Naming invariant.** Every tool name matches `^[a-z][a-z0-9_]*$`; every param name
  matches `^[a-z][a-zA-Z0-9]*$`. Loop over `registry.mcpTools`. Makes dot-notation
  structurally impossible.
- **T3 — No orphan names (the half-migration guard — highest value).** A test asserting no
  string anywhere references a tool name not in `mcpTools`. Inverse-scan the known
  embedding sites: `mcp_hello` payload (`AllnighterCLI.mcpHelloJSONString` `tools` +
  `decisionTree` + `quickstart`), `AgentReadiness` next-action/decision strings,
  `HelpService`/`HelpTopicRegistry` refs, `docs/generated/alln/mcp-tools.json`,
  `error-codes` `agentAction` strings, `AGENTS.md`, and the CLI agent system prompt. A
  rename that misses any site fails the build.
- **T4 — Bidirectional parity.** `MCPParityTests` already checks MCP↔CLI; extend to assert
  the parity table's key set **equals** `mcpTools` names, so no tool can be added/merged/
  removed without the parity map updated in lockstep.
- **T5 — Schema-weight ratchet (enforces P5).** No single tool's serialized
  input-schema + description (UTF-8 char count) exceeds `MAX_TOOL_SCHEMA_CHARS`.
  **Calibration:** at Slice 0 set it to today's heaviest tool's size; it may only ever
  *decrease*. Additionally each merge survivor's serialized schema must be **≤ the largest
  single tool it replaces** ("union ≤ prior worst"). `thread_send`'s ~24-code error list is
  the likely current ceiling — trim it (§7).
- **T6 — `mcp_hello` does not echo the roster (the website.studio guard, Allnighter-
  specific).** Assert `mcp_hello`'s payload does **not** contain the full tool-name list:
  it carries *grouped, curated* next-tool guidance (the `decisionTree`/`quickstart` shape),
  not a 1:1 `tools: [ToolRef]` mirror of `tools/list`. This kills the second per-turn
  catalog tax and stops the surface bloating in a second place. Also assert **state
  invariance** — `tools/list` is identical regardless of readiness / which sources are
  logged in (presence never encodes state; P9).

Run: `swift test --package-path Packages/AllnighterCore` + the repo proof wall
([[allnighter-conventions]]).

---

## 7. Per-merge safety rule (applied during §B)

Each survivor's serialized schema (params + description) must be **≤ the largest single
tool it replaces** (T5). Pre-decided fallbacks where a union is plausibly over budget — an
implementer never chooses at build time:

- **`thread_send`** (already the heaviest: ~24 error codes + two nested `oneOf` array
  params). It is *not* a merge target, but it sets the T5 ceiling, so trim it at Slice 0:
  keep the routing-critical codes in the schema; move the long attachment/file-reference
  failure catalog to `error_explain` + the help topic (the description points there). The
  full code set stays reachable; it just leaves the per-turn schema.
- **`teams_edit`** (save + duplicate + set_default + delete + restore): if over budget,
  split **reads from writes is already done** (reads live on `teams_get`); the fallback is
  to move `restore` back to its own tool (it is the least-used verb), staying at ≤30.
- **`pending_update`** (submit + edit + reorder + cancel): `edit` carries the most params.
  If over budget, keep `pending_edit` separate and merge only submit/reorder/cancel.

All other merges are within budget by inspection (small action sets).

---

## 8. Migration: clean cut (zero users → zero accommodation)

Not a deprecation. Each slice is one atomic change, build + full suite green at the end
([[allnighter-working-prefs]]: commit each step).

1. **Delete** removed/merged `MCPToolSpec` entries from `m1MCPTools`; demote §A to CLI-only
   (keep the `CommandSpec`, drop the `MCPToolSpec`).
2. **Delete** the corresponding `tools/call` dispatch arms / orphaned handler code in
   `MCPServer.swift` and the `MCP*Handlers` files. Capability that survives moves into the
   survivor's handler; the removed wrapper is deleted, not stubbed.
3. **Rewire** merged behavior into the survivor's handler via its new
   `action`/`mode`/`view`/`dryRun`/`refresh` param, honoring §4. The underlying engine
   services (TeamCatalog, ProjectStore, Pending/Stalled stores, ThreadStore) are unchanged
   — this is a *surface* cut, not an engine rewrite.
4. **Update** CLI `command:` projections so MCP↔CLI parity (T4) holds.
5. **Regenerate** `docs/generated/alln/mcp-tools.json` **via the export path / test, never
   by hand** (T3 catches drift).
6. **Rewrite embedded references in the same commit:** `mcp_hello` payload (drop the
   roster mirror per T6; regroup `decisionTree`/`quickstart` to the 28-tool surface),
   `AgentReadiness` routing, `HelpService` topics, `error-codes` `agentAction` strings,
   `AGENTS.md`, the CLI agent system prompt.
7. **Update tests** to the new surface (§6). Never leave a half-migrated catalog.

No old name survives as a working alias — calling one returns "unknown tool," which is the
intended behavior. A human-facing `old → new` table goes in the **PR description**, never
as a runtime shim.

---

## 9. Rollout slices (caps tighten monotonically; green at every step)

| Slice | Scope | Net Δ | Tools after | `MAX_MCP_TOOLS` |
|-------|-------|------:|------------:|----------------:|
| **0** | Land T1–T6 calibrated to current surface; trim `thread_send` (T5); strip `mcp_hello` roster mirror (T6) | 0 | 61 | 61 |
| **1** | §A boost-window → CLI-only | −4 | 57 | 57 |
| **2** | Catalog merges (`teams_get`/`teams_edit`/`skills_get`/`skills_edit`, `team_show`) | −7 | 50 | 50 |
| **3** | Execution + run-inspection merges (`team_start` dryRun, `team_result`, `team_run`, `pair_run`, `run_get`) | −6 | 44 | 44 |
| **4** | Threads + pending merges (`thread_get`, `pending_list`, `pending_update`) | −7 | 37 | 37 |
| **5** | Stalled + projects + help merges + description/schema-quality pass + doc/catalog/AGENTS.md rewrite | −9 | 28 | **30** |

Each slice: code + CLI + catalog + embedded refs + tests in one commit. The count falls
61 → 57 → 50 → 44 → 37 → 28, build green at every step.

---

## 10. Proof / launch gate

Not "done" until:

1. Repo proof wall green (T1–T6 + T3 orphan scan).
2. `MCPParityTests` updated to the 28-tool surface and passing (T4).
3. `MCPToolContractTests` extended with T1/T2/T5/T6 and passing.
4. Contract export (`docs/generated/alln/mcp-tools.json`) regenerated and diffed clean in
   CI (no by-hand edits).
5. `mcp_hello` payload re-inspected: no full roster; grouped guidance only; identical across
   readiness states (T6).
6. **Real-client smoke (manual, once):** connect from Cursor and from Claude, confirm the
   tool list is **not truncated** (we are moving from 61 — over the ~40 cap — to 28, under
   it), and run one full loop end-to-end: `mcp_hello` → `team_run`/`team_start` →
   `team_result` → `run_get`. This *confirms* the headroom; it does not re-open the target.
7. **Golden agent trace:** check in a fixture of the bootstrap → run → inspect tool sequence
   so Slices 1–5 cannot silently regress discovery order.

---

## 11. Postmortem invariant (carried from both reference projects)

Both reference projects received a correct "world-class MCP" mandate and **bloated** —
XTerminal to 64, website.studio to 107 — because a 1:1 capability→tool mapping looks like
best practice in isolation and its cost is emergent, only visible under a real cached/capped
client. website.studio re-bloated *after* a cleanup because the lesson lived in an execution
spec that got archived.

**Standing correction, enforced here:** on any "best-practice / world-class" mandate for the
tool surface, *re-audit the entire surface against real client and model behavior* — never
merely add locally-good pieces. Bloat is the default of a 1:1 mapping; **subtraction is the
discipline, and new power ships as data (P9), not as a new address.** This pass is framed as
a subtraction with a hard cap (T1), naming invariant (T2), orphan guard (T3), schema-weight
ratchet (T5), and a no-roster-echo guard (T6) precisely so the next mandate cannot recreate
any of those failures. This doc — not an execution spec — is the durable home.

---

## 12. Appendix — full disposition ledger (all 61)

`survivor` = stays on the MCP surface. `CLI-only` = demoted per P7 (§A). `→ X` = removed;
behavior merged into X (§B). New tools created *by* a merge (`teams_get`, `teams_edit`,
`skills_get`, `skills_edit`, `run_get`, `pending_update`, `stalled_update`, `help`) do not
get their own row — they are named in the disposition of the tools they absorb.

| # | Tool (today) | Disposition | Slice |
|---|--------------|-------------|:----:|
| 1 | `mcp_hello` | survivor (T6: stop echoing roster) | 0 |
| 2 | `teams_list` | → `teams_get` (new) | 2 |
| 3 | `teams_show` | → `teams_get` | 2 |
| 4 | `teams_definition` | → `teams_get` (`detail`) | 2 |
| 5 | `teams_duplicate` | → `teams_edit` (new) | 2 |
| 6 | `teams_save` | → `teams_edit` | 2 |
| 7 | `teams_set_default` | → `teams_edit` | 2 |
| 8 | `teams_delete` | → `teams_edit` | 2 |
| 9 | `teams_restore` | → `teams_edit` | 2 |
| 10 | `skills_list` | → `skills_get` (new) | 2 |
| 11 | `skills_show` | → `skills_get` | 2 |
| 12 | `skills_duplicate` | → `skills_edit` (new) | 2 |
| 13 | `skills_save` | → `skills_edit` | 2 |
| 14 | `skills_delete` | → `skills_edit` | 2 |
| 15 | `team_preflight` | → `team_start` (`dryRun`) | 3 |
| 16 | `team_start` | survivor (absorbs preflight) | 3 |
| 17 | `team_status` | → `team_result` | 3 |
| 18 | `team_result` | survivor (absorbs status) | 3 |
| 19 | `team_cancel` | survivor | — |
| 20 | `team_run` | survivor (absorbs team_ask) | 3 |
| 21 | `pair_slice` | → `pair_run` | 3 |
| 22 | `pair_run` | survivor (absorbs pair_slice) | 3 |
| 23 | `pair_status` | survivor | — |
| 24 | `team_ask` | → `team_run` | 3 |
| 25 | `team_show` | → `teams_get` (no-arg) | 2 |
| 26 | `history` | survivor | — |
| 27 | `show` | → `run_get` (new, `view:summary`) | 3 |
| 28 | `doctor` | survivor (absorbs boost-window read) | 1 |
| 29 | `error_explain` | survivor (absorbs trimmed thread_send codes) | 0 |
| 30 | `spec_get` | → `run_get` (`view:spec`) | 3 |
| 31 | `floor_show` | → `run_get` (`view:floor`) | 3 |
| 32 | `thread_send` | survivor (T5 trim) | 0 |
| 33 | `thread_get` | survivor (absorbs status + attachment) | 4 |
| 34 | `thread_rename` | survivor | — |
| 35 | `thread_status` | → `thread_get` | 4 |
| 36 | `thread_attachment_get` | → `thread_get` (`attachmentId`) | 4 |
| 37 | `pending_list` | survivor (absorbs show + queue) | 4 |
| 38 | `pending_show` | → `pending_list` (`pendingId`) | 4 |
| 39 | `pending_queue` | → `pending_list` (`mode:queue`) | 4 |
| 40 | `pending_submit` | → `pending_update` (new) | 4 |
| 41 | `pending_edit` | → `pending_update` | 4 |
| 42 | `pending_reorder` | → `pending_update` | 4 |
| 43 | `pending_cancel` | → `pending_update` | 4 |
| 44 | `pending_run` | survivor | — |
| 45 | `project_stalled` | → `stalled_list` (`project`) | 5 |
| 46 | `stalled_list` | survivor (absorbs project_stalled) | 5 |
| 47 | `stall_check_status` | → `stalled_update` (new, `action:check`) | 5 |
| 48 | `stall_keep_waiting` | → `stalled_update` (`action:wait`) | 5 |
| 49 | `stall_dismiss` | → `stalled_update` (`action:dismiss`) | 5 |
| 50 | `project_list` | → `project_get` | 5 |
| 51 | `project_get` | survivor (absorbs project_list) | 5 |
| 52 | `project_context` | survivor (the P9 capability-as-data pack) | — |
| 53 | `project_workers` | survivor (absorbs recheck via `refresh`) | 5 |
| 54 | `project_recheck_workers` | → `project_workers` (`refresh`) | 5 |
| 55 | `defaults_get` | survivor | — |
| 56 | `boost_window_show` | CLI-only (§A; read via doctor) | 1 |
| 57 | `boost_window_set` | CLI-only (§A) | 1 |
| 58 | `boost_window_seed` | CLI-only (§A) | 1 |
| 59 | `boost_window_observations_clear` | CLI-only (§A) | 1 |
| 60 | `help_search` | → `help` (new) | 5 |
| 61 | `help_get` | → `help` (new) | 5 |

**Reconciliation (every one of the 61 accounted for):**

- **20 survivors keep an existing name:** mcp_hello, team_start, team_result, team_cancel,
  team_run, pair_run, pair_status, history, doctor, error_explain, thread_send, thread_get,
  thread_rename, pending_list, pending_run, stalled_list, project_get, project_context,
  project_workers, defaults_get.
- **8 new survivors created by merges:** teams_get, teams_edit, skills_get, skills_edit,
  run_get, pending_update, stalled_update, help.
- **4 demoted to CLI-only (§A):** boost_window_show/set/seed/clear.
- **29 removed names merged into survivors (§B "→" rows).**

`20 existing-survivors + 29 removed + 4 CLI-only = 53` … plus the **8 survivors that were
themselves renamed/merged-from removed rows are counted in the 29** → final MCP surface =
`20 + 8 = ` **28 tools.** ✔  (61 − 4 CLI-only − 29 merged-away = 28.)

---

## 13. Cross-doc updates (do in Slice 5, same commit)

- `AGENTS.md`: repoint MCP work to this doc; rewrite any tool lists to the 28-tool surface.
- `docs/phases/MCP_Agent_First_Contract.md`: rewrite its tool lists to the 28-tool surface;
  reference this doc as the canonical surface contract.
- Update [[allnighter-mcp-help]] and [[allnighter-agent-first-schemas]] memory pointers once
  landed (help_search/help_get → help; the surface count).
