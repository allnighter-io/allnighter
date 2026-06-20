# MCP Help System

Status: H0a–H3 BUILT (agent-callable + distributable); H4 reframed; H5 + installed-bundle remain
Owner: Founder + Shared Core + CLI/MCP + Docs/Release
Updated: 2026-06-20

> **BUILD STATUS (resume here).** Slices below are partly shipped on feat/design-chain:
>
> | Slice | State | Where |
> | --- | --- | --- |
> | **H0a — Help SSOT** | **BUILT** | `HelpTopicRegistry.swift` (12 topics, aliases, registry refs) + `HelpService.swift` (lexical search + get(topic\|ref\|tool\|error) + `alln://` refs). Drift gates in `HelpTopicRegistryTests`. |
> | **H1 — CLI** | **BUILT** | `alln help search\|get\|topics`; `HelpContract.swift` envelopes (HelpSearch/Get/TopicsJSON) + `HelpProjector` (routing law + nextToolPlan). |
> | **H2 — MCP** | **BUILT** | `help_search`/`help_get` (MCPHelpHandlers + dispatch); routingLaw + topicSitemap + decisionTree in `mcp_hello`. |
> | **H3a — error bridge** | **BUILT** | `error_explain`/`doctor explain` → `ErrorExplainJSON` (helpRef + recovery plan) via `ErrorHelpBridge`. |
> | **H3b — host activation** | **BUILT** | `alln mcp install --target <agent>` prints config + `HelpService.hostInstructionBlock`. |
> | **H0 — installed bundle** | **NOT built** | No `help-pack.json`/topic-md export, no `alln dev export-help --check`, no `helpBundleVersion`/hash in mcp_hello/doctor, no app/CLI resource packaging. Topics are compiled-in for now. |
> | **H4 — in-app** | **REFRAMED (see below)** | NOT a separate help UI. The Default Team worker answers Allnighter questions in **normal compose** using the installed help. Mostly non-GUI wiring. |
> | **H5 — golden transcripts** | **NOT built** | Non-GUI test suite (question → tool sequence → answer shape). |
> | **H6 — web mirror** | parked | Optional. |
>
> **Generated artifacts (`docs/generated/alln/`) are regenerated + drift-gated** for the
> contract parts (mcp-tools.json, error-codes.json, help_alln_cli_spec.md). The *help
> bundle* export (H0) is the main missing piece.

## Founder Intent

When a user installs Allnighter, they do not have this repository or the phase
docs in front of them. They have the app, the `alln` binary, and whatever agent
they are already using. If they ask "how do I use Allnighter?", that agent should
not guess from training data, scrape the source repo, or invent a private
procedure. It should call the local Allnighter MCP help surface.

The help system is therefore part of the product contract, not support copy.

The installed product must carry enough local, version-correct knowledge for a
human or agent to answer:

- what Allnighter does;
- which command or MCP tool to call;
- how teams, workers, projects, Pending, threads, and results fit together;
- what the current local setup can actually do;
- how to recover from setup/auth/config errors;
- what is safe for an agent to do without human action;
- where to fetch schemas, examples, and exact enum values.

## Product Value

A world-class help MCP makes Allnighter easier to trust and easier to use:

- **Users get answers without the repo.** The installed app becomes
  self-explaining, even when the question is asked from Cursor, Claude, Codex,
  OpenClaw, Hermes, or another MCP-aware agent.
- **Agents stop guessing.** Tool selection, argument shape, enum values, polling
  cadence, idempotency, recovery, and safety rules come from the installed
  contract.
- **Support stays version-correct.** The answer matches the binary on the user's
  Mac, not a website, old release note, source checkout, or model memory.
- **Safety improves.** Help can say "call doctor", "ask the user to authenticate",
  or "do not execute without approval" before an agent spends quota or mutates a
  repo.
- **The app becomes more distributable.** A product that every agent can learn
  through `mcp_hello`, `help_search`, `help_get`, `doctor`, and `error_explain`
  is more likely to become the default local team engine.

The quality bar is the final answer. If a user asks a normal product question,
the agent should produce a concise, correct, state-aware answer with exact next
actions and no repo dependency.

## Trusted Workflow Slice

Primary slice:

```text
user asks an MCP-aware agent "How do I send this to a team?"
-> agent calls Allnighter MCP `mcp_hello`
-> agent calls `help_search(query: "...send this to a team...")`
-> agent calls `help_get(topic: "team_run_loop")`
-> agent calls `teams_list` or `team_preflight` if the answer depends on live setup
-> agent answers with the exact command/tool path for this installed version
```

Recovery slice:

```text
user asks "Why can't Allnighter run Codex?"
-> agent calls `mcp_hello`
-> agent calls `doctor(agent: "codex")`
-> agent calls `error_explain` or `help_get(topic: "setup_and_auth")`
-> agent presents the exact human action and verification step
```

No-repo slice:

```text
fresh installed Allnighter, no source checkout
-> agent connects to `alln mcp serve --stdio`
-> agent calls `help_search`, `help_get`, `mcp_hello`, and `doctor`
-> agent can answer onboarding, setup, team, Pending, and schema questions
```

In-app slice:

```text
user asks Allnighter chat "what is Pending vs running a team?"
-> Default Team routes the question to the same installed help bundle
-> help returns a concise answer, stable `alln://` refs, and suggested actions
-> Mac UI can show "Add to Pending", "Run team now", or "Open help" without
   inventing separate SwiftUI truth
