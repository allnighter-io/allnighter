# RB6 - Council-as-Tool (local MCP / CLI / HTTP)

Status: **BUILT (engine + CLI + MCP) — Core+Engine green; HTTP/WS loopback stubbed. (orchestration run)**
Owner: Shared Core + Engine + Mac
Created: 2026-06-14
Updated: 2026-06-14
Depends on: 06 (the council foundation: `Worker`, `PlanAnalysis`, `StageOutput`,
the headless engine). Exposes richer presets as RB1–RB3 land, but needs only 06.

## The moat (why this is huge)

OpenRouter's Fusion is a **cloud API you pay per token for**, invoked as a server
tool the base model calls on hard questions. Allnighter already runs the same
panel→judge→plan pattern **locally, on the user's machine, through CLIs they
already pay a flat rate for — zero marginal cost.**

RB6 turns that into the unfair advantage: **expose Allnighter's council as a local
tool that *any* terminal coding agent can call mid-task.** A vibe coder is deep in
Claude Code (or Codex, or Grok) building a feature, hits a real architectural fork,
and the agent itself calls:

```text
team_ask("Should the run store be an actor or a serialized queue here?")
```

Allnighter fans the question out to the local panel, runs the structured judge,
and hands back a decision-grade answer with consensus/contradictions/blind spots —
in seconds, for **$0 of additional API cost**. The agent uses it and keeps
building. The human never switched windows.

> **Local Fusion, callable by every agent on the machine, at zero marginal cost.**
> Fusion is a feature you rent. Allnighter becomes the judgment layer the whole
> machine runs on, that the user already owns.

This is what makes Allnighter impossible to remove: it stops being "a thing you
open before coding" and becomes **infrastructure every agent quietly leans on.**

## Goal

Expose the council as a tool any local agent can invoke, over three transports
that share **one engine** (no logic duplicated):

1. **CLI** — `alln team "<question>"`: universal. Every coding agent has a
   shell tool, so this works with *anything*, no integration required.
2. **MCP server** — `allnighter mcp`: first-class structured tool for MCP-aware
   agents (Claude Code, and the growing MCP ecosystem). Returns structured
   `PlanAnalysis`, not just text.
3. **Local HTTP/WebSocket** — `allnighter serve` (or hosted by the Mac app):
   programmatic access and the same transport seam iOS will use (`00` §10).

Judgment in, spec out. The tool **never writes code, runs git, or dispatches an
executor** — it answers, analyzes, and (with deeper presets) produces a spec. The
calling agent does the building.

## Non-Goals (hard boundaries)

- **No git, worktrees, branches, commits, landing, or code execution.** RB6 is
  *judgment only.* Direct executor dispatch stays the separate, explicit, GUI-gated
  action (`RB4`). (Founder directive: the entire git-management surface stays out.)
- **No API keys, no cloud, no token cost.** The tool only invokes the user's
  already-authenticated CLIs — the zero-marginal-cost law (`00` §9) is absolute.
- **No network egress** beyond `localhost` and the CLIs' own auth. No remote/
  internet exposure, no multi-user. (iOS-over-Tailscale is a separate existing
  seam, not this.)
- **No general RPC / no DAG.** A fixed council tool surface, mirroring the rest of
  the milestone's "no general workflow engine" discipline.
- **No auto-registration.** Allnighter never wires itself into another agent's tool
  config without explicit user consent.
- **No new heavy dependencies** (`00` §2): a thin JSON-RPC-over-stdio handler for
  MCP and the already-planned Hummingbird server for HTTP; nothing else.

## Product Laws (carried forward + new for the tool)

- **Recursion is impossible.** A council worker can never trigger a nested council
  (see Recursion Guard). Mirrors Fusion's recursion protection.
- **Shape before commit.** Every tool result reports observed `invocations`; a governor caps
  concurrent councils; the CLI/MCP lists preset **work shape** via `WorkOrder.summary`
  before committing. No pre-run cost/time estimates.
- **Localhost-only + authenticated.** HTTP binds `127.0.0.1` only and requires a
  per-session bearer token; MCP is a user-spawned stdio child (no socket).
- **Injection-safe.** Tool input reaches workers as `argv`/stdin, never shell-
  concatenated (`00` §9), exactly like GUI prompts.
