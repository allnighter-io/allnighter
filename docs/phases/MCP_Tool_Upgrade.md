# Allnighter — MCP Tool Upgrade (v2)

**Status:** Proposed — decision doc / implementation spec (not a survey)
**Updated:** 2026-06-27
**Owner:** AllnighterCore (ContractRegistry) + AllnighterCLI (MCPServer)
**Supersedes:** v1 of this file (the 61→28 count-cut). v2 keeps every v1 guardrail and adds
the **wire-protocol layer** the v1 draft under-specified, after two mentor reviews.
**Reference lessons:** `XTerminal/docs/phases/MCP_Hardening_Core_Upgrade.md` (merge discipline +
ratchets), `websitemd.studio/Docs/product/MCP_Tool_Surface_Contract.md` (frozen wire ABI +
capability-as-data), **Ikiro Phase 50 / Cursor `outputSchema` rejection** (2026-06-27 — see
§6.7: green connected + 0 tools when `tools/list` carries schemas Cursor cannot parse).
**Adjacent:** [[allnighter-agent-first-schemas]], [[allnighter-mcp-help]],
[[allnighter-pending-execute-lane-safety]], `docs/phases/MCP_Agent_First_Contract.md`.

---

## Why (read this first)

Allnighter is **MCP-first by design** — the agent is the primary operator, so the catalog's
health *is* the product's health. v1 of this doc correctly diagnosed catalog bloat (61 tools,
over Cursor's silent ~40 cap, double per-turn tax because `mcp_hello` re-embeds the whole
roster) and prescribed a clean 61→28 cut.

**v1's blind spot, named by review: it optimized tool *count* while leaving the *wire
protocol* at 2024-era quality.** World-class MCP in 2026 is not "fewer tools." It is
**fewer tools + correct wire semantics + model-grade metadata.** Verified gaps in the code
today:

- Protocol version pinned to `2024-11-05` (`MCPServer.swift:8`).
- `tools/list` emits only `name`/`description`/`inputSchema` — the registry **has**
  `outputSchema` and idempotency, but neither reaches the wire (`toolDefinitions()`,
  `MCPServer.swift:409`).
- `structuredContent` is `{"json": "<stringified-json>"}` (`MCPServer.swift:528`) — a string,
  not the typed object the 2025-06-18 spec requires.
- No tool `annotations` (`readOnlyHint`/`destructiveHint`/`idempotentHint`), no `title`.
- `mcp_hello` re-embeds all 61 names **and** the full help sitemap, and already carries a
  **live orphan** — `Quickstart.recommendedAfterHello` hardcodes `team_preflight`
  (`AllnighterCLI.swift:900`), a tool this plan removes. The drift the doc warns about is
  already present.
- Tool errors are flattened to `"code: message"` text; the rich `ErrorEnvelope`
  (`agentAction`, `fixCommand`, `retryable`) is stringified, so the model can't act on it
  without a second call.

**Timing is the whole argument. Zero users** ([[allnighter-mvp-state]],
[[allnighter-foundation-first]]). Pre-launch is the only window where renaming, re-shaping the
wire envelope, and bumping the protocol are **free**. This is a clean cut: no aliases, no
shims ([[allnighter-working-prefs]], [[allnighter-language-cutover]]). We fix the protocol
layer *in the same cut* — not ship a leaner version of the 2024 shape.

**Target (decided): ~30 tools + ~7 resources + 3 prompts, on a 2025-06-18 wire.** The number
falls out of the principles in §3; we chase **wrong-tool rate and per-turn token cost**, not a
magic count.

---

## 0. Primitives: Tools vs Resources vs Prompts — and the client-reality decision

MCP has three client-facing primitives. Using the right one for each capability is the
difference between "lean catalog" and "idiomatic protocol."

- **Tools** — model-controlled *verbs*. Side-effects, mutations, and any read the **agent
  must reach autonomously** to decide its next move. Reliably model-callable on **every**
  client.
- **Resources** — application-controlled *nouns* (URIs). Read-only context the **host** can
  surface or inject. **Client support is uneven**: Cursor's resource support is weak and
  often does not let the *model* fetch a resource autonomously; many clients require the
  *user* to attach one.
- **Prompts** — user-triggered, parameterized templates (slash-commands). Additive; do **not**
  count against the tool cap. Support is good in Claude Desktop, thin elsewhere.

### The decision (first-principles, and it diverges from the louder mentor proposal)

One review proposed moving every read-only getter (`run_get`, `thread_get`, `pending_list`,
`teams_get`, …) to Resources, shrinking Tools to ~13. **We decline that, deliberately**, and
this is the single most important call in v2:

> **Allnighter is an *autonomous* agent operator. Its agent must read live state — run
> status, pending queue, stalls, thread snapshots — without a human in the loop. On the
> client we are most worried about (Cursor, the one with the ~40 cap), the *model* cannot
> reliably fetch a Resource on its own. Moving live-state reads to resources-only would make
> the agent blind on the dominant client. Tools are the lowest-common-denominator that works
> everywhere; for an agent-first product, live reads stay Tools.**