```

## Non-goals

- No source-repo requirement for installed help.
- No training-data fallback for Allnighter product facts when MCP help is
  available.
- No GUI-only help truth.
- No hand-written duplicate command flags, tool schemas, enum values, or error
  recovery tables.
- No public-web lookup by default. Help is local first; optional official web
  fallback is a separate user-controlled setting.
- No hidden MCP-only behavior. Help describes the same Core/CLI/MCP contract.
- No support chatbot with private semantics. This is retrieval over product
  truth.

## Prior Art Read

The best design is not one vendor's exact shape. It is a hybrid.

| System | What to learn | What not to copy blindly |
| --- | --- | --- |
| Cursor | Layered routing: built-in skills for durable product areas, a product-doc specialist for broad questions, repo search for workspace truth, shell/config reads for current state, web only when freshness requires it. Skill descriptions are injected first; full docs load only when relevant. | There is no single product docs MCP in the observed setup, so agents still choose between several retrieval paths. Allnighter should make the local help MCP the obvious first call. |
| Grok Build | A dedicated help skill routes product questions to installed user-guide files and live config. The local docs directory is treated as source of truth, not model memory. | File reading works for the product's own agent, but third-party agents need a stable MCP/CLI contract that does not assume privileged filesystem paths. |
| Antigravity / Gemini CLI | A guide skill with `SKILL.md` as a sitemap, dense offline reference files, and optional official web URLs gives a good offline/online hybrid. | Allnighter should keep optional web help behind privacy-aware settings and should not make public docs more authoritative than the installed binary. |
| Product docs MCPs, e.g. Sanity-style `search_docs` / `read_docs` | Tool shape matters: agents can search, fetch exact docs, and cite product-specific references instead of using generic web search. | Generic docs search is not enough. Allnighter also needs live local readiness, schema refs, errors, idempotency, and approval guidance. |

Verdict: Cursor is strongest at routing and context economy. Grok and
Antigravity are stronger at installed offline docs. Product-doc MCPs are the
cleanest agent interface. Allnighter should combine all three:

```text
installed offline help pack
+ generated contract docs/schemas/errors/examples
+ MCP search/get tools
+ live local state via mcp_hello/doctor/teams/models
+ optional official web fallback
```

## Hard Decisions

These decisions tighten the plan for implementation:

- **`alln help` is the friendly installed guide.** It owns product usage,
  search, topic retrieval, answer templates, and state-aware next actions.
  **`alln docs` remains the raw generated contract reference** for exhaustive
  command/tool/schema/error output.
- **No separate `help_plan` tool in v1.** Keep the tool surface small:
  `help_search` discovers, and `help_get` retrieves. Both return an ordered
  `nextToolPlan` so host agents do not have to synthesize orchestration from
  prose.
- **`help_get` accepts topic ids, `alln://` refs, tool ids, and error codes.**
  The common paths are `help_get(topic: "pending")`,
  `help_get(ref: "alln://help/pending#when-to-use-pending")`,
  `help_get(tool: "team_start")`, and `help_get(error: "SOURCE_AUTH_EXPIRED")`.
- **Every high-traffic help response carries a suggested human answer.** The
  host agent may summarize, but the returned shape should already contain a
  short, citable, version-correct answer plus exact next action.
- **The first screen is `tools/list` + `mcp_hello`, not the topic body.** Tool
  descriptions, install snippets, and `mcp_hello` must repeat the help-first
  routing law in compact language.
- **The same help bundle powers external MCP and in-app chat.** Allnighter's own
  Default Team must not answer product questions from prompt memory while
  external agents get better local help.

## Current State

Useful substrate already exists:

- `ContractRegistry` is the Core-owned source for commands, MCP descriptors,
  schemas, error codes, doctor checks, events, examples, and generated docs.
- `ContractExport` generates `docs/generated/alln/help_alln_cli_spec.md`,
  `alln-contract.json`, `mcp-tools.json`, JSON Schemas, error codes, events, and
  examples.
- `ContractExportTests` proves checked-in generated artifacts match the
  registry.
- `MCPToolContractTests` gates command projection, parameter docs, error
  catalog references, output schema choice, and idempotency rules.
- `mcp_hello`, `doctor`, `error_explain`, `spec_get`, team tools, Pending
  read/run tools, stalled-work reads, and project foundation tools exist in the
  MCP server.
- `Agent_First_MCP_And_Messaging_Workflows.md` already names `help_get` as
  product-critical, and Works Test K says generated help must prevent schema
  guessing.

Gaps:

- `help_get` is documented but not yet in the `ContractRegistry` MCP tool list
  or `MCPServer` handler.
- There is no `help_search`, so an agent must already know the topic id.
- `alln docs` is a generated contract manual, not an installed product guide.
- Generated docs are checked into the repo, but the installed user may not have
  this repo.
- Help topics are not a versioned installed bundle with a search index.
- Tool-selection guidance, examples, troubleshooting, and current-setup routing
  are not generated/bundled as one release artifact.
- `mcp_hello` reports `docsVersionMatchesBinary`, but the help bundle/version
  is not yet a first-class runtime fact.
- Current setup questions still require agents to know that help alone is not
  live state; they should call `mcp_hello`, `doctor`, team/model catalog tools,
  or `project_workers` where those tools are registered.

## SSOT

Help has two truth layers:

1. **Contract truth:** `ContractRegistry` owns commands, MCP tools, parameters,
   output schema refs, error codes, doctor checks, events, examples, idempotency,
   and next actions. Help must generate these facts from the registry.
2. **Guide truth:** a Core-owned help topic registry owns narrative routing,
   task explanations, glossary, workflows, safety guidance, and examples that
   combine several contract facts.

The guide layer may explain product meaning. It may not hand-author flags,
schemas, enum values, error tables, or tool lists that can be generated.

Proposed source layout:

```text
Packages/AllnighterCore/Sources/AllnighterCore/HelpTopicRegistry.swift
docs/help/source/*.md                         # authored topic prose, source form
docs/generated/alln/help-pack.json            # generated installed index
docs/generated/alln/help-topics/*.md          # generated installed topics
docs/generated/alln/help-search-index.json    # generated local search index
```

Installed layout:

```text
Allnighter.app/Contents/Resources/AllnighterHelp/<contractVersion>/
~/.allnighter/help/<contractVersion>/          # optional CLI-installed mirror
```

Installed help must cite installed help refs, not repo-only paths:

```text
alln://help/team_run_loop#preflight
alln://tool/team_start
alln://schema/teamStartResponse
alln://error/SOURCE_AUTH_EXPIRED
```

Development builds may retain internal `sourceRefs` for maintainers, but public
answers must not require the user to open `docs/phases/...`.

## Help Architecture

```text
ContractRegistry
  -> command/tool/schema/error/example projections
  -> generated contract docs
  -> generated help blocks

HelpTopicRegistry
  -> authored guide topics
  -> generated contract inserts
  -> topic metadata and aliases
  -> local search index

InstalledHelpBundle
  -> bundled with app/CLI
  -> version/hash reported by mcp_hello and doctor
  -> served by alln help, MCP help tools, and Mac in-app help

HelpService
  -> pure Core lookup/search/render API over the installed bundle
  -> CLI adapter
  -> MCP adapter
  -> Mac chat/help presenter

MCP help tools
  -> help_search
  -> help_get
  -> doctor/error_explain for live setup and recovery
```

The help system should use local lexical search first. A small BM25 or SQLite FTS
index is enough for v1. Do not require embeddings or network calls. Embeddings
can be a later optional acceleration if they are local and deterministic enough
for tests.

## Tool Surface

Keep the first surface small and boring.

Required MCP tools:

```text
help_search
help_get
```

Companion tools or tool families that help should route to:

```text
mcp_hello
doctor
error_explain
teams_list
teams_show
team_preflight
model/bench readiness tools where registered
project_workers
spec_get
```

CLI parity:

```bash
alln help search "how do I send work to a team?" --json
alln help get team_run_loop --json
alln help get alln://help/pending#when-to-use-pending --json
alln help get --tool team_start --json
alln help topics --json
alln help get tool_selection --format md
alln doctor --json                  # live setup/readiness; paired with help
alln docs                         # raw generated contract manual remains
```

`alln docs` remains the generated contract reference. `alln help` is the
installed product guide and retrieval surface.

### `help_search`

Use when the agent does not know the exact topic.

Input:

```json
{
  "query": "How do I put this on Codex's desk later?",
  "kind": "search",
  "audience": "agent",
  "surface": "mcp",
  "limit": 5,
  "includeSnippets": true
}
```

Output:

```json
{
  "schemaVersion": 1,
  "contractVersion": "1.0.0",
  "helpBundleVersion": "2026.06.20",
  "helpVersionMatchesBinary": true,
  "query": "How do I put this on Codex's desk later?",
  "suggestedAnswer": {
    "audience": "agent",
    "markdown": "Use Pending when the user wants work stored for later or when Allnighter cannot start it right now. For a chat-originated request, create a Pending item with an idempotency key, then show the user the Pending id and current blocked/wake state.",
    "refs": ["alln://help/pending#when-to-use-pending"]
  },
  "results": [
    {
      "topicId": "pending",
      "sectionId": "when-to-use-pending",
      "title": "Pending Work",
      "summary": "Use Pending when the user wants work stored for later or when admission blocks.",
      "snippet": "Use pending_add when the user wants work done later...",
      "score": 0.92,
      "refs": ["alln://help/pending#when-to-use-pending"],
      "relatedTools": ["pending_add", "pending_list", "pending_run"],
      "relatedCommands": ["alln pending add", "alln pending list"],
      "needsLiveCheck": false
    }
  ],
  "nextToolPlan": [
    {
      "order": 1,
      "tool": "help_get",
      "args": {"topic": "pending", "detail": "machine"},
      "why": "Retrieve the full decision table and examples.",
      "stopWhen": "The user only needs a short conceptual answer."
    }
  ],
  "nextActions": [
    {"kind": "getHelp", "tool": "help_get", "topicId": "pending"}
  ],
  "stalenessWarning": null
}
```

Rules:

- Search only installed help content and generated contract metadata.
- Return ranked refs, not a long answer.
- Include `relatedTools` and `relatedCommands` from the registry.
- Index guide prose, topic aliases, retired vocabulary redirects, tool
  summaries, parameter names, schema names, error codes, and example titles.
- Include `suggestedAnswer` for high-confidence hits so host agents can answer
  without inventing wording from snippets.
- Include `nextToolPlan` with ordered calls and stop conditions when the query
  implies a workflow.
- Mark `needsLiveCheck: true` when the answer depends on local state.
- Allow an empty query or `kind: "topics"` request to enumerate the compact
  topic sitemap; do not add a separate `help_list` tool in v1 unless host-agent
  testing proves it is necessary.
