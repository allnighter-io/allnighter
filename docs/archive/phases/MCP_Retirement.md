# MCP Retirement — Allnighter goes CLI-only for agents

Status: **DONE — 2026-07-16.** Cut over in three commits on `feat/design-chain`;
build + full `swift test` green (minus the pre-existing WIP baseline, unchanged);
works test passed (below). Mac app builds clean.
Owner: AllnighterCore + CLI
Updated: 2026-07-16

## Why (first principles)

Allnighter is a local Mac product whose callers are CLI agents (Claude Code, Cursor,
Codex, Grok) — **every one of them has a shell.** The founder killed MCP on two prior
products (XTerminal, Ikiro) for the same reason rediscovered independently by
OpenClaw: **MCP preloads the entire tool surface into every session's context**
(29 tool schemas, thousands of tokens, used or not), while a CLI costs ~one line
("Allnighter is `alln`; run `alln help`") with help on demand. Local CLI-to-CLI is
10–100x more token-efficient, and Allnighter already consumes AgentOS — which is
CLI-only by design. Every simplification so far has improved the product.

**Killing MCP loses zero capability.** Both surfaces are projections of the same
`ContractRegistry`; CLI parity is enforced by tests today. The capability (structured
envelopes, schemas, help, error bridge) lives in the registry and stays. Only the
second wire format dies.

## Consumer check (performed 2026-07-16 — the gate for this cutover)

- **Mac app:** links the library directly; every "MCP" hit in `Apps/AllnighterMac`
  is a doc comment. Zero runtime MCP consumption.
- **iOS/remote:** Supabase + R2 transport (cloud-first spine), not MCP.
- **Repo:** no `.mcp.json`; the only host wiring is `alln mcp install` *printing*
  config for the user to paste. Pre-launch, external consumers = the founder.
- **Shell-less hosts** (Claude Desktop chat, web): not a target user for a local
  CLI-orchestration product.

## Kill list (outright, no shims)

- `MCPServer.swift`; CLI verbs `mcp` / `mcp serve` / `mcp install` / `mcp-install`
- All `MCP*Handlers.swift` (Async/BoostWindow/Defaults/Help/Merged/Pending/Project/
  Relay/Resource/Run/Stalled) + their test suites
- Registry MCP surface: `MCPToolSpec`, `mcpTools`, `ContractRegistry+MCPSurface.swift`,
  tool-level `errors[]`/`idempotency` advertisement, the tool-count ratchet
- `MCPParityTests`, `MCPWireConformanceTests`, `MCPToolContractTests`
- Generated MCP artifacts (regenerate `alln dev export-contracts`; the export set
  shrinks — update the drift-gate expectations)
- Docs sweep: AGENTS.md / phase docs / README references to MCP tools → point to the
  `alln` verbs; delete `MCP_Retirement`-obsoleted phase docs' *routing* references,
  keep history

## Keep (the actual product — untouched)

- `ContractRegistry`, `CommandSpec`s, `OutputSchema`, every public JSON envelope
- The help system (`alln help` topics/search, error→help bridge) — **rewrite content**
  that referenced MCP: host snippets become the one-liner CLI snippet ("add to your
  agent's context: Allnighter is available via `alln`; `alln help <topic>`");
  `mcp_hello` guidance becomes `alln team hello` (already exists, keep it)
- `alln dev export-contracts` (CLI artifacts only)
- NDJSON streaming, exit-code discipline, error catalog

## Guardrails for the executor

1. **No capability may die.** Before deleting any handler, confirm its CLI twin
   exists (parity tests are the map — read them before removing them). Anything
   MCP-only found (there should be nothing) gets a CLI verb FIRST, in its own commit.
2. Help topics must not 404: run the help works test after the content rewrite.
3. The Mac app must not reference deleted symbols (doc comments mentioning "MCP"
   may simply be reworded).
4. Commit in reviewable units: (a) handlers+server+verbs, (b) registry surface +
   tests + regenerated artifacts, (c) help content + docs sweep.

## Works test

```bash
alln team hello --json          # agent front door, quota-free
alln help search "start a relay"
alln pair relay --doc … --json  # the loop, pure CLI
alln nosuchverb                 # error envelope → help bridge still routes
swift test --package-path Packages/AllnighterCore   # green minus known WIP baseline
```
An agent session given only the one-liner context snippet can discover and drive
the full surface. Nothing anywhere instructs configuring an MCP server.

## Evidence (executed 2026-07-16)

- `alln team hello --json` — returns the `AgentHello.Payload` (schemaVersion 2,
  `contractHash` now derived from CLI command names via `ContractRegistry.
  contractHash()`, `routingLaw` in CLI phrasing, `nextToolPlan.tool: "team_start"`,
  33 ready teams). No MCP install/config text anywhere in the payload.
- `alln help search "start a relay"` — top hit `pm_relay` (score 1.00), followed by
  `quickstart`/`team_run_loop`/`tool_selection`/`pending`; prints `next: help_get
  detail=machine topic=pm_relay`.
- `alln nosuchverb` — `unknown command: nosuchverb` on stderr, full usage printed,
  exit code `2` (usage class). Error → help bridge intact.
- `grep -rli mcp docs/generated/alln/` — zero hits except the closed `RunOrigin`
  enum's historical `"mcp"` case value in `pending-item.schema.json` /
  `team-run.schema.json` (persisted-data provenance tag for old runs, not an
  instruction — left in place so historical run/pending records still decode).
- `swift build --package-path Packages/AllnighterCore` clean; `swift build
  --build-tests` clean; full `swift test` — 1379 tests, 8 failures (4 unique:
  `AgentBootstrapTests.testPreflightBugHuntHighOnOneModel`,
  `CodeReviewParallelSafetyTests.testDisjointFindingsTouchesAreSafe`,
  `DefaultConfigDriftTests.testEmbeddedWorkersMatchModelCatalogBuiltIns`,
  `ExitCodeContractTests.testUsageErrorsExitTwoOperationalExitOne`) — confirmed
  identical on the pre-cutover baseline (stash/rerun), unrelated to this cutover.
  `swift test --filter Relay` green (161 tests).
- `alln dev export-contracts --check` green; 18 artifacts (was 19 —
  `mcp-tools.json` no longer emitted).
- Mac app (`xcodebuild -scheme AllnighterMac build`) — **BUILD SUCCEEDED**; zero
  references to deleted MCP symbols found (only doc comments + a few Settings
  help-text strings, all reworded to drop "MCP").

## Activation (the replacement surface)

Retiring MCP could not mean retiring activation — the old `alln mcp install`
was the product's onboarding UX (print a paste-ready host snippet), and losing
it without a replacement would mean agents never find Allnighter at all. The
founder's soft spot: treat the bootstrap snippet as first-class product
surface, not a docs footnote. `alln bootstrap [--host claude|cursor|codex|generic]
[--json]` is that replacement — same consent posture as the old install
(prints, never edits files), now a real CLI verb with a `CommandSpec`, a
`bootstrap` help topic (findable via `alln help search "install"` / "setup" /
"connect agent"), and a `--json` envelope (`{ host, pasteTarget, snippet }`)
so an agent can install itself. The snippet itself (`HelpService.
hostInstructionBlock`, shared SSOT with the `quickstart` topic) teaches the
whole trusted workflow in ~6 lines: `alln team hello --json` for quota-free
discovery, `alln help search`/`alln help get` for anything else, prefer
`--json` envelopes, follow the error envelope's help pointer (`alln doctor
--json` for environment problems), never guess flags. No humans in the loop —
CLI-to-CLI and agent-first is still a thing without MCP.