What Resources **are** right for — and where we adopt them — is **static, low-churn contract
data and capability-as-data**, which is genuinely host/context-shaped and is *pure per-turn
tax* when it lives in tool descriptions instead:

- per-tool I/O schemas (today fabricated as dead `tool://*.schema.json` refs in `mcp_hello`),
- the error catalog + per-code recovery rules,
- help topics (today dumped as a full sitemap into every `mcp_hello`),
- the named workflow recipes,
- the project **context pack** (the P9 "capability as data" moat).

This split captures the real win the mentor was reaching for (get static contract bulk **out
of the per-turn prefix**) **without** the catastrophic risk (a blind agent on Cursor). It is
additive, not a tool-count trick: 30 tools is already comfortably under 40.

**Prompts:** adopt 3 (§5C) as an additive convenience that mirrors — never diverges from —
the tool workflows. They are the idiomatic way to expose our SOPs as slash-commands.

**Resource subscriptions / `notifications/resources/updated`:** **deferred, on purpose**
(§11). They are elegant for "wake when the overnight run finishes," but they require
resource-reads to be the agent's path (which we just rejected), add stateful subscription
bookkeeping to a today-stateless stdio server, and have near-zero client consumers in 2026.
The polling contract (`team_result` + `nextPollAfterMs`) already works on every client.
Building speculative protocol features for clients that don't exist is the *inverse* of the
zero-users discipline.

---

## 1. What v1 already got right (lock it in)

- **All names `snake_case`, underscores only** — no dot notation (the bug that broke clients
  in the website.studio audit). Emitted verbatim.
- **Contract-first** — every tool has a CLI projection, typed `outputSchema`, declared error
  set, idempotency rule ([[allnighter-agent-first-schemas]]).
- **P8 (mutating verbs stay distinct), P9 (capability ships as data), the clean cut, and the
  T3 orphan scan** are all kept verbatim. T3 is world-class infra — almost nobody scans
  bidirectionally across hello/help/error-codes/generated artifacts. Keep it.

---

## 2. The two lessons + the protocol layer

- **XTerminal:** subtraction is the discipline; consolidate overlap behind one clear
  `action`/`mode`/`view` param, never a god-tool; guard with hard ratchets.
- **website.studio:** a wire tool is an *address*, a capability is a *power* — many powers,
  few addresses; new power ships as **data**, not as a new wire name.
- **The protocol layer (new in v2):** the address must also be *well-formed* — typed outputs,
  annotations, teachable errors, a router-not-catalog hello, schemas-as-resources. v1 fixed
  *how many* addresses; v2 fixes *how good each address is on the wire*.

---

## 3. Design principles (these pick the surface, not a number)

**Final for implementation.** Deviating means editing this doc with sign-off.

- **P1 — Agent surface ≠ engine/owner surface.** A *tool* exists only if an external agent
  calls it to do the user's job. Owner-only config and internal mechanics leave the catalog
  (§P7). 
- **P2 — Fewer well-named tools, never a god-tool.** Consolidate overlap behind one clear
  `action`/`mode`/`view` param. Every merge must satisfy P5 and the union-schema rule (§7).
- **P3 — Read where you write, with *wire-level* discrimination.** `get`+`list` collapse:
  `id` omitted = summary array; `id` present = full record. **The merged tool's registry
  `outputSchema` MUST be a tagged `oneOf` with a root `"type": "object"`**, not prose — a
  discriminated union hosts can validate when we eventually wire it (§6.7). Bare root-level
  `oneOf` (no `type`) is invalid for strict MCP clients and can zero the entire catalog.
- **P4 — Create is idempotent and absorbs its variants** (PATCH, not PUT); a `dryRun` flag
  absorbs preflight/validate.
- **P5 — Descriptions are routing rules, and the format is enforced.** Every tool description
  follows a fixed template (T9):
  ```
  DOES: <one sentence>
  USE WHEN: <trigger>
  NOT WHEN: <the adjacent tool/condition to pick instead>
  NEXT: <typical follow-up tool>
  ```
  A merged tool additionally carries an **action/mode decision table** (value → when). Merged
  tools inherit *more* routing burden, so their descriptions do more work, not less.
- **P6 — `snake_case`, underscores only, forever** (names `^[a-z][a-z0-9_]*$`, params
  `^[a-z][a-zA-Z0-9]*$`). Never a dot in a client-facing identifier (T2).
- **P7 — Parity preserved; four exact states** (Agent tool / CLI-only owner-admin /
  Engine-only / Removed). Demoting owner config off the catalog is not a parity loss; agents
  are already readers-not-approvers for config ([[allnighter-default-model-tiers]]).
- **P8 — Irreversible / lane-unsafe / different-trust-class operations stay deliberate.**
  Ambiguity on the mutating path is never traded for tool-count
  ([[allnighter-pending-execute-lane-safety]]). **v2 correction:** this principle forbids the
  v1 plan to fold `team_ask` (non-mutating answer) into `team_run` (may dispatch a mutating
  worker) — they are different *trust boundaries*, not just different params. Re-split (§5).