- Never perform a run, probe, auth flow, or network call.

### `help_get`

Use when the topic/ref is known.

Input:

```json
{
  "topic": "tool_selection",
  "ref": null,
  "tool": null,
  "error": null,
  "section": null,
  "detail": "machine",
  "format": "json",
  "includeSchemas": true,
  "includeExamples": true
}
```

Output:

```json
{
  "schemaVersion": 1,
  "contractVersion": "1.0.0",
  "helpBundleVersion": "2026.06.20",
  "helpVersionMatchesBinary": true,
  "topic": {
    "id": "tool_selection",
    "title": "Tool Selection",
    "audience": "agent",
    "summary": "Choose the right Allnighter MCP tool for the user's intent.",
    "suggestedAnswer": {
      "markdown": "For long-running team work, call `team_preflight` first, then `team_start` with an idempotency key. Poll with `team_status` using `nextPollAfterMs`, then fetch `team_result` or `spec_get` for the full packet.",
      "refs": ["alln://help/tool_selection#team-run"]
    },
    "bodyMarkdown": "...",
    "machineGuide": {
      "rules": [
        {
          "intent": "start a long team run",
          "preferredTool": "team_preflight -> team_start",
          "argsSkeleton": {
            "team_preflight": {"lane": "code", "team": "code_bug_hunt", "prompt": "..."},
            "team_start": {"prompt": "...", "lane": "code", "team": "code_bug_hunt", "idempotencyKey": "..."}
          },
          "needsLiveCheck": true,
          "approvalNote": "Starting an answer team is allowed when preflight passes; mutating execution follows the installed approval/safety policy.",
          "notes": "Use a lane/team explicitly. Poll using nextPollAfterMs."
        }
      ]
    },
    "nextToolPlan": [
      {"order": 1, "tool": "mcp_hello", "args": {}, "why": "Check current readiness."},
      {"order": 2, "tool": "team_preflight", "args": {"lane": "code", "team": "<team>", "prompt": "<prompt>"}, "why": "Validate before spending quota."}
    ],
    "relatedTools": ["mcp_hello", "team_preflight", "team_start", "pending_add", "spec_get"],
    "relatedCommands": ["alln team preflight", "alln team start", "alln spec"],
    "schemaRefs": ["alln://schema/teamStartResponse"],
    "errorRefs": ["alln://error/CLI_USAGE_ERROR"],
    "sourceRefs": ["alln://help/tool_selection"]
  },
  "stalenessWarning": null
}
```

Rules:

- `detail: summary` returns a compact human/agent answer.
- `detail: machine` returns structured decision tables, argument skeletons,
  suggested answer text, refs, and next-tool plans. It is the preferred mode for
  agents that will act.
- `detail: full` returns complete markdown plus generated appendices.
- `topic`, `ref`, `tool`, and `error` are mutually exclusive selectors.
- Unknown topics return close matches, the compact sitemap, and a suggested
  `help_search` call instead of a dead-end error.
- `includeSchemas` returns schema refs by default; inline schemas only when
  explicitly requested and small enough.
- If a topic is about live setup, the topic must name the live tool to call
  rather than pretending the help bundle knows current state.
- Every high-traffic topic must include at least one stable `alln://` ref the
  calling agent can cite in its final answer.

## Required Topics

Minimum v1 installed topics:

| Topic id | Purpose | Generated inputs |
| --- | --- | --- |
| `quickstart` | First 5 minutes: what Allnighter is, run a team, inspect result. | commands, examples |
| `tool_selection` | Agent decision guide for MCP/CLI tools. | MCP tools, idempotency, schemas |
| `current_setup` | How to answer "what can my install do right now?" | mcp_hello, doctor, models, teams |
| `setup_and_auth` | Install, source auth, doctor, recovery ladder. | doctor checks, errors |
| `teams_and_workers` | Teams, workers, skills, models, Default Team. | team/skill/model schemas |
| `team_run_loop` | Preflight, start, status, result, cancel, spec retrieval. | team tools, async schemas |
| `deployables` | Packaged team jobs and deployable-team flows. | deployable tools |
| `pending` | Draft/Pending/Running, later work, Wake facts. | pending schemas/tools |
| `projects_and_threads` | Project roots, work threads, project workers. | project/thread tools |
| `file_references` | Composer `@` refs, file chips, send-time audit. | file-reference errors/tools |
| `images` | Image attachments and worker image output. | attachment errors/tools |
| `schemas` | Where to get JSON schemas and examples. | all generated schemas |
| `errors` | Error recovery and retry ladder. | error catalog |
| `doctor` | Doctor status, auto-fix boundaries, human actions. | doctor schema/checks |
| `approval_and_safety` | What agents may do, approval objects, mutating boundaries. | safety errors, tool metadata |
| `entitlement_and_limits` | Entitlement blocks, quota/billing posture, and tools still safe when blocked. | entitlement errors/tools |
| `mcp_install` | How to install/configure the MCP server for agents. | install command/docs |
| `mac_app` | What the app shows and when to open it. | app-facing guide prose |
| `glossary` | Product vocabulary: Team, worker, model, skill, Pending, run. | vocabulary source refs |
| `examples` | Named recipes for common human and agent workflows. | registry examples |

Every advertised MCP tool must be reachable from at least one topic. Every
topic that names a tool or command must reference a registry id.

