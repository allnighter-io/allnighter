# MCP Help System

Status: Draft feature packet
Owner: Founder + Shared Core + CLI/MCP + Docs/Release
Updated: 2026-06-20

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
  -> served by alln help and MCP help tools

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
models_list
project_workers
spec_get
```

CLI parity:

```bash
alln help search "how do I send work to a team?" --json
alln help get team_run_loop --json
alln help get tool_selection --format md
alln help doctor --json
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
  "query": "How do I put this on Codex's desk later?",
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
  "nextActions": [
    {"kind": "getHelp", "tool": "help_get", "topicId": "pending"}
  ]
}
```

Rules:

- Search only installed help content and generated contract metadata.
- Return ranked refs, not a long answer.
- Include `relatedTools` and `relatedCommands` from the registry.
- Mark `needsLiveCheck: true` when the answer depends on local state.
- Never perform a run, probe, auth flow, or network call.

### `help_get`

Use when the topic/ref is known.

Input:

```json
{
  "topic": "tool_selection",
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
  "topic": {
    "id": "tool_selection",
    "title": "Tool Selection",
    "audience": "agent",
    "summary": "Choose the right Allnighter MCP tool for the user's intent.",
    "bodyMarkdown": "...",
    "machineGuide": {
      "rules": [
        {
          "intent": "start a long team run",
          "preferredTool": "team_preflight -> team_start",
          "notes": "Use a lane/team explicitly. Poll using nextPollAfterMs."
        }
      ]
    },
    "relatedTools": ["mcp_hello", "team_preflight", "team_start", "pending_add", "spec_get"],
    "relatedCommands": ["alln team preflight", "alln team start", "alln spec"],
    "schemaRefs": ["alln://schema/teamStartResponse"],
    "errorRefs": ["alln://error/CLI_USAGE_ERROR"],
    "sourceRefs": ["alln://help/tool_selection"]
  }
}
```

Rules:

- `detail: summary` returns a compact human/agent answer.
- `detail: machine` returns structured decision tables and refs.
- `detail: full` returns complete markdown plus generated appendices.
- `includeSchemas` returns schema refs by default; inline schemas only when
  explicitly requested and small enough.
- If a topic is about live setup, the topic must name the live tool to call
  rather than pretending the help bundle knows current state.

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
| `pending` | Draft/Pending/Running, later work, Wake facts. | pending schemas/tools |
| `projects_and_threads` | Project roots, work threads, project workers. | project/thread tools |
| `file_references` | Composer `@` refs, file chips, send-time audit. | file-reference errors/tools |
| `images` | Image attachments and worker image output. | attachment errors/tools |
| `schemas` | Where to get JSON schemas and examples. | all generated schemas |
| `errors` | Error recovery and retry ladder. | error catalog |
| `doctor` | Doctor status, auto-fix boundaries, human actions. | doctor schema/checks |
| `approval_and_safety` | What agents may do, approval objects, mutating boundaries. | safety errors, tool metadata |
| `mcp_install` | How to install/configure the MCP server for agents. | install command/docs |
| `mac_app` | What the app shows and when to open it. | app-facing guide prose |
| `glossary` | Product vocabulary: Team, worker, model, skill, Pending, run. | vocabulary source refs |
| `examples` | Named recipes for common human and agent workflows. | registry examples |

Every advertised MCP tool must be reachable from at least one topic. Every
topic that names a tool or command must reference a registry id.

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
```

Optional later activation packs can mirror Cursor/Grok-style skills:

```text
AllnighterHelp/SKILL.md
AllnighterHelp/references/*.md
```

Those packs are install helpers, not a second truth source. They are generated
from the same help pack.

## Implementation Slices

### H0 - Help SSOT and bundle shape

- Add `HelpTopicRegistry` with topic ids, aliases, refs, audience, and generated
  block declarations.
- Add `docs/help/source/*.md` for authored guide prose.
- Add `HelpTopicReferenceTests` against `ContractRegistry`.
- Add no-repo and banned-term tests.

Completion gate:

- Help topics can be generated without touching MCP runtime.
- Every topic ref resolves.

### H1 - Installed help export

- Add `ContractExport` or sibling `HelpExport` artifacts:
  `help-pack.json`, generated topic markdown, and `help-search-index.json`.
- Add `alln dev export-help --check`.
- Add app/CLI resource packaging for the help bundle.
- Add `helpBundleVersion`, `helpBundleHash`, and `helpVersionMatchesBinary` to
  `mcp_hello` and doctor.

Completion gate:

- A built product can read its help bundle without the repo.
- Drift fails before release.

### H2 - CLI help retrieval

- Add `alln help search <query> --json`.
- Add `alln help get <topic> --json|--format md`.
- Keep `alln docs` as the raw generated contract reference.
- Add focused tests for quickstart, tool selection, schemas, and errors.

Completion gate:

- A user can answer common product questions from the installed CLI alone.

### H3 - MCP help retrieval

- Add registry specs and handlers for `help_search` and `help_get`.
- Add schemas, error sets, output schema cases, and idempotency rules.
- Add Works Test K as an MCP handler test.
- Update MCP server instructions/descriptions to route agents to help first.

Completion gate:

- An MCP client can search and retrieve help without knowing topic ids.

### H4 - State-aware help routing

- Mark topics/sections that require live state.
- Ensure `help_search` results include `needsLiveCheck` and `nextActions`.
- Add examples that combine help with `mcp_hello`, `doctor`, `teams_list`,
  `team_preflight`, and `project_workers`.

Completion gate:

- Help answers do not pretend to know live setup. They route to live tools.

### H5 - Agent install and generated activation packs

- Generate OpenClaw/Hermes/Codex/Claude/Cursor instruction snippets.
- Add `alln mcp install --target <agent> --print` output for help-first usage.
- Optionally generate skill-style offline references from the help pack.

Completion gate:

- A third-party agent install has enough instructions to call Allnighter help
  before guessing.

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
- Help distinguishes product docs from live setup state and routes to live
  tools when needed.
- Public help output never depends on repo-only paths or model memory.

## Open Questions

- Should `alln help` be a new top-level command, or should `alln docs` grow
  `search/get` subcommands while preserving raw contract output?
- Should production help include internal `sourceRefs` for support builds, or
  only public `alln://help/...` refs?
- Should optional web fallback ship in v1, or stay parked until official public
  docs exist?
- Which agent targets get generated activation snippets first: Codex, Claude,
  Cursor, OpenClaw, Hermes, or all of them?