- **P9 — New capability ships as data, not as ABI.** A new power is a registry behavior / enum
  value / context-pack field — never a new `tools/list` name. The context pack has its **own**
  contract and size ratchet (§6.5) so the moat doesn't itself become a fat blob.
- **P10 — Naming topology = namespace (new).** Prefix clusters the model's mental map and is
  an explicit invariant: `teams_*`/`skills_*` = catalog CRUD; `team_*` = execution lifecycle;
  `thread_*`/`pending_*`/`project_*`/`stalled_*` = domain nouns. Every tool also carries a
  human `title` ("List teams", not `teams_get`) for host UIs (T7).
- **P11 — Wire conformance is part of the contract (new).** The registry's `outputSchema`,
  idempotency, and read/destructive nature MUST be projected onto the response envelope
  (typed `structuredContent`, `annotations`, `title`) on the 2025-06-18 protocol.
  **`outputSchema` on `tools/list` is deferred until T7.7 passes** (§6.7) — the registry and
  `allnighter://schemas/{tool}` resources own the typed contract; aspirational wire
  `outputSchema` that breaks Cursor is not conformance, it is an outage.

---

## 4. Behavioral contracts for merged tools

- **`teams_get` / `skills_get` (P3):** id omitted → lane-scoped summary array; present → full
  record; `detail:"definition"` → round-trippable `TeamPreset`. No-arg `teams_get` also
  returns per-lane defaults (absorbs `team_show`). Output is a tagged `oneOf` (summary | full
  | definition | defaults).
- **`teams_edit` / `skills_edit` = PATCH, `action`-dispatched.** teams `action ∈ {save,
  duplicate, set_default, delete, restore}`; skills `{save, duplicate, delete}`. `save`
  partial-merges; lab-team typeTag + lane-match invariants enforced unchanged.
- **`team_ask` (kept separate — non-mutating answer class).** Runs a lane/answer team on a
  prompt; returns a board/synthesis. Never takes the write lock, never the execution lane.
- **`team_run` (mutating execution class).** Project-scoped; may dispatch one mutating worker
  under the execution lane. Description states the trust boundary explicitly. (Async variant:
  `team_start`/`team_result`/`team_cancel`.)
- **`team_start` absorbs preflight via `dryRun:true`** (resolve against the ready bench, spend
  nothing, take no lane). Stays `keyed`.
- **`team_result` absorbs `team_status`:** running → lightweight state + `nextPollAfterMs`;
  terminal → full `TeamRunJSON`. Output `oneOf(running | terminal)`.
- **`run_get` absorbs `show`+`spec_get`+`floor_show`:** key by run id/`latest`,
  `view ∈ {summary, spec, floor}`, output `oneOf` per view. `history` stays separate (search).
- **`pending_list` absorbs `pending_show`+`pending_queue`** (`pendingId` → one; `mode:"queue"`
  → armed-queue bundle). **`pending_edit` stays separate** (v2 correction: fattest schema +
  distinct "mutate content" mental model; folding it would also breach §7 union-schema).
  **`pending_update`** absorbs the thin state/position transitions submit/cancel/reorder
  (`action ∈ {submit, cancel, reorder}`). `pending_run` stays separate (executes).
- **`thread_get` absorbs `thread_status`+`thread_attachment_get`** (base → snapshot incl.
  running/attention; `attachmentId` → that attachment). `thread_send`/`thread_rename` stay.
- **`stalled_list` absorbs `project_stalled`** (`project` optional). **`stalled_update`**
  absorbs check/keep-waiting/dismiss (`action ∈ {check, wait, dismiss}`).
- **`project_get` absorbs `project_list`** (id omitted → list). **`project_workers` absorbs
  `project_recheck_workers`** via `refresh:true` (safe probes only; never auto-config/auth —
  [[allnighter-cli-setup]], [[allnighter-no-api-keys]]). **`project_context` stays a tool**
  (autonomous fetch) **and is dual-exposed as a resource** (§5B) — the one justified dual,
  because it is the explicit P9 moat.
- **`help` absorbs `help_search`+`help_get`** (`query` → search; `topic`/`ref`/`tool`/`error`
  → fetch). Low-stakes, self-correcting selector; kept merged. Help *content* is additionally
  a resource (§5B) so it leaves the per-turn prefix.
- **Pagination (cross-cutting, all list tools — P3 extended):** every list (`teams_get` no-arg,
  `skills_get`, `history`, `pending_list`, `stalled_list`, `project_get` no-arg) takes an
  optional `limit` (default 25) + `cursor`, and returns `nextCursor` in structured output.
  Lists return **summaries**; the by-id form returns the full record.

---

## 5. The target surface (61 → 30 tools + 7 resources + 3 prompts)

### §5A — MCP Tools (30)

```
Bootstrap & recovery (6): mcp_hello, doctor, error_explain, help, defaults_get, history
Catalog (4):              teams_get, teams_edit, skills_get, skills_edit
Execution (6):            team_ask, team_run, team_start, team_result, team_cancel, run_get
Pair executor (2):        pair_run, pair_status
Threads (3):              thread_send, thread_get, thread_rename
Pending (4):              pending_list, pending_edit, pending_update, pending_run
Stalled (2):              stalled_list, stalled_update
Projects (3):             project_get, project_context, project_workers
```