Topic aliases and redirects are part of v1:

| User/search term | Canonical topic | Notes |
| --- | --- | --- |
| `approval`, `permissions`, `safe to run` | `approval_and_safety` | `approval` is an alias, not a separate topic. |
| `fan out`, `send to team`, `delegate` | `team_run_loop` | Search should find current vocabulary while redirecting retired words. |
| `build`, `code lane` | `teams_and_workers` / `team_run_loop` | Explain Build -> Code when needed; public output uses Code. |
| `lane` | `glossary` | Disambiguate old lane language from current product terms. |
| `saved job`, `recipe`, `deploy` | `deployables` | Routes to deployable-team tools when registered. |
| `limits`, `billing`, `blocked`, `quota` | `entitlement_and_limits` | Must not estimate future spend; route to live entitlement/doctor facts. |

## State-Aware Answering Rules

Help docs answer product behavior. Live tools answer local state.

| User asks | Agent should call | Why |
| --- | --- | --- |
| "How do I run a bug hunt?" | `help_search` -> `help_get` -> optionally `teams_list` | Help explains workflow; teams list shows installed teams. |
| "Can Allnighter run right now?" | `mcp_hello` | Readiness is live state. |
| "Why is Codex blocked?" | `doctor(agent: "codex")` -> `error_explain` | Auth/readiness is live state plus recovery metadata. |
| "What tool should I use?" | `help_get(topic: "tool_selection")` | Tool routing is guide truth generated from the registry. |
| "What fields does team_start return?" | `help_get(topic: "schemas", includeSchemas: true)` | Schema refs come from generated artifacts. |
| "Show the full packet from that run" | `spec_get` | Results are runtime artifacts, not help docs. |

MCP server/tool descriptions should explicitly instruct agents:

```text
For questions about how to use Allnighter, call help_search/help_get first.
For questions about this Mac's current readiness, call mcp_hello or doctor.
Do not answer Allnighter product questions from training data when these tools
are available.
```

## Bootstrap Contract

World-class help starts before the first help call. The MCP client sees
`tools/list` and `mcp_hello` before it reads any topic body, so those surfaces
must make the routing law unavoidable.

Every generated help-aware tool description should include a short routing note:

```text
For Allnighter usage, tool-choice, setup, team, Pending, safety, schema, or
error questions, call help_search/help_get before answering from memory.
```

`mcp_hello` must return a compact decision tree and topic sitemap:

```json
{
  "contractVersion": "1.0.0",
  "helpBundleVersion": "2026.06.20",
  "helpVersionMatchesBinary": true,
  "routingLaw": "For Allnighter product questions, call help_search/help_get before answering from memory.",
  "topicSitemap": [
    {"topicId": "quickstart", "title": "Quickstart", "summary": "First 5 minutes."},
    {"topicId": "tool_selection", "title": "Tool Selection", "summary": "Which tool/command to call."},
    {"topicId": "current_setup", "title": "Current Setup", "summary": "Use mcp_hello/doctor for live readiness."}
  ],
  "decisionTree": [
    {"ifUserAsks": "how to use Allnighter", "call": "help_search -> help_get"},
    {"ifUserAsks": "can it run right now", "call": "mcp_hello"},
    {"ifUserAsks": "why is setup/auth blocked", "call": "doctor -> error_explain"},
    {"ifUserAsks": "what schema/fields/errors exist", "call": "help_get(topic: schemas/errors)"}
  ]
}
```

If a host agent only reads one Allnighter response at session start, it should
still know how to ask Allnighter about itself.

## In-App Consumption

The installed help bundle is not only for external MCP clients. The Mac app and
Default Team should use the same `HelpService` directly or through the CLI/MCP
adapter.

Rules:

- Default Team product questions route to `HelpService` before prompt-memory
  answers.
- In-app answers use `audience: "human"` by default: short answer first, exact
  next action second, refs available but not noisy.
- The Mac presenter may render suggested actions such as "Send to team",
  "Add to Pending", "Run doctor", "Open topic", or "Copy CLI command" from the
  returned `nextToolPlan`.
- SwiftUI may present help; it must not own help truth, topic ids, tool-choice
  tables, or schema facts.
- In-app help can chain to live checks (`mcp_hello`, `doctor`, `team_preflight`)
  when the user asks "can you do this now?".

Example in-app answer shape:

```json
{
  "answerMarkdown": "Pending is for work you want saved for later or work that cannot start yet. Running a team starts work now after preflight.",
  "refs": ["alln://help/pending#pending-vs-running"],
  "suggestedActions": [
    {"kind": "addToPending", "label": "Add to Pending"},
    {"kind": "teamPreflight", "label": "Check a team"}
  ]
}
```

## Drift Prevention

Release law:

```text
No Allnighter release ships with stale installed help.
```

Required gates:

- `alln dev export-contracts --check` still gates generated contract artifacts.
- Add `alln dev export-help --check` to generate and verify the installed help
  bundle.
- Add `HelpPackExportTests` so checked-in help artifacts match
  `HelpTopicRegistry + ContractRegistry`.
- Add `HelpTopicReferenceTests` so every topic command/tool/schema/error ref
  resolves to the registry.
- Add `HelpCoverageTests` so every advertised MCP tool has at least one topic
  route and every topic with a `relatedTool` has a registered tool.
- Add `HelpNoRepoDependencyTests` so public help output does not require
  `docs/phases/...`, `Packages/...`, or source checkout paths.
