# CLI Product Spine

Status: Draft v3 for mentor feedback; product spine
Owner: Founder + Shared Core + CLI + Mac
Updated: 2026-06-15

## Founder Intent

Allnighter should not be trapped inside a menu bar app. The product coordinates
CLIs, so the CLI should be a first-class product surface rather than a debug
sidecar.

The Mac app still matters. It is the visual floor manager. But the command line
should be the spine: scriptable, testable, agent-callable, and semantically
identical to what the GUI renders.

The stronger version: Allnighter is entering an agent-first world. Other agents
must be able to call Allnighter as confidently as a human can. A merely adequate
CLI is not enough; `alln` is the contract.

## Prior Art Read

Local sibling projects point to the same architecture:

| Project | Keep for Allnighter |
| --- | --- |
| VVX | GUI as a visual remote control over a headless CLI; stable JSON/NDJSON for every core operation; `doctor` as the first recovery step; generated AI-facing CLI docs from the compiled binary. |
| ClawWidget | One contract, one truth; generated `help_*` artifacts; strict schema validation before execution; structured errors with `agentAction`, `fixCommand`, and `requiresManual`; one audit trail; no hidden MCP-only behavior. |
| KansoBooks | Interface larger than transport; MCP/CLI/help/doctor are projections of one contract; tools expose availability, grants, consent, owner actions, and structured recovery; agents draft/propose while product-owned truth remains local and audited. |

Translation:

```text
AllnighterCore contract registry
  -> validators
  -> run engine
  -> alln CLI
  -> generated docs/help
  -> doctor/recovery
  -> MCP tools
  -> local HTTP/WS
  -> Mac/iOS presenters
```

No surface invents behavior. If a feature changes, the command contract changes
first, then CLI docs, GUI, MCP, local API, examples, and tests follow.

Implementation detail lives in `CLI_Implementation_Contract.md`: exact command
grammar, `TeamRunJSON`, NDJSON events, doctor checks, error codes, generated
artifacts, and proof gates.

## Thesis

```text
Product: Allnighter
Daily command: alln
Primary operation: alln team
Mac app: visual floor manager over the same command model
iOS app: remote floor manager over the same command model
Agent surface: team as a local tool, same engine as alln
```

`allnighter` is too long for a daily command. `nite` is cute but non-obvious.
`nt` is short but already collides in package ecosystems. `alln` is short,
brand-linked, available enough in the checks run so far, and easy for agents and
humans to type.

## Implementation Posture

Treat this as a breaking replacement for the RB6 tool surface, not an extension
of it. The current CLI/MCP surface proved the idea, but it still speaks the old
prototype frame (`ask`, `presets`, `recall`, old run fields, hand-written tool
descriptors). The first serious `alln` milestone must cut to the new command
grammar and schema together.

Do not build new GUI wiring against legacy JSON and translate it later. The CLI
is the golden grammar; shared Core command handlers are the golden implementation
path.

## Why CLI First

1. **Native habitat.** Allnighter orchestrates the CLIs the user already pays
   for. A great CLI is not a lesser GUI; it is the native control surface.
2. **Forces clean architecture.** If the CLI is first-class, product truth cannot
   hide in SwiftUI state or menu-bar affordances.
3. **Makes agents better users.** Codex, Claude Code, Aider, Cursor, and other
   tools can call `alln` directly instead of reading a GUI.
4. **Makes proof easier.** CLI commands produce deterministic output, fixtures,
   schemas, and Works Tests before polished UI exists.
5. **Clarifies background mode.** Foreground CLI commands can be ephemeral; long
   runs, iOS, and overnight work can opt into a resident coordinator.
6. **Creates distribution.** A world-class CLI plus agent-ready docs spreads
   through workflows, skills, MCP clients, READMEs, and copy-paste commands.

## Product Vocabulary

```text
Source = how Allnighter reaches a model
Model  = Opus, Sonnet, Grok, Gemini, etc.
Skill  = the hat/instruction
Worker = model + skill for this run
Team   = workers selected for this job
Bench  = available models
```

CLI surfaces:

```text
Bench/setup: alln models
Run/customize: alln team
Work-order creation: alln work
```

Do not ship public `alln team`, `alln team`, or `worker` language. The RB6
upload that says `team_*` is superseded by this doc; the durable operation is
`team_*`.

## RB6 Cutover

The existing RB6 surface must be replaced deliberately:

| Today | Target | Decision |
| --- | --- | --- |
| `allnighter` binary | `alln` | Rename the SPM product/install path for public use. No public long-form alias. |
| `ask` | `alln team` | Replace, do not alias as public grammar. |
| `detect` / narrow doctor output | `alln doctor` | Merge into Doctor; hidden debug commands are allowed only for local development. |
| `presets` | `alln team show` now; team preset commands later | Do not ship a separate old preset grammar. |
| `recall` | `alln history` / `alln show` | History and show own retrieval. |
| `team_ask` / RB6 tool names | `team_ask` / `team_*` | Rename before advertising MCP again. |
| `plan` JSON / copy | `plan` | Rename in persisted/public JSON at the same time as CLI output. |
| `Worker` / `worker` | `worker` | Runtime assignment: model + skill. |

If local scripts need a temporary development bridge, keep it private and remove
it before mentor-facing demos. Public docs, help text, MCP tool descriptors, and
fixtures should not teach both grammars.

## Command Grammar

The default command should read like the product promise. `team` asks models to
show up as workers:

```bash
alln team "Pressure-test this launch plan."
alln team --file prompt.md
alln team --lane build --effort deep "Plan this feature."
alln team --lane copy --type landing-page "Rewrite this page."
alln team --lane design --image screen.png --brief "Make this calmer."
```

Core commands:

```bash
alln team [prompt]                 # ask the default team, foreground
alln team start [prompt]           # start a resumable/asynchronous team run
alln team status <run-id>          # show live state for a team run
alln team result <run-id>          # show final result for a team run
alln team show                     # show current default team
alln team edit                     # edit team lineup
alln models                        # list ready/known models on the Bench
alln models add                    # add/configure a model
alln doctor                        # check sources, models, auth, coordinator
alln doctor explain <code>         # explain one failure/recovery code
alln docs                          # generated AI-facing CLI reference
alln docs team                     # generated docs for one command family
alln docs --errors                 # generated error/recovery table
alln docs --schema                 # generated JSON/NDJSON schemas
alln docs --examples               # generated example recipes
alln work [prompt]                 # create a work order
alln work from latest              # promote a plan/result into a work order
alln history                       # list recent runs
alln show latest                   # show one run
alln export latest --format md     # export result bundle
alln dispatch latest --to codex    # send a work order/spec to an execution target
alln pair approve <device-id>      # approve iOS/Mac pairing
```

Agent integration commands:

```bash
alln mcp serve --stdio             # run the MCP stdio server
alln mcp install                   # write MCP config with user consent
alln serve                         # resident Mac agent; deferred until needed
```

`alln mcp` may remain a transport command family, but tool names must use the
new surface (`team_ask`, not `team_ask`). `alln serve` is named here so iOS
and overnight docs have a target, but it is not part of CLI milestone 1.

Do not use `alln prompt` as the primary work-order command. A prompt is the input
object. The product object is a work order, so the command is `alln work`.

`alln doctor` supersedes old detection commands. It should be the headless setup
proof path: find sources, classify auth/readiness, list models, test a small safe
probe where possible, and explain the next fix.

`alln docs` is not generic help text. It is the generated, agent-facing command
manual: commands, flags, schemas, examples, error codes, and recovery ladder.
Human `--help` may stay terse; agents need the full contract.

`alln skills` is real only when the skill library exists. Until then, skill
names may appear inside `alln team show` and run output, but do not imply a
standalone editable library.

Lane shortcuts may exist later:

```bash
alln build "Implement this feature."
alln design screen.png --brief "Improve this screen."
alln copy "Write a launch email."
```

But the canonical primitive remains `team`: one prompt, selected worker lineup,
worker answers, synthesized plan/result.

## Agent-First Quality Bar

`alln` should be pleasant for humans and boringly reliable for agents.

Required rules:

- `--json` returns one complete structured object and no human prose on stdout.
- `--stream` returns NDJSON events on stdout; progress chatter goes to stderr.
- Human output is compact, useful, and never required for automation.
- No ANSI color in non-TTY output; no spinners in JSON/NDJSON.
- Every error has stable `code`, `message`, `agentAction`, `fixCommand`,
  `requiresManual`, `retryable`, and `traceId` fields where applicable.
- Agents run `alln doctor --json` after command failures before escalating.
- `alln doctor --auto-fix` may apply only Allnighter-owned safe repairs where
  `requiresManual == false`.
- `alln docs` is generated from the compiled command/contract registry.
- `alln dev export-contracts --check` or equivalent must fail when generated
  docs, schemas, examples, doctor recovery, or MCP descriptors drift.