vs v1's 28: **+`team_ask`** (P8 trust-boundary re-split) and **+`pending_edit`** (§7 schema
re-split). Both buy *fewer wrong-action retries* — the metric that matters — for two tools we
have ample cap room for.

### §5B — MCP Resources (7, all static-contract or capability-as-data)

| Name | URI template | Represents |
|------|--------------|------------|
| Contract manifest | `allnighter://contract` | Surface manifest + `contractVersion` + `contractHash` (agents detect stale cached schemas). |
| Tool schema | `allnighter://schemas/{tool}` | One tool's I/O JSON schema (replaces the dead `tool://*.schema.json` refs). |
| Error catalog | `allnighter://errors` | Index of all error codes. |
| Error rule | `allnighter://errors/{code}` | One code's recovery rule (`agentAction`, `fixCommand`, who-fixes). |
| Help topic | `allnighter://help/{topic}` | One help topic (sitemap leaves `mcp_hello`). |
| Workflow recipes | `allnighter://workflows` | The named recipes `mcp_hello.workflows` points at. |
| Project context | `allnighter://projects/{projectId}/context` | The capability-as-data pack (dual with the `project_context` tool). |

**No live mutable state is a resource.** Runs, threads, pending, stalls, catalogs, defaults
stay Tools so the autonomous agent reaches them on every client (§0).

### §5C — MCP Prompts (3, additive; mirror the tool workflows)

- `run-sprint` *(args: project, lane, prompt)* — check defaults → read project context →
  `team_start(dryRun)` → `team_start` → surface `team_result`.
- `diagnose-environment` — `doctor` (full) → `error_explain` the failures → propose fixes.
- `resolve-stalls` *(args: project?)* — `stalled_list` → guide `stalled_update(check)` →
  ask user to `wait`/`dismiss`.

### §5D — CLI-only (owner admin, off the agent catalog — §A/P7)

`boost_window_show`, `boost_window_set`, `boost_window_seed`,
`boost_window_observations_clear`. The read stays visible to agents through `doctor`.

**Guard against a shadow surface:** CLI-only is for genuine owner-admin, not an escape hatch
to dodge the cap. The orphan scan (T3) treats CLI-only names as a closed, enumerated set in
§5D — adding one is a reviewed act, same as adding a tool.

---

## 6. Guardrails (ratchets that prevent recurrence)

`MCPToolContractTests`/`MCPParityTests` today check metadata only. Add T1–T9.

- **T1 — Count caps.** `mcpTools.count ≤ 32` (target 30, 2 slots headroom);
  `mcpResources.count ≤ 12`; `mcpPrompts.count ≤ 4`. Each constant carries the comment:
  *"Raising this requires editing MCP_Tool_Upgrade.md §3 first — guardrail, not a budget."*
- **T2 — Naming invariant.** names `^[a-z][a-z0-9_]*$`; params `^[a-z][a-zA-Z0-9]*$`; resource
  URIs `^allnighter://`. Makes dot-notation structurally impossible.
- **T3 — No orphan names (highest value).** No string anywhere references a tool/resource name
  not in the registry. Inverse-scan: `mcp_hello` payload (incl. `nextToolPlan`/`workflows`),
  `AgentReadiness`, `HelpService`, `docs/generated/alln/mcp-tools.json`, error-code
  `agentAction` strings, `AGENTS.md`, CLI agent system prompt. **First catch: the
  `team_preflight` reference in `Quickstart` (`AllnighterCLI.swift:900`).**
- **T4 — Bidirectional parity.** Parity-table key set **equals** `mcpTools` names; every
  Agent tool has a CLI path and vice-versa.