- Add `HelpBannedTermTests` for retired product vocabulary in public help.
- Add packaging tests that prove the app/CLI bundle includes the help pack for
  the current `contractVersion`.
- `mcp_hello` and `doctor` must report `helpBundleVersion`,
  `helpBundleHash`, and `helpVersionMatchesBinary`.

Runtime stale-help behavior:

| Condition | Tool behavior | Agent instruction |
| --- | --- | --- |
| `helpVersionMatchesBinary == true` | Normal responses. | Use help normally. |
| Help bundle present but stale | `mcp_hello`, `doctor`, `help_search`, and `help_get` include `stalenessWarning`; schema/tool/enum answers prefer live `alln docs` / registry projections. | Warn once, avoid confident flag/enum claims from guide prose, and use generated contract refs for exact fields. |
| Help bundle missing/corrupt | `mcp_hello` reports degraded help; `help_search/get` return a structured `HELP_BUNDLE_UNAVAILABLE` error with remediation. | Use `alln docs`/`doctor` for exact contract facts; tell the user to repair/reinstall or run the developer export command in a source checkout. |

Developer remediation:

```bash
alln dev export-help --check
alln dev export-help
```

Installed-user remediation must be phrased as an app/binary repair or update,
not a source-repo command unless the user is explicitly in a development checkout.

Generated block rule:

```text
If a fact can be derived from ContractRegistry, HelpTopicRegistry must reference
the generated block. It must not duplicate the text by hand.
```

Examples:

- Tool parameter tables are generated.
- Error recovery tables are generated.
- Schema refs are generated.
- Idempotency/retry guidance is generated.
- Short workflow prose is authored.
- Product positioning and conceptual explanation are authored.

## Error And Recovery Bridge

Every emitted error should lead to help without a search detour.

Rules:

- Every `ErrorSpec` with user/agent recovery must include `helpTopicId` and
  optional `helpSectionId` once the help registry exists.
- `error_explain` must return `helpRef`, `helpTopicId`, and `helpSectionId`
  alongside the catalog recovery metadata.
- Tool-level failures should include `docsRef` / `helpRef` where safe, so a host
  agent can call `help_get(ref: ...)` immediately.
- `help_get(error: "SOURCE_AUTH_EXPIRED")` resolves through the error catalog,
  not a hand-authored duplicate explanation.
- Unknown help topics, unknown refs, and bad selectors return close matches and
  the topic sitemap. They should not strand the agent with only
  `CLI_USAGE_ERROR`.

Example error bridge:

```json
{
  "code": "SOURCE_AUTH_EXPIRED",
  "agentAction": "Re-authenticate the named source.",
  "helpRef": "alln://help/setup_and_auth#source-auth-expired",
  "nextToolPlan": [
    {"order": 1, "tool": "help_get", "args": {"ref": "alln://help/setup_and_auth#source-auth-expired"}},
    {"order": 2, "tool": "doctor", "args": {"agent": "<sourceId>"}}
  ]
}
```

## Privacy And Network Rules

Allnighter help is local by default.

- `help_search` and `help_get` must not send the user's query, prompt, repo path,
  config, or tool history to a network service.
- Optional official web fallback can exist later only behind an explicit user
  setting such as `allowNetworkHelp`.
- If web fallback is enabled, tool results must label it as web-sourced and
  include the URL/version/date.
- Web docs never outrank the installed binary contract for command/tool/schema
  truth.
- Help tools must not reveal secrets, prompt bodies, run transcripts, file
  contents, or provider config. They can point to `spec_get`, `doctor`, or
  project/thread tools when runtime data is needed.

Privacy-safe local feedback:

- Record zero-result and low-confidence help searches locally with timestamp,
  contract version, and topic ids considered.
- Keep raw query text local only; do not transmit it.
- Provide a future opt-in export/redaction path for support, never automatic
  upload.
- Use this local gap log to add aliases, topics, examples, and golden
  transcripts.

## Agent Install Artifacts

`alln mcp install --target <agent> --print` should include both MCP config and a
short agent instruction block:

```text
Use Allnighter MCP for Allnighter product questions.
Call mcp_hello at session start.
Call help_search/help_get before answering "how do I use Allnighter?"
Call doctor for current setup/auth/readiness questions.
Use error_explain after failed Allnighter tools.
Never rely on training data for current Allnighter flags, schemas, or safety.
```

Generated artifacts:

```text
docs/generated/alln/agent-quickstart.md
docs/generated/alln/agent-tool-selection.md
docs/generated/alln/agent-error-recovery.md
docs/generated/alln/help-pack.json
docs/generated/alln/help-search-index.json
docs/generated/alln/host-instructions/codex.md
docs/generated/alln/host-instructions/claude.md
docs/generated/alln/host-instructions/cursor.md
docs/generated/alln/host-instructions/openclaw.md
docs/generated/alln/host-instructions/hermes.md
```

Every host instruction fragment must include the permanent routing rule:

```text
When the user asks anything about Allnighter usage, tools, teams, Pending,
errors, setup, safety, schemas, or capabilities, call the local Allnighter MCP
`help_search` first, or `help_get` if you already know the topic/ref/tool/error.
Prefer the local installed help pack over training data or public web docs.
```

Generate fragments for the major host shapes:

| Host | Artifact shape |
| --- | --- |
| Codex | Project/user instructions snippet. |
| Claude | Project custom instructions snippet. |
| Cursor | Rules / project instruction snippet. |
| OpenClaw / Hermes | Messaging-agent bootstrap prompt and MCP config notes. |