- Examples are contract-owned. Do not hand-author agent examples that can drift
  from the parser or JSON schemas.
- Output field names use product vocabulary from day one.

Agent recovery ladder:

1. Parse `error.code`.
2. If `requiresManual == false` and `fixCommand` exists, run once and retry once.
3. If `requiresManual == true`, present `agentAction` and stop.
4. If no fix is known, run `alln doctor explain <code> --json`.
5. Escalate only after doctor and required manual fixes have failed.

Minimum doctor flags:

```bash
alln doctor                  # human-readable diagnostic report
alln doctor --json           # structured report for agents/GUI
alln doctor --quiet          # failed checks only
alln doctor --full           # deeper probes, bounded timeout
alln doctor --auto-fix       # apply safe Allnighter-owned fixes
alln doctor explain <code> --json
```

Minimum doctor JSON shape:

```json
{
  "status": "ok | degraded | critical",
  "binaryVersion": "0.1.0",
  "docsVersionMatchesBinary": true,
  "checks": [
    {
      "name": "codex",
      "status": "ok",
      "detail": "Codex CLI found and authenticated",
      "fixCommand": null,
      "requiresManual": false
    }
  ],
  "models": [],
  "fixes": [],
  "coordinator": {
    "available": false,
    "detail": "foreground CLI only"
  }
}
```

## Output Contract

Default human output should be compact and useful:

```text
Run run_20260615_2214
Team: 4 workers · Build · Deep

✓ Opus / First Principles      1m42s
✓ Sonnet / Skeptic             1m10s
✓ Codex / Maintainer           2m04s
✗ Gemini / Proof Skeptic       auth expired

Plan written by Opus.

Next:
  alln show run_20260615_2214
  alln export run_20260615_2214 --format md
  alln dispatch run_20260615_2214 --to codex --cwd .
```

Machine output should be explicit:

```bash
alln team --json "..."
alln team --stream "..."
alln show latest --json
alln team status run_... --json
alln team result run_... --json
```

JSON is for agents, GUI tests, and external tooling. Markdown is for humans.
The first `alln team --json` output must use the new vocabulary and be rich
enough for the Mac GUI to render without field translation.

Minimum top-level contract:

```text
schemaVersion
contractVersion
teamRun
models
workers
workerAnswers
stages
plan
usage
warnings
errors
nextActions
audit
```

Sketch:

```json
{
  "schemaVersion": 1,
  "contractVersion": "1.0.0",
  "teamRun": {
    "id": "run_20260615_2214",
    "status": "done",
    "origin": "cli",
    "lane": "build",
    "type": "feature",
    "effort": "deep",
    "prompt": "Pressure-test this launch plan.",
    "createdAt": "2026-06-15T22:14:00Z",
    "completedAt": "2026-06-15T22:16:08Z",
    "threadId": null,
    "teamPresetId": "default_deep",
    "planWriterWorkerId": "worker_plan_opus"
  },
  "models": [
    {
      "id": "model_opus",
      "displayName": "Opus 4.8",
      "sourceId": "claude_code",
      "status": "ready"
    }
  ],
  "workers": [
    {
      "id": "worker_first_principles_opus",
      "skillId": "first_principles",
      "skillName": "First Principles",
      "modelId": "model_opus",
      "modelName": "Opus 4.8",
      "sourceId": "claude_code",
      "purpose": "answer",
      "instanceIndex": 0
    },
    {
      "id": "worker_plan_opus",
      "skillId": "plan_writer",
      "skillName": "Plan Writer",
      "modelId": "model_opus",
      "modelName": "Opus 4.8",
      "sourceId": "claude_code",
      "purpose": "plan",
      "instanceIndex": 0
    }
  ],
  "workerAnswers": [
    {
      "workerId": "worker_first_principles_opus",
      "status": "done",
      "durationMs": 102000,
      "markdown": "..."
    }
  ],
  "stages": [
    {
      "id": "stage_plan",
      "purpose": "plan",
      "status": "done",
      "producedByWorkerId": "worker_plan_opus"
    }
  ],
  "plan": {
    "status": "done",
    "writerWorkerId": "worker_plan_opus",
    "stageId": "stage_plan",
    "markdown": "..."
  },
  "usage": {
    "cliCalls": 2
  },
  "warnings": [],
  "errors": [],
  "nextActions": [
    {
      "kind": "showRun",
      "command": "alln show run_20260615_2214 --json"
    }
  ],
  "audit": {
    "traceId": "trace_20260615_2214",
    "runJournalPath": "~/.allnighter/runs/run_20260615_2214/run.json"
  }
}
```