- **T5 — Schema-weight ratchet (input).** No tool's serialized `inputSchema` + description
  exceeds `MAX_TOOL_SCHEMA_CHARS`, calibrated to today's heaviest at Slice 0, monotonically
  decreasing. Each merge survivor ≤ the largest single tool it replaces ("union ≤ prior
  worst"). `thread_send` (~24 error codes) sets the ceiling and is trimmed at Slice 0 (§7).
- **T6 — `mcp_hello` is a router, not a catalog.** Assert the payload contains **no** full
  tool roster and **no** full help sitemap. It carries (§6.4): `nextToolPlan` (one structured
  next step), `workflows` (3–5 named recipes), `contractHash`, and live readiness — and is
  **state-invariant on `tools/list`** (presence never encodes readiness/auth/project; T7).
- **T7 — Wire conformance (new — the v2 core).** A conformance test asserting, for the emitted
  wire (not just the registry):
  1. `protocolVersion == "2025-06-18"`.
  2. every tool descriptor emits a `title` and `annotations` mapped from registry metadata:
     `readOnlyHint` for non-mutating reads; `destructiveHint`+`openWorldHint` for
     `team_run`/`pending_run`/`thread_send`/`pair_run`; `idempotentHint` from the idempotency
     rule (**keyed ≠ idempotent** → `team_start.idempotentHint == false`).
  3. **`tools/list` does NOT emit `outputSchema` until T7.7 is green** (§6.7). Registry +
     `allnighter://schemas/{tool}` carry the typed contract instead.
  4. success `structuredContent` is the **typed object** matching the registry `outputSchema` —
     never `{"json": "<string>"}` (fixes `MCPServer.swift:528`).
  5. error responses emit the full `ErrorEnvelope` as typed `structuredContent` (not a
     flattened string), enriched with `nextTool` + `helpRef: alln://errors/{code}` so the
     model recovers in-turn without a second call (§6.6).
  6. merged read tools (`teams_get`, `team_result`, `run_get`, `pending_list`, `thread_get`)
     registry schemas are tagged `{"type":"object","oneOf":[…]}` unions (P3) — ready for a
     future wire emit once T7.7 passes.
- **T7.7 — Cursor `tools/list` schema compat (new — launch blocker for wire `outputSchema`).**
  Cursor's MCP client validates `outputSchema` on every tool in `tools/list` **strictly** and
  **silently drops the entire tool list** when any single descriptor fails (green connected,
  0 tools in UI, empty local `tools/*.json` cache — same class as Ikiro Phase 50,
  [Cursor forum #160620](https://forum.cursor.com/t/mcp-server-connected-green-dot-and-tools-discovered-in-logs-but-0-tools-in-ui-and-agent/160620)).
  Until this ratchet passes:
  - **Do not** put `outputSchema` on `tools/list` (structured responses already live in
    `structuredContent`; schema resources are the contract surface).
  - When we opt in later, every wire `outputSchema` MUST have a root `"type": "object"` —
    never bare root `oneOf` / `anyOf` (invalid_literal at `outputSchema.type` zeros the list).
  - CI asserts the serialized `tools/list` payload passes the same strict validation Cursor
    uses (golden fixture + per-tool schema lint).
  - `alln mcp doctor --client cursor` verifies **registered tool count > 0**, not just that
    the server returned N tools over the wire.
- **T8 — Golden agent traces (new — the launch proof).** Check-in a fixture per workflow; CI
  replays the tool-call sequence. The canonical trace:
  `mcp_hello → help(topic) → team_start(dryRun) → team_start → team_result → run_get`.
  Slices cannot silently regress discovery order. (Subsumes/upgrades MCP-Help H5.)
- **T9 — Description template lint.** Every tool description matches the P5 template
  (DOES/USE WHEN/NOT WHEN/NEXT); every merged tool's description contains its action/mode
  decision table; every tool's `title` is non-empty and distinct.

Run: `swift test --package-path Packages/AllnighterCore` + the repo proof wall
([[allnighter-conventions]]).

### 6.4 `mcp_hello` router contract (replaces the roster echo)

```jsonc
{
  "schemaVersion": 2,
  "contractVersion": "…", "contractHash": "…", "binaryVersion": "…",
  "canStartTeamRun": true,
  "nextToolPlan": { "tool": "team_start", "args": { "dryRun": true }, "reason": "…" },
  "workflows": [ { "id": "run_async", "steps": ["team_start","team_result","run_get"] }, … ],
  "readiness": { "readyTeams": […], "blockedReason": null }
}
```
No `tools: [...]` roster. No `helpTopics` sitemap (point to `help` / `allnighter://help/*`).
When blocked, `nextToolPlan.tool` is **always** `doctor` first — the agent never relies on a
tool being *absent* to know it's blocked (resolves the T6-vs-conditional-capability tension).

### 6.5 `project_context` contract (the P9 moat made concrete)

The pack has its own versioned schema and **its own T5-style size ratchet** (a fat context
blob re-bloats as fast as tool schemas). Required shape:
- `schemaVersion`, `generatedAt`, `binaryVersion` (freshness).
- sections: `runnableTeams`, `admissionHints`, `pendingCapacity`, `installedWorkers`,
  `featureFlags`.
- **invalidation rule (decided):** re-fetch after a mutating `team_run`/`pending_run` in the
  project, or after `doctor` changes source health — **not** mid-thread on every turn. The
  rule ships in the pack description so agents cache correctly.

### 6.6 Error envelope on the wire

The `ErrorEnvelope` already carries `agentAction`/`fixCommand`/`retryable`/`requiresManual`.
The fix is wire serialization: emit it as typed `structuredContent.error` (object), add
`nextTool` (derived from `ErrorHelpBridge`) and `helpRef: "alln://errors/{code}"`. The
`text` content stays a one-line human summary.

### 6.7 Cursor `outputSchema` rejection — do not repeat Ikiro Phase 50

**Applies to Slice 0+.** Today Allnighter is *safe*: `toolDefinitions()` emits only
`name`/`description`/`inputSchema` (`MCPServer.swift:409`) — no wire `outputSchema`, so
Cursor registers all ~61 tools. **The planned upgrade would regress** if Slice 0 blindly
projects registry `outputSchema` onto `tools/list` the way Ikiro's Phase 50 wire ABI did.

**Observed failure mode (Ikiro, 2026-06-27):**

| Signal | Meaning |
|--------|---------|
| MCP server green / connected | Transport + auth OK |
| `tools/list` HTTP 200, N tools, ~10KB | Server is fine |
| Cursor UI: "No tools" / agent has 0 MCP tools | Client rejected the list |
| Local MCP cache: only metadata, no `tools/*.json` | Parse/validation never succeeded |

**Root cause class:** strict client validation of `outputSchema` on `tools/list`. One bad
descriptor → **entire list dropped**, not N−1. Common trigger: root-level `"oneOf": […]`
without `"type": "object"` (same bug class as
[claude-code#10031](https://github.com/anthropics/claude-code/issues/10031)).

**Allnighter-specific risk:** v2 plans tagged `oneOf` outputs for merged reads (P3/T7.6) and
nullable unions in `ContractSchema` (`nullableRef` uses bare `oneOf`). Projecting those verbatim
onto `tools/list` without a root `type: object` wrapper would zero the catalog on Cursor —
our primary client (§0).

**Decided guardrails (implementation):**

1. **Slice 0 ships typed `structuredContent`, `title`, `annotations`, enriched errors — not wire
   `outputSchema`.** Schemas live in the registry + `allnighter://schemas/{tool}` (§5B).
2. **Wire `outputSchema` is opt-in behind T7.7**, not a Slice 0 deliverable.
3. **If/when we emit wire `outputSchema`:** every tool uses root `"type": "object"`; unions are
   `{"type":"object","oneOf":[…]}`; CI runs Cursor-compat validation on the full list payload.
4. **Never encode "must emit outputSchema on wire" in tests** until T7.7 exists — that test
   pattern is what shipped the Ikiro regression.

**Debug when suspected:** Cursor MCP Logs (`Cmd+Shift+U`) → `Error listing tools` /
`invalid_literal` at `outputSchema.type`. Direct `tools/list` against `alln mcp serve` proves
server vs client.

---

## 7. Per-merge safety rule (applied during the cut)

Each survivor's serialized schema ≤ the largest single tool it replaces (T5). Pre-decided:
- **`thread_send`** sets the ceiling (~24 codes + nested `oneOf` arrays). Trim at Slice 0:
  keep routing-critical codes inline; move the long attachment/file-reference failure catalog
  to `error_explain` + `allnighter://errors/*` (the description points there).
- **`pending_edit`** is **already split out** in v2 (not a fallback) — it is the fattest
  pending member.
- **`teams_edit`** reads already live on `teams_get`; if still over budget, move `restore`
  (least-used) to its own tool, staying ≤32.

---

## 8. Implementation contract (Swift)

**`ContractRegistry`** gains two arrays alongside `mcpTools`:
```swift
public var mcpResources: [MCPResourceSpec]   // uriTemplate, name, title, description, mimeType
public var mcpPrompts:   [MCPPromptSpec]      // name, title, description, arguments: [Param]
```
`MCPToolSpec` gains projected wire fields (computed from existing metadata, not re-authored):
`title`, and an `annotations` derivation (`readOnly`/`destructive`/`idempotent` from
`idempotency` + a `mutates` flag).

**`MCPServer.serve()`** advertises and routes the new primitives:
```swift
"capabilities": ["tools": [:], "resources": [:], "prompts": [:]]   // subscribe: deferred (§11)
// + cases: resources/list, resources/read, prompts/list, prompts/get
```
`toolDefinitions()` emits `title`, `annotations`; **`outputSchema` omitted until T7.7** (§6.7).
`toolText(...)` returns typed `structuredContent` (decode the JSON string to an object before
embedding).
`respondToolError(...)` emits the full enriched `ErrorEnvelope` object.

**Protocol bump:** `protocolVersion = "2025-06-18"`; `serverInfo.version = "1.0"`.

The underlying engine services (TeamCatalog, ProjectStore, Pending/Stalled/Thread stores) are
**unchanged** — this is a surface + wire pass, not an engine rewrite.

---

## 9. Rollout: two slices, not six (zero users → reviewability is the only constraint)

v1's six monotonic slices were user-safety caution we don't need; T3 catches half-migration.
But a single 61→30 + new-wire + resources + prompts PR is unreviewable. Two real slices:

| Slice | Scope | Surface Δ |
|-------|-------|-----------|
| **0 — Foundation** | Bump protocol; emit `title`/`annotations` ( **`outputSchema` deferred — §6.7** ); typed `structuredContent`; enriched error envelope; land T1–T9 + T7.7 cursor-safe wire ratchet calibrated to the **current** surface; rewrite `mcp_hello` to the router shape (kills the `team_preflight` orphan); trim `thread_send` (T5). | 0 tools (wire-only) |
| **1 — Atomic cut** | The full tool merge 61→30 + the 7 resources + 3 prompts + `project_context` contract, in one atomic commit: registry, `MCPServer` dispatch, CLI projections, regenerated `mcp-tools.json`, all embedded refs (T3), tests + golden traces (T8). | −31 → 30 tools, +7 resources, +3 prompts |

Slice 0 lands the correct wire *first* so the merges in Slice 1 are authored on conformant
rails. Each slice: build + full suite green; commit each step ([[allnighter-working-prefs]]).

---

## 10. Proof / launch gate

1. Repo proof wall green (T1–T9 + T3 orphan scan).
2. `MCPToolContractTests`/`MCPParityTests` extended to the 30-tool surface + resources/prompts.
3. Wire conformance test (T7) green: protocol `2025-06-18`, typed `structuredContent`,
   `title`/`annotations` present; **no wire `outputSchema` unless T7.7 green**; registry
   merged-read unions are `type:object` + `oneOf`.
4. `mcp_hello` re-inspected (T6): no roster, no sitemap, `nextToolPlan` routes to `doctor`
   when blocked, state-invariant `tools/list`.
5. Contract export (`docs/generated/alln/mcp-tools.json` + new resource/prompt manifests)
   regenerated via the export path, diffed clean.
6. **Golden traces (T8)** checked in and replaying green — the real "world-class" proof.
7. **`alln mcp doctor --client cursor`** (new, ship it): verifies the connected tool count is
   under the client cap, **that Cursor actually registered tools (not 0 after a green
   connect — §6.7)**, and the handshake advertises resources/prompts — a programmatic guard
   against silent truncation and `outputSchema` rejection, beside manual Cursor + Claude smoke.
8. **`alln mcp install --target cursor|claude`** prints the exact config **plus tool count +
   contract hash**, so connect is frictionless and verifiable.

---

## 11. Deliberately deferred (decided, with rationale — do not re-litigate)

- **Resource subscriptions** (`resources/subscribe`, `notifications/resources/updated`).
  Requires resource-reads to be the agent path (rejected, §0); adds stateful bookkeeping to a
  stateless stdio server; ~zero client consumers in 2026. Revisit when a client we target
  ships model-driven subscription reads. Polling (`team_result`/`nextPollAfterMs`) is the
  supported path until then.
- **Dual-exposing live state (runs/threads/pending) as resources.** Nice host-UI sugar, but
  Allnighter already has its own Mac GUI for humans, and it doubles the surface + test burden.
  The tools are the contract. Reconsider only if a targeted client proves model-driven
  resource reads.
- **Marketplace/`server.json` registry listing.** After launch; `alln mcp install` covers
  connect today.

---

## 12. What we took from review, and what we declined (durable, so it isn't re-argued)

**Taken (gems):** wire conformance as a first-class layer (T7); typed `structuredContent` +
`annotations`/`title` + protocol bump; **wire `outputSchema` deferred behind T7.7** (§6.7,
Ikiro lesson); `mcp_hello` as router with
`nextToolPlan`/`workflows`/`contractHash` (T6); enforced description template (P5/T9);
re-split `team_ask` from `team_run` (P8) and `pending_edit` from `pending_update` (§7);
naming topology P10; `project_context` contract + size ratchet (§6.5); pagination rule;
enriched error envelope (§6.6); resources for **static contract + context** (§5B); 3 prompts
(§5C); golden traces as launch proof (T8); two slices not six (§9); `alln mcp doctor/install`
(§10); discriminated `oneOf` outputs (P3/T7.6).

**Declined (with reason):**
- **Move live-state reads to Resources, Tools→13.** Breaks the autonomous agent on Cursor,
  the client we most need to work (§0). The real win (static-contract offload) is captured by
  §5B without the risk.
- **Resource subscriptions now.** Speculative, no consumer, stateful (§11).
- **Single all-in-one PR.** Unreviewable; Slice 0 must land the wire first (§9).
- **Chase 13/15/25 as the count.** The metric is wrong-tool rate + token cost, not a number;
  30 with conformant wire beats 13 with a 2024 envelope.

---

## 13. Appendix — full disposition ledger (all 61)

`survivor` = stays a tool. `CLI-only` = §5D. `→ X` = merged into X. `+resource` = also/instead
exposed under §5B. New tools created by a merge (`teams_get`, `teams_edit`, `skills_get`,
`skills_edit`, `run_get`, `pending_update`, `stalled_update`, `help`) are named in the rows
they absorb.

| # | Tool (today) | Disposition | Slice |
|---|--------------|-------------|:----:|
| 1 | `mcp_hello` | survivor → router shape (drops roster+sitemap; +`contractHash`) | 0 |
| 2 | `teams_list` | → `teams_get` (new) | 1 |
| 3 | `teams_show` | → `teams_get` | 1 |
| 4 | `teams_definition` | → `teams_get` (`detail`) | 1 |
| 5 | `teams_duplicate` | → `teams_edit` (new) | 1 |
| 6 | `teams_save` | → `teams_edit` | 1 |
| 7 | `teams_set_default` | → `teams_edit` | 1 |
| 8 | `teams_delete` | → `teams_edit` | 1 |
| 9 | `teams_restore` | → `teams_edit` | 1 |
| 10 | `skills_list` | → `skills_get` (new) | 1 |
| 11 | `skills_show` | → `skills_get` | 1 |
| 12 | `skills_duplicate` | → `skills_edit` (new) | 1 |
| 13 | `skills_save` | → `skills_edit` | 1 |
| 14 | `skills_delete` | → `skills_edit` | 1 |
| 15 | `team_preflight` | → `team_start` (`dryRun`) | 1 |
| 16 | `team_start` | survivor (absorbs preflight; `idempotentHint:false`) | 1 |
| 17 | `team_status` | → `team_result` | 1 |
| 18 | `team_result` | survivor (absorbs status; `oneOf` output) | 1 |
| 19 | `team_cancel` | survivor | — |
| 20 | `team_run` | survivor — **mutating class** (P8) | 1 |
| 21 | `pair_slice` | → `pair_run` | 1 |
| 22 | `pair_run` | survivor (absorbs pair_slice) | 1 |
| 23 | `pair_status` | survivor | — |
| 24 | `team_ask` | **survivor — non-mutating class (v2 re-split, P8)** | 1 |
| 25 | `team_show` | → `teams_get` (no-arg) | 1 |
| 26 | `history` | survivor (+pagination) | 1 |
| 27 | `show` | → `run_get` (new, `view:summary`) | 1 |
| 28 | `doctor` | survivor (absorbs boost-window read) | 1 |
| 29 | `error_explain` | survivor (+`allnighter://errors/*` resource) | 0 |
| 30 | `spec_get` | → `run_get` (`view:spec`) | 1 |
| 31 | `floor_show` | → `run_get` (`view:floor`) | 1 |
| 32 | `thread_send` | survivor (T5 trim at Slice 0) | 0 |
| 33 | `thread_get` | survivor (absorbs status + attachment) | 1 |
| 34 | `thread_rename` | survivor | — |
| 35 | `thread_status` | → `thread_get` | 1 |
| 36 | `thread_attachment_get` | → `thread_get` (`attachmentId`) | 1 |
| 37 | `pending_list` | survivor (absorbs show + queue; +pagination) | 1 |
| 38 | `pending_show` | → `pending_list` (`pendingId`) | 1 |
| 39 | `pending_queue` | → `pending_list` (`mode:queue`) | 1 |
| 40 | `pending_submit` | → `pending_update` (new) | 1 |
| 41 | `pending_edit` | **survivor — kept separate (v2, §7)** | 1 |
| 42 | `pending_reorder` | → `pending_update` | 1 |
| 43 | `pending_cancel` | → `pending_update` | 1 |
| 44 | `pending_run` | survivor | — |
| 45 | `project_stalled` | → `stalled_list` (`project`) | 1 |
| 46 | `stalled_list` | survivor (absorbs project_stalled) | 1 |
| 47 | `stall_check_status` | → `stalled_update` (new, `action:check`) | 1 |
| 48 | `stall_keep_waiting` | → `stalled_update` (`action:wait`) | 1 |
| 49 | `stall_dismiss` | → `stalled_update` (`action:dismiss`) | 1 |
| 50 | `project_list` | → `project_get` | 1 |
| 51 | `project_get` | survivor (absorbs project_list) | 1 |
| 52 | `project_context` | survivor **+ `allnighter://projects/{id}/context` resource** | 1 |
| 53 | `project_workers` | survivor (absorbs recheck via `refresh`) | 1 |
| 54 | `project_recheck_workers` | → `project_workers` (`refresh`) | 1 |
| 55 | `defaults_get` | survivor | — |
| 56 | `boost_window_show` | CLI-only (§5D; read via doctor) | 0 |
| 57 | `boost_window_set` | CLI-only (§5D) | 0 |
| 58 | `boost_window_seed` | CLI-only (§5D) | 0 |
| 59 | `boost_window_observations_clear` | CLI-only (§5D) | 0 |
| 60 | `help_search` | → `help` (new) +`allnighter://help/*` | 1 |
| 61 | `help_get` | → `help` +`allnighter://help/*` | 1 |

**Reconciliation:**
- **22 survivors keep an existing name:** mcp_hello, team_start, team_result, team_cancel,
  team_run, team_ask, pair_run, pair_status, history, doctor, error_explain, thread_send,
  thread_get, thread_rename, pending_list, pending_edit, pending_run, stalled_list,
  project_get, project_context, project_workers, defaults_get.
- **8 new survivors from merges:** teams_get, teams_edit, skills_get, skills_edit, run_get,
  pending_update, stalled_update, help.
- **4 demoted to CLI-only:** boost_window_show/set/seed/clear.
- **27 removed names merged into survivors.**

`22 + 8 = ` **30 tools.** ✔  (61 − 4 CLI-only − 27 merged = 30.)
Plus **7 resources** (§5B) and **3 prompts** (§5C).

---

## 14. Cross-doc updates (Slice 1, same commit)

- `AGENTS.md`: repoint MCP work here; rewrite tool lists to the 30-tool + resources surface.
- `docs/phases/MCP_Agent_First_Contract.md`: rewrite to the 30-tool surface + the
  resources/prompts primitives.
- Update [[allnighter-mcp-help]] / [[allnighter-agent-first-schemas]] memory pointers once
  landed (help_search/help_get → help; H5 golden-trace superseded by T8; new surface count).