Optional later activation packs can mirror Cursor/Grok-style skills:

```text
AllnighterHelp/SKILL.md
AllnighterHelp/references/*.md
```

Those packs are install helpers, not a second truth source. They are generated
from the same help pack.

## Implementation Slices

### H0 - Help SSOT and installed bundle foundation

- Add `HelpTopicRegistry` with topic ids, aliases, refs, audience, and generated
  block declarations.
- Add `docs/help/source/*.md` for authored guide prose.
- Add `HelpExport` artifacts: `help-pack.json`, generated topic markdown, and
  `help-search-index.json`.
- Add `alln dev export-help --check`.
- Add app/CLI resource packaging for the help bundle.
- Add `helpBundleVersion`, `helpBundleHash`, and `helpVersionMatchesBinary` to
  `mcp_hello` and doctor.
- Add `HelpTopicReferenceTests` against `ContractRegistry`.
- Add no-repo, banned-term, and packaging tests.

Completion gate:

- A built product can read its help bundle without the repo.
- Help topics can be generated before MCP runtime handlers exist.
- Every topic ref resolves.
- Drift fails before release.

### H1 - CLI help retrieval and authoring loop

- Add `alln help search <query> --json`.
- Add `alln help get <topic|ref> --json|--format md`.
- Add `alln help get --tool <tool>` and `alln help get --error <code>`.
- Add `alln help topics --json` or equivalent topic-sitemap output.
- Keep `alln docs` as the raw generated contract reference.
- Add focused tests for quickstart, tool selection, schemas, errors, aliases,
  and stale-bundle behavior.

Completion gate:

- A user can answer common product questions from the installed CLI alone.
- Bad topic/ref requests return close matches and the sitemap.

### H2 - MCP help retrieval and bootstrap injection

- Add registry specs and handlers for `help_search` and `help_get`.
- Add schemas, error sets, output schema cases, idempotency rules, and MCP
  parity with `alln help`.
- Add `suggestedAnswer`, `nextToolPlan`, stable refs, close matches, and
  `stalenessWarning` to returned shapes.
- Put the help-first routing law in MCP tool descriptions.
- Put `topicSitemap`, decision tree, help version/hash, and routing law in
  `mcp_hello`.
- Add Works Test K as an MCP handler test.

Completion gate:

- An MCP client can search and retrieve help without knowing topic ids.
- A host agent that only sees `tools/list` + `mcp_hello` knows to call help.

### H3 - State-aware plans, error bridge, and host activation

- Mark topics/sections that require live state.
- Ensure `help_search` and `help_get` include `needsLiveCheck`,
  `nextToolPlan`, and stop conditions.
- Add examples that combine help with `mcp_hello`, `doctor`, `teams_list`,
  `team_preflight`, and `project_workers`.
- Add `helpTopicId`, `helpSectionId`, and `helpRef` to error recovery metadata.
- Generate OpenClaw/Hermes/Codex/Claude/Cursor instruction snippets.
- Add `alln mcp install --target <agent> --print` output for help-first usage.
- Add local zero-result/low-confidence search logging.

Completion gate:

- Help answers do not pretend to know live setup. They route to live tools.
- Error recovery is one call away from the failed tool result.
- A third-party agent install has enough permanent instructions to call
  Allnighter help before guessing.

### H4 - In-app help consumption — REFRAMED (founder, 2026-06-20)

**There is no separate in-app help UI, AND the default chat must NOT be biased toward
help.** In-app help is just regular compose: a user can ask "how does Pending work?"
and get a good answer — but the default chat stays **raw passthrough that equals
running the CLI raw** (the locked Unified-Run-Model law). 

**DO NOT inject a help-first instruction into the Default Team worker's prompt
(founder, 2026-06-20).** Assuming every chat is an internal-help question is wrong ~99%
of the time, adds latency, and breaks default-run == CLI-raw. The help-first routing
law / `hostInstructionBlock` is for **external host agents' standing config only**
(the `alln mcp install --target …` snippet), where it is scoped to Allnighter-usage
questions — never for Allnighter's own default chat.

How in-app Allnighter Q&A works without bias:

- The worker reaches the installed help by **tool availability, by its own judgment** —
  i.e. the Allnighter MCP help tools (`help_search`/`help_get`/`doctor`) are reachable
  if/when the worker chooses to call them because the *user actually asked an Allnighter
  question*. No system-prompt mandate, no forced first call.
- `HelpService` (Core) stays the SSOT for whatever path answers.
- The Mac presenter only renders the normal chat reply; no dedicated help component.

Open question to resolve before building H4: should Allnighter even auto-wire its own
MCP into the default-chat worker invocation (so the worker *can* call help), or leave
in-app Allnighter Q&A to whatever MCP the user already configured? Either way: **no
prompt bias, default chat == CLI raw.** Keep H4 minimal until decided.

Completion gate (revised):

- Default chat answers a normal work question exactly as the raw CLI would (no help
  bias, no added latency). A genuine Allnighter question *can* be answered from
  installed help, but only when the agent chooses to reach for it. No help screen.

### H5 - Golden transcripts and quality bar

- Add 10-20 golden transcripts:
  user question -> expected tool sequence -> expected answer shape.
- Include no-repo, Pending, auth expired, wrong team id, deployable job,
  stale help, and in-app chat examples.