Status enums must be closed and shared: queued, running, done, failed, timedOut,
cancelled, skipped. Errors need stable `code`, human `message`, `agentAction`,
`fixCommand`, `requiresManual`, `retryable`, and optional `sourceId` / `modelId`
/ `workerId`.

Do not ship new CLI JSON with legacy fields such as `TeamRun`,
`workers`, `workerAnswers`, `plan`, or `team_ask`.

The first schema artifact should be a checked-in `TeamRunJSON` fixture. Core
types, CLI output, GUI presenter tests, MCP descriptors, and iOS snapshot
fixtures should converge on that shape instead of inventing parallel contracts.
The exact schema lives in `CLI_Implementation_Contract.md`.

## Plan Writer Rule

For v1, the plan writer is a designated **worker** in the team snapshot: one
model wearing the Plan Writer skill. The reduce/plan stage may run after the
parallel answers, but attribution and JSON point to `planWriterWorkerId`.

This gives the user-facing line:

```text
Plan written by Opus 4.8.
```

without exposing `plan writer` or `plan writer`.

Do not leave this context-dependent for milestone 1. Exotic post-run-only reduce
stages can be introduced later if they still serialize through a clear worker or
stage reference.

NDJSON event names should also use product words:

```text
teamRunStarted
workerStarted
workerAnswered
workerFailed
planStarted
planWritten
teamRunCompleted
teamRunFailed
error
```

## Team As Tool

RB6's core idea is right: Allnighter's team should be callable by other agents.
The vocabulary in that upload is old; the architecture is valuable.

One engine, multiple transports:

```text
CLI:        alln team ...
MCP:        alln mcp serve --stdio
Local API:  alln serve --localhost
GUI/iOS:    shared command handlers or local coordinator
```

Transport names may differ, but operation semantics must map to the same command
handlers:

| Operation | CLI shape | Tool/API shape |
| --- | --- | --- |
| Show available teams/presets | `alln team show --json` | `team_presets` / `team_show` |
| Synchronous ask | `alln team --json "..."` | `team_ask` |
| Async start | `alln team start --json "..."` | `team_start` |
| Status | `alln team status <run-id> --json` | `team_status` |
| Result | `alln team result <run-id> --json` | `team_result` |
| History/recall | `alln history --json` / `alln show <run-id>` | `team_recall` |
| Doctor | `alln doctor --json` | `doctor` |

Agent-facing tools must not expose a richer semantic surface than the CLI. MCP
and local API can be more convenient, but they are not alternate products.

Safety rules:

- Tool calls are local by default.
- Every run writes the same run journal/audit record no matter which transport
  started it.
- Recursive calls are bounded. If an Allnighter worker tries to spawn another
  unbounded team run, return a structured `NESTED_TEAM_BLOCKED` or require an
  explicit depth budget.
- External agents can request team analysis and work orders; dispatch that kills
  sessions, edits files, or spends meaningful quota remains governed by the same
  local permission and confirmation model as the CLI/GUI.
- The product never hides failed workers. Tool results expose partials, failures,
  and warnings honestly.

## App Shell Implication

The GUI should render and send the same typed instructions the CLI exposes.

Preferred implementation shape:

```text
AllnighterCore command/contract registry
-> alln CLI
-> generated docs/help/doctor recovery
-> Mac app presenter/actions
-> optional local coordinator for long-running/resumable work
-> MCP/local API adapters
-> iOS remote client
```

The Mac app should not invent GUI-only semantics. It should issue the same
operations a CLI user could issue: ask team, customize team, stop run, show run,
export, dispatch, pair, revoke.

Implementation detail to decide with mentors:

| Option | Upside | Risk |
| --- | --- | --- |
| GUI shells out to `alln` | Total parity; easy dogfood | Process overhead, brittle parsing, harder live state |
| CLI and GUI share `AllnighterCore` command handlers | Fast, testable, native | Requires discipline to keep parity visible |
| CLI and GUI both talk to local coordinator | Best for iOS/overnight/resume | More daemon complexity early |

Recommended posture: build shared command handlers first; make `alln` the golden
grammar, generated docs, and Works Test surface. Add a local coordinator when
long-running and remote workflows require it.

The GUI may show the exact equivalent `alln` command in an advanced/detail
drawer. That is a trust and education feature, not the primary UI.

## Foreground vs Resident Mode