- **Honest + visible.** Tool-invoked runs are first-class `TeamRun`s, origin-
  tagged, persisted to the same `Runs/` store, and surfaced in the Mac app's
  history so the user sees exactly what their agents asked and got.
- **Judgment only.** The tool has no capability to write files, run git, or invoke
  the executor. Capability boundary enforced in code, not just convention.
- **Graceful degradation.** Partial panels and unhealthy workers are reported
  (Doctor), never silently downgraded.

## Architecture (one engine, thin transports)

```text
   terminal agent (Claude Code / Codex / Grok / Cursor / any shell)
        |                      |                         |
   shell: `alln team`   MCP stdio (JSON-RPC)   HTTP/WS (127.0.0.1 + token)
        |                      |                         |
        +----------+-----------+------------+------------+
                                |
                   +------------v-------------+
                   |   TeamService (actor) |   one entry: request -> TeamRun
                   |   - recursion guard       |
                   |   - TeamGovernor cap   |
                   |   - origin tagging        |
                   +------------+-------------+
                                |
            existing engine: TeamRunCoordinator + PlanWriter (06)
                                |
              Runs/  (shared store, single source of truth)  +  RunEvent stream
                                |
                   Mac app observes Runs/ -> live "tool activity" + history
```

The CLI and MCP server run the engine **in-process** (they link `AllnighterEngine`,
read the same `Config/`, write the same `Runs/`). They do **not** require the Mac
app to be running — a terminal-first user gets the tool with the GUI closed. When
the Mac app *is* open, it observes the shared `Runs/` folder (and/or the local
server's event stream) and shows tool runs live. Cross-process concurrency is
governed by a file-based semaphore (below), so caps hold whether the CLI, MCP
server, and app run councils together or apart.

## The Tool Surface (operations)

A small, fixed set of operations, identical across MCP and HTTP (the CLI maps to
them as subcommands):

| Operation | Purpose |
| --- | --- |
| `team_presets` | List exposed presets + each one's work shape (`WorkOrder.summary`). |
| `team_ask` | Run a council and return the result. Optional `waitSeconds` is a **client timeout** only — may return a `runId` to poll; never branches on a predicted duration. |
| `council_start` | Kick off a council asynchronously; return a `runId` immediately. |
| `council_status` | `{ runId } -> { status, seatsDone/total, stage, invocations }`. |
| `council_result` | `{ runId } -> TeamToolResult`. |
| `team_recall` | **Read-only**, zero-cost: search prior councils and return past judgments (with dates). The council *remembers* — reuse a prior decision without spending a call. |

`team_ask` may honor `waitSeconds` as a pure client timeout (return `runId` to
poll if the run is still in flight). It does **not** compare against a predicted
duration or return an ETA.

**`team_recall` semantics (v1, no index needed):** case-insensitive keyword/
substring match over `TeamRun.prompt` across `Runs/` (excluding the `Evals/`
corpus), ranked **most-recent-first**, returning the top *K* (default 5) **complete**
runs as compact `{ runId, prompt, createdAt, plan-excerpt }`. **Each result
carries `createdAt`** so the agent can judge staleness (acting on a 6-month-old
decision unknowingly is a silent correctness bug). "No match" returns an empty list,
not an error. Pure local read — no engine spin-up, zero calls. (A semantic index is
a later, optional upgrade; the substring v1 is honest and sufficient.)

### Result shape (structured, for agents)

```text
TeamToolResult
- runId
- origin                 # mcp | cli | http
- preset
- status                 # complete | partial | failed
- createdAt              # so a recalled/old result's age is visible
- plan: String?    # the plan
- finalSpec: String?     # nil until RB3 ships (review/final-spec presets)
- analysis: PlanAnalysis # consensus/contradictions/uniqueInsights/blindSpots/failedWorkers (06)
- partials: [WorkerFailure] # honest: which seats didn't answer
- contextTruncated: Bool  # the caller's context snippet was clipped to contextByteLimit
- invocations: Int        # observed worker/stage invocations after the run
- note: String            # refusal/status reasons only (not estimates)
```

MCP returns this as structured tool output (plus a Markdown rendering for display).
The CLI prints Markdown by default and the full object under `--json`.

## Core Types (contract-first, `AllnighterCore`)

Each ships a fixture + round-trip test (`00` §8). Foundation-first: final shapes,
no shims.

```text
RunOrigin : gui | cli | mcp | http        # DEFINED IN PHASE 06 (06 owns the type + TeamRun.origin)
                                            # RB6 only SETS origin = cli|mcp|http; it adds no field.

TeamRequest                            # the normalized tool input
- question: String
- presetId: String?                       # default from ToolConfig; must be in exposedPresetIds
- context: String?                        # optional bounded snippet the agent wants considered
- waitSeconds: Int?                       # team_ask client timeout (poll if exceeded)

TeamToolResult                         # see "Result shape" above; finalSpec is nil until RB3 ships
ToolConfig                                # Config/Tool/config.json
- enabledTransports: { cli, mcp, http }
- exposedPresetIds: [String]              # default = the Phase 06 panel presets ONLY (no review/final until RB1-3)
- defaultPresetId: String
- maxConcurrentTeamRuns: Int              # governor cap (default small, e.g. 2)
- maxTeamRunDepth: Int                    # recursion ceiling (default 1)
- httpPort: Int                           # 127.0.0.1 only
- contextByteLimit: Int                   # bound the optional context
- allowSinglePassthroughAtDepth: Bool     # at the ceiling, degrade to one direct answer vs refuse
```

`question`/`context` flow to workers only as `argv`/stdin (injection-safe). The
`context` selector is the `WorkerPrompt` "no longer identical-text-only" growth
seam (`00` §10): truncated to `contextByteLimit` as **head + tail** with an
explicit `[… truncated N bytes …]` marker, and the result tells the caller it was
truncated. Until RB1–RB3 land, `exposedPresetIds` defaults to the Phase 06 panel
presets only and `TeamToolResult.finalSpec` is always nil (review/final-spec
presets light up as those milestones ship).

## Recursion Guard (non-negotiable, fail-closed)

A council's own member/judge CLIs (e.g. `claude`) may have the Allnighter tool
registered globally. Without a guard, a worker calls the council → spawns workers →
call the council — infinite recursion and quota detonation. The guard must hold for
**spawned** clients (CLI/MCP children) *and* an **already-running** HTTP server
(which doesn't inherit a caller's env).

- **Env, for spawned clients.** Every worker subprocess is spawned with
  `ALLNIGHTER_TEAM_DEPTH = depth + 1`. The CLI and MCP entrypoints read it on
  startup; depth `>= maxTeamRunDepth` (default 1) → refuse to fan out (or, if
  `allowSinglePassthroughAtDepth`, return one direct answer). Never a nested panel.
- **HTTP fails closed.** The loopback server cannot read a caller's env, so every
  council-start request **must** carry an `X-Allnighter-Council-Depth` header; all
  Allnighter clients forward their env depth into it. A request with a **missing or
  unparseable** header is treated as **at the ceiling** and refused (fail-closed).
  Additionally, the **session token is scrubbed from every worker subprocess's
  environment**, so a deep worker cannot trivially authenticate to the server at
  all. This closes the *accidental* recursion case completely; deliberate
  adversarial self-recursion (a model forging `depth: 0`) is out of scope and
  bounded anyway by the governor + quota. The audit log flags depth-anomalous calls.

It is the first thing RB6 builds and the first thing its tests prove.

## Concurrency Governance (cost defense, crash-safe)

`TeamGovernor` caps concurrent councils at `maxConcurrentTeamRuns` across
processes (CLI + MCP + app) using **`flock(2)` advisory locks** on slot files under
`Config/Tool/slots/` — not a hand-rolled counter file (which has a TOCTOU race).
`flock` is **auto-released when the holding process dies or closes the fd**, so a
crashed council never leaves a stale lock; a belt-and-suspenders TTL + PID-liveness
sweep reclaims any orphan. Acquiring a slot is atomic. Beyond the cap, a request
queues (async) or returns a clear "busy, N running" status (sync). Every result
reports `invocations`; `team_presets` lists work shape via `WorkOrder.summary`.

## Security & Honesty Posture

- **Localhost only.** HTTP binds `127.0.0.1`; never `0.0.0.0`. MCP is a stdio child
  the agent spawns — no listening socket at all.
- **Bearer token.** HTTP requires a per-launch token at `Config/Tool/session-token`
  (`0600`). It is **scrubbed from worker subprocess env** (recursion guard). HTTP
  clients re-read the token file per session; **MCP needs no token** (stdio child),
  so token rotation never breaks a long-running MCP session.
- **No secrets, ever.** No model API keys; the tool only invokes already-authed CLIs.
- **Injection-safe.** `question`/`context` passed as `argv`/stdin, never shell-cat.
- **Capability boundary = no writes outside `AllnighterPaths`.** The tool legitimately
  writes `Runs/`, `Config/Tool/` (token, audit log, slots) — these are expected. The
  boundary it must **not** cross: **no writes to any repo/CWD, no git, no executor
  dispatch.** The tool target links the council engine only (no dispatch/executor
  modules). The exit-gate test asserts "no filesystem writes outside `AllnighterPaths`"
  during a tool run — not the overclaim "no file writes."
- **Audit log.** Every invocation appends an honest line (time, origin, agent,
  preset, invocations, outcome) to `Config/Tool/audit.log`; the run is visible in the
  Mac app. Nothing the agents ask is hidden from the human.

## Transports (detail)

- **CLI** — a new `allnighter` executable target (SPM product, depends on
  `AllnighterEngine` **only**, which imports no UI — `00` decision log — so it builds
  and runs headlessly, no display server). Subcommands: `ask`, `start`/`status`/
  `result`, `recall`, `presets`, `doctor`, `serve`, `mcp`, `mcp-install`,
  `install-cli`. `--json` for structured output. The universal surface — works with
  any agent that has a shell tool.
- **PATH install** — `allnighter install-cli` symlinks the binary into a PATH dir
  (e.g. `/usr/local/bin`, with consent) so agents can call `allnighter` from a bare
  shell; otherwise the path is documented for manual `ln -s`. (Distribution is
  deferred, so for now this is the dev-build path.)
- **MCP** — `allnighter mcp` runs a stdio JSON-RPC MCP server (thin handler, no
  heavy dependency) pinned to a **named MCP protocol version**, advertising that
  version in capability negotiation and rejecting unknown majors with a clear error
  (upgrade path documented). The user adds it to their agent's MCP config; we never
  auto-inject.
- **HTTP/WS** — `allnighter serve` (or Mac-hosted) over `127.0.0.1` JSON + a
  `RunEvent` WebSocket — the exact iOS seam (`00` §10). To honor "boring deps"
  (`00` §2), v1 uses a **minimal loopback listener**; if Hummingbird is adopted it
  is recorded in the `00` decision log, not pulled in silently. iOS later adds
  Tailscale + pairing on top, no reshape.
- **Install helper** — `allnighter mcp-install` detects supported agents
  (Claude Code / Codex / Cursor) and, **with explicit consent**, writes the MCP
  server entry into their config (or prints the exact snippet). A reachability check
  (`team_presets`) confirms the tool answers.

## Ordered Slices

- [ ] RB6-S01 - `TeamRequest`, `TeamToolResult`, `ToolConfig` models + fixtures
  + round-trip tests. (`RunOrigin` + `TeamRun.origin` come from Phase 06; RB6
  only sets `origin`/`originAgent` on tool runs.)
- [ ] RB6-S02 - `TeamService` actor: one normalized entry (`TeamRequest` →
  `TeamRun`), origin tagging, persistence to the shared `Runs/` store. Reuses
  the 06 engine unchanged.
- [ ] RB6-S03 - **Recursion guard (fail-closed):** inject `ALLNIGHTER_TEAM_DEPTH`
  into every worker subprocess + scrub the session token from worker env; CLI/MCP
  read the env, HTTP requires the depth header (missing ⇒ refused). Tests prove a
  worker cannot start a nested council on any transport.
- [ ] RB6-S04 - `TeamGovernor`: cross-process **`flock(2)`** slot semaphore
  (crash-safe; TTL/PID sweep for orphans) + observed `invocations` in every result.
- [ ] RB6-S05 - `allnighter` CLI target (links Engine only, builds headlessly):
  `ask` (self-correcting sync), `presets`, `doctor`, `recall`; `install-cli` PATH
  setup. The universal shell surface.
- [ ] RB6-S06 - Async protocol: `start`/`status`/`result` over `TeamService`,
  reusing the `RunEvent` stream; runId returned immediately.
- [ ] RB6-S07 - MCP server (`allnighter mcp`): stdio JSON-RPC pinned to a named MCP
  protocol version, the operations as tools with structured results. Validated
  against a real MCP client.
- [ ] RB6-S08 - Local HTTP/WS server (`allnighter serve` / Mac-hosted): `127.0.0.1`
  only, bearer token, **mandatory depth header**, same handlers, `RunEvent`
  WebSocket. Minimal listener (Hummingbird only if logged in `00`).
- [ ] RB6-S09 - Security + governance hardening: token `0600` + env-scrub, audit
  log, **capability-boundary test (no writes outside `AllnighterPaths`; no git/
  executor module linked)**, injection tests, context head+tail truncation.
- [ ] RB6-S10 - Mac app integration: live "tool activity" view, origin tags in
  history, server enable/disable, exposed-preset + token management.
- [ ] RB6-S11 - `allnighter mcp-install` onboarding for Claude Code / Codex /
  Cursor (consent-gated) + reachability check + docs.

## Works Test

```text
Register `allnighter mcp` in Claude Code's MCP config (via `allnighter mcp-install`,
with consent). Mid-task, the agent calls team_ask("actor or serialized queue
for the run store?") with the Fast Team preset. Allnighter runs the local panel
(zero API cost), returns a plan + structured PlanAnalysis + `invocations`;
the agent uses it and continues — no window switch, no clipboard.

Prove the guards:
- The council's own `claude` worker, with the tool registered, attempts a nested
  team_ask on each transport -> refused (env depth for CLI/MCP; fail-closed
  depth header for HTTP). No second panel, no quota burn.
- A crashed CLI mid-council leaves no stale lock (flock auto-release); the next
  council proceeds.
- Two agents call simultaneously -> the governor caps concurrency cross-process.
- From a bare shell (no MCP): `alln team "..."` returns the same result.
- `team_recall("run store")` returns the earlier judgment (with its date), 0 calls.
- The Mac app history shows all of it, origin-tagged (mcp/cli), with observed invocations.
- No git, no executor invocation, and no writes outside AllnighterPaths occurred.
```

## Exit Gates

- [ ] A council worker cannot start a nested council on **any** transport
  (env guard for CLI/MCP; fail-closed depth header for HTTP).
- [ ] Concurrency cap holds across CLI + MCP + app via `flock(2)`; a crashed holder
  leaves no stale lock.
- [ ] `alln team` works from a bare shell (binary builds headlessly — Engine
  imports no UI); the MCP server validates against a real MCP client at a pinned
  protocol version; HTTP binds `127.0.0.1` only and requires token + depth header.
- [ ] Zero API keys introduced; no network egress beyond localhost + the CLIs' own.
- [ ] Every tool result reports observed `invocations`; `team_presets` lists work shape.
  `team_ask` may return a `runId` when `waitSeconds` elapses (client timeout only).
- [ ] Tool runs persist origin-tagged and appear in Mac app history + audit log.
- [ ] **Capability boundary:** no writes outside `AllnighterPaths`; no git; no
  executor module linked (asserted by test).
- [ ] Prompts/context reach workers as argv/stdin only; context truncates head+tail
  with a marker and `contextTruncated` is reported.
- [ ] `team_recall` is read-only, returns dates, and spends no calls.
- [ ] `swift test` + `xcodebuild test -scheme AllnighterMac` green; Code Audit CLEAN.

## Closeout

Allnighter is now the **local judgment layer for the whole machine**: any agent the
user runs can summon a zero-cost, Fusion-grade council mid-task and inherit the
structured analysis, while every call stays honest, bounded, recursion-safe, and
visible. This is the moat — the capability OpenRouter sells as a paid cloud API,
delivered locally on tools the user already owns, callable from everywhere, owning
none of their git or execution. The iOS seam (`00` §10) is now a Tailscale +
pairing layer on the loopback server RB6 already built — no reshape required.