- Grade for exact refs, next actions, banned vocabulary, live-state routing, and
  concise human answer.

Completion gate:

- The first canonical questions produce crisp, citable, actionable answers in
  CLI, MCP, and in-app paths.

### H6 - Optional official web mirror

- Publish versioned official help docs generated from the same help pack.
- Add optional, privacy-labeled web fallback only when enabled by the user.
- Web fallback must never override installed command/tool/schema truth.

Completion gate:

- Public docs improve onboarding without becoming a second SSOT.

## Works Tests

### Works Test A - no-repo onboarding

Setup:

```text
Run installed `alln` from a temp directory with no Allnighter source checkout.
```

Gesture:

```text
alln help search "How do I send work to a team?" --json
alln help get team_run_loop --json
```

Assertions:

- Results mention the current installed `contractVersion`.
- Output contains no repo-only file path.
- Output names the correct CLI/MCP sequence and schema refs.

### Works Test B - MCP help prevents guessing

Gesture:

```text
MCP client calls help_search("put this on Codex's desk later")
MCP client calls help_get("pending", detail: "machine")
```

Assertions:

- Pending is the top route when available.
- Response names `pending_add` only if the tool is registered; otherwise it
  states the current installed alternative.
- Response includes idempotency and live-state guidance.

### Works Test C - setup question routes to doctor

Gesture:

```text
MCP client asks how to fix a blocked Codex source.
```

Assertions:

- Help marks the answer as requiring live state.
- `doctor(agent: "codex")` returns the exact failing check.
- `error_explain` returns the recovery text.
- The final answer names a verification step.

### Works Test D - release drift blocks

Setup:

```text
Change an MCP parameter or error code in ContractRegistry without regenerating help.
```

Assertions:

- `alln dev export-help --check` fails.
- Tests identify the stale topic/generated block.

### Works Test E - source-free app bundle

Setup:

```text
Build the Mac app/CLI artifact.
```

Assertions:

- Help bundle exists in app resources.
- `mcp_hello` reports matching help/binary versions.
- `help_get(topic: "quickstart")` succeeds with no repo checkout.

### Works Test F - no unsafe network by default

Gesture:

```text
help_search("latest Allnighter docs")
```

Assertions:

- Search stays local by default.
- If optional web fallback is disabled, result says local installed docs only.
- No prompt/repo/config content leaves the machine.

### Works Test G - simulated agent loop

Gesture:

```text
help_search("put work on Codex's desk later")
help_get(ref: <top result ref>, detail: "machine")
mcp_hello()
```

Assertions:

- The combined guidance names Pending tools when registered, or the current
  installed alternative when not.
- Guidance includes idempotency and live-check notes.
- Output contains at least one stable `alln://` ref.
- Output contains no retired public vocabulary except in alias/redirect context.

### Works Test H - in-app product question

Gesture:

```text
User asks Default Team chat: "What is Pending vs running a team?"
```

Assertions:

- The response comes from the installed help bundle.
- The response is short, version-correct, and uses current vocabulary.
- Suggested actions include app-native paths such as "Add to Pending" or
  "Check a team" where available.
- No SwiftUI-local table owns the answer.

### Works Test I - stale help degraded mode

Setup:

```text
Install a mismatched help bundle for the current binary contract.
```

Assertions:

- `mcp_hello` reports `helpVersionMatchesBinary: false`.
- `help_search` / `help_get` include `stalenessWarning`.
- Exact schema/enum questions route to current contract docs/registry refs.
- The agent answer warns once and avoids confident claims from stale guide prose.

### Works Test J - error to help bridge

Gesture:

```text
Call a tool with an invalid team id, then call error_explain and help_get(ref).
```

Assertions:

- Error response includes `helpRef` or error explanation returns one.
- `help_get(ref:)` resolves without another search.
- Final guidance includes the exact safe retry path or tells the agent to stop.

### Works Test K - golden transcripts

Setup:

```text
Run the golden transcript suite.
```

Assertions:

- Canonical questions produce the expected tool sequence.
- Final answers include a short human paragraph, exact next action, and stable
  citation.
- Wrong-tool and stale-help scenarios degrade predictably.

## Done When

- Installed users can get product help through `alln help` and MCP without the
  source repo.
- Agents are instructed and tooled to call `help_search`/`help_get` for
  Allnighter product questions.
- `help_get` and `help_search` are registry-backed MCP tools with schemas,
  errors, idempotency, and CLI parity.
- `mcp_hello` and doctor report help bundle version/hash/drift.
- Generated help, agent install snippets, schemas, errors, examples, and MCP
  descriptors are release-gated.
- `mcp_hello` and generated tool descriptions teach the help-first routing law.
- `help_search`/`help_get` return suggested human answers, stable refs, and
  next-tool plans for high-traffic topics.
- Stale or missing help degrades explicitly and routes exact contract questions
  to current registry/docs truth.
- Error responses bridge to help refs without requiring another search.
- Allnighter's in-app chat uses the same installed help truth as external MCP
  agents.
- Golden transcripts pass for the canonical first questions.
- Help distinguishes product docs from live setup state and routes to live
  tools when needed.
- Public help output never depends on repo-only paths or model memory.

## Open Questions

- Should production help include internal `sourceRefs` for support builds, or
  only public `alln://help/...` refs?
- Should optional web fallback ship in v1, or stay parked until official public
  docs exist?
- What is the retention window and UI for the local zero-result/low-confidence
  help search log?