Not every use requires a background process.

Foreground:

```bash
alln team "..."
```

Runs directly, streams status, writes the run journal, exits when done.

Resident:

```bash
alln serve
alln mcp serve --stdio
```

or an app-installed login/background helper handles:

- iOS remote commands;
- long runs after GUI windows close;
- overnight utilization;
- notifications;
- resumable event streams;
- local MCP/HTTP tool calls.

The product should not pretend the Mac can be controlled while Allnighter is not
running. If resident mode is off, iOS says the Mac is offline. External agents
can still use foreground CLI commands without resident mode.

## Naming Decision Proposal

Adopt:

```text
Product/app: Allnighter
CLI binary: alln
Primary command: alln team
Bench command: alln models
Work-order command: alln work
Background service: defer public name; internal helper is fine
MCP/local API: `team_*` operation names, not `team_*`
URL scheme: allnighter:// for app links, with universal links where needed
```

Do not ship public `alln team` or `alln team` aliases.
Do not ship a long-lived second grammar under `allnighter`. Internal scripts
should move to `alln` during the rename.

## Current Decisions

| Question | Decision |
| --- | --- |
| Primary happy path | `alln team "prompt"`; help text can say "ask your team." |
| `alln ask` | Defer. It is generic and splits the product primitive. |
| GUI integration | Shared `AllnighterCore` command handlers first. Do not shell out just to prove parity. |
| Resident mode | Defer until iOS, overnight, resumable runs, or MCP/local API require it. |
| Lane shortcuts | Defer `alln build/design/copy`; use `alln team --lane ...` first. |
| Binary name | `alln`. |
| Work-order command | `alln work`; help text spells out "work order." |
| Detection command | `alln doctor`; no separate public `detect` command unless implementation needs a hidden/debug alias. |
| AI-facing docs | `alln docs` generated from the command/contract registry. |
| Agent tool operations | Use `team_*`, not `team_*`; CLI command handlers remain semantic owner. |
| Plan writer | A designated worker with the Plan Writer skill; JSON uses `planWriterWorkerId`. |
| Skill library | Defer standalone `alln skills`; milestone 1 uses preset-embedded skills surfaced by `team show`. |
| MCP cutover | Defer public MCP launch until CLI JSON/NDJSON, doctor, docs, and registry drift checks are boring. |
| Implementation detail | `CLI_Implementation_Contract.md` owns exact schemas, events, doctor checks, errors, generated artifact paths, and proof gates. |

## Mentor Feedback Needed

1. Does the `TeamRunJSON` contract in `CLI_Implementation_Contract.md` contain
   enough stable structure for the Mac GUI, MCP clients, and iOS snapshots to
   share one renderer/reducer?
2. Should MCP projection ship immediately after milestone 1, or wait until a real
   external-agent workflow forces it?
3. Should `alln team start/status/result` require resident mode, or can the first
   async run journal work without a long-lived coordinator?
4. Is `alln mcp install` the right subcommand shape, or should MCP setup remain a
   lower-level installer action until the CLI surface settles?

## First Milestone

Build the CLI before more GUI wiring. Start with the schema fixture, then the
commands:

1. Checked-in `TeamRunJSON` fixture using the new names.
2. Contract registry for commands, output schemas, errors, examples, and doctor
   checks.
3. `alln docs` generated from that registry.
4. `alln doctor` plus `alln doctor --json`.
5. `alln doctor explain <code> --json`.
6. `alln models` plus `alln models --json`.
7. `alln team show` plus `alln team show --json`.
8. `alln team "prompt"` using the current default team.
9. `alln team --json "prompt"` matching the fixture.
10. `alln team --stream "prompt"` with NDJSON events.
11. `alln show latest` plus `alln show latest --json`.
12. `alln export latest --format md`.

Works Test:

```bash
alln docs > /tmp/alln-docs.md
alln docs team > /tmp/alln-team-docs.md
alln docs --errors > /tmp/alln-errors.md
alln docs --schema > /tmp/alln-schema.md
alln doctor --json
alln models --json
alln team show --json
alln team "Give me three ways to simplify the Allnighter CLI."
alln show latest --json
alln export latest --format md
alln team --json "Give me one small naming test."
alln team --stream "Give me one tiny event-stream test."
alln dev export-contracts --check
```

The same run must appear in the Mac app without translation or renamed fields.

Explicitly out of milestone 1: full skill-library CRUD, lane shortcut commands,
`alln work`, dispatch, iOS pairing, and resident `serve`.
