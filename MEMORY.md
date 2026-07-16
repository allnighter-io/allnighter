# MEMORY.md

Machine-maintained repo posterior — operational truth learned under load, distinct from `AGENTS.md` (the constitution).
Any seat may cite lines and propose corrections; consolidation compresses, never appends forever.

- trap — Cursor headless permissions: `cursor-agent` merges global `~/.cursor/cli-config.json` with project `.cursor/cli.json` at process start; `--trust` does not bypass; denials are bare `Rejected:` with no reason; editing permissions mid-turn locks that turn's shell. Burned: piloted deliveries #2/#3 (2026-07-16). Verify: run `git status` at turn start.
- trap — stale binary during verification: CLI behavior checks need `swift build --package-path Packages/AllnighterCore --product alln` first; test runs alone do not refresh the `alln` product. Burned: Pilot DX round-1 review (2026-07-16). Verify: rebuild, then re-run the command you are judging.
- trap — verdict-tail authoring: prefer `pilot handoff --verdict X --handover-file file.md` (raw markdown); legacy `--file` needs exactly one trailing fenced verdict block (parser fence fix d96f332a). Burned: relay_af304745 round 1.
- trap — external Cursor auto-commit on `feat/design-chain` sweeps dirty source into its own commits; commit promptly in logical units, stage explicit paths only. Burned: pm-read-only slice (180148de).
- proof — the wall: `swift test --package-path Packages/AllnighterCore` (+ `xcodebuild test -scheme AllnighterMac` for Mac app targets); contract drift gate: `alln dev export-contracts --check`. `scripts/check.sh` also trips a pre-existing spawn-policy scan (`SpawnResolvingCommandRunner`) unrelated to most slices.
- proof — known-red baseline: `AgentBootstrapTests.testPreflightBugHuntHighOnOneModel` (9 vs 10 workers) is pre-existing; do not chase in unrelated slices; report separately from your own results.
- seat — `model_cursor_grok_45` (Cursor Grok 4.5): five clean piloted slices in a row, ~5–15 min rounds, honest failure reporting, splits commits as ordered (week of 2026-07-14). `model_sonnet` (Claude Code): fast + honest dev seat, proven in works tests.
- decision — no API keys, ever (subscriptions/logins only). Allnighter does no git (workers commit; GitObserver reads only). MCP retired — CLI is the only agent surface. No up-front slicing — PM prose per round. Read-only-by-prompt is banned (mechanism or nothing).
- decision — house method: one substrate with projections on top; convention before mechanism; delete outright (no archives, no shims); no fake data in real app paths; agent-first structured envelopes always.
