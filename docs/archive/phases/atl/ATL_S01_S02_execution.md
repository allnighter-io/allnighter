# ATL-S01 + ATL-S02 — unattended relay execution brief

**PM seat: Sonnet 5 (Claude Code). Dev seat: Grok 4.5.** Unattended relay.

Product truth is [`docs/phases/Agent_Team_Loop.md`](../Agent_Team_Loop.md) —
already hardened and frozen by an adversarial Grok pass, all open questions
resolved. **Do not redesign it.** This file only scopes what to execute and in
what order.

Read `AGENTS.md` first. Read `MEMORY.md` at the repo root and cite honored lines.

---

## Scope: ATL-S01, then ATL-S02. Nothing else.

The packet defines four slices. **Only the two CLI slices are in scope here.**
ATL-S03 and ATL-S04 are Mac GUI and require a surface brief plus the Visual
Proof Gate (`docs/gui/GUI_Workflow.md`, `docs/gui/Visual_Proof_Gate.md`) — a
sighted human-reviewed gate that an unattended loop cannot satisfy. Do not start
them. Do not touch `Apps/AllnighterMac`.

The packet's own law is **CLI before GUI**, so this ordering is its instruction,
not a reduction of it.

### ATL-S01 — kickoff brief (CLI + Engine)

Full spec: packet §"Kickoff brief — exact field / owner" and §ATL-S01.

Ship:

- `RelayCoordinator.Config.kickoffMessage` → durable `RelayState.kickoffMessage`
  → `RelayPMPrompt.Context.kickoffMessage`
- CLI `--message <text>` / `--message-file <path>`, mutually exclusive, empty
  after trim refused with `CLI_USAGE_ERROR` when either flag is present
- Detached child argv preserves the message flags (parent strips only
  `--no-wait` / delivery flags, per existing detach law)
- Prompt section `## Kickoff brief (founder)` with the text **verbatim**, placed
  after the PM identity / doc / rounds-left blocks and before the dev-report
  blocks
- **Consume once**: clear `kickoffMessage` after the first PM turn is durably
  recorded. Later rounds never re-inject.

Three ways to fail this slice, all named in the packet:

- kickoff stored in `founderNote` — that field is **resume-only**
- kickoff living only in GUI state
- silent truncation of a long brief — refuse loud instead

CLI with neither flag stays allowed for back-compat. Do not hard-require it.

### ATL-S02 — `alln loop stop` (CLI + Engine)

Full spec: packet §"Stop settlement — exact order" and §ATL-S02.

Ship `RelayCoordinator.stop(relayId:reason:)` and the verb
`alln loop stop` (renamed from `pair relay stop` — LVC, 2026-07-30), plus
`RelayState.founderStoppedReason = "founder stopped"`.

The ten-step settlement order in the packet is exact. Follow it. In particular:

- **A PM Turn write is required** on a founder-stop transition. A stop that
  kills a process without a durable `stopped` + PM Turn fails the slice.
- Idempotent on `done` / `stopped` — return current state, do not rewrite
  `stoppedReason`, do not write a second PM Turn.
- Allowed on `escalated` as abandonment. Do **not** map that to
  `RELAY_INVALID_STATE`.
- Stop **wins** over an in-flight round. `RELAY_ROUND_IN_FLIGHT` is a
  start/resume/adopt guard, not a stop guard.
- After founder stop, `isResumable == false`.
- Never stamp `stopped` over work you know is still live — non-zero and
  `RELAY_STOP_FAILED` instead. Refusing to lie beats a convenient success.

Reuse the identity-checked terminate helpers from Process Ownership *inside*
`stop`; do not make `ProcessOwnershipSurface.kill` the whole path.

---

## Contract and version

Both slices add CLI surface, so they need a `ContractRegistry.contractVersion`
bump and a regenerate:

```bash
swift build --package-path Packages/AllnighterCore --product alln
./Packages/AllnighterCore/.build/debug/alln dev export-contracts
```

The contract is **currently clean at 6.4.0** — a green wall was just achieved
(2525 tests, 0 failures). Additions take a minor bump. Never hand-edit anything
under `docs/generated/`.

Bumping the version breaks assertions that pin it. There are four known pin
sites; all were just updated for the 6.4.0 cut, so follow the same set:

- `Packages/AllnighterCore/Sources/AllnighterCore/Resources/Fixtures/team_run.json`
- `ContractRegistryTests.swift` (version literal **and** the M1 command boundary
  set, if the new verb belongs to M1)
- `FixtureRoundTripTests.swift` (version literal, and add a comment line for the
  bump — that file documents each one)

## Proof

Filtered while iterating. The full wall at slice close:

```bash
swift test --package-path Packages/AllnighterCore --scratch-path /tmp/atl-<slice>
./Packages/AllnighterCore/.build/debug/alln dev export-contracts --check
```

**Baseline is 2525 tests, 0 failures.** Any regression from that is yours and
must be fixed or reported, not left. Run the wall in the **foreground** and wait
for it — roughly two minutes.

Works Tests are specified per slice in the packet; implement them as written,
including the negative cases.

## Commits

One commit per slice minimum; smaller is fine. Explicit paths only. The tree has
two pre-existing dirty files —
`docs/phases/Work_Recovery_And_PM_Continuity.md` and `.relay-smoke-spec.md` —
leave both alone. Never `git reset --hard`, never rewrite history on
`feat/design-chain`.

## Stop conditions

- The packet's spec contradicts the code → stop and report which, do not pick a
  winner.
- A slice would require touching the Mac app → stop; that is out of scope.
- The wall regresses below the 2525 / 0 baseline and the cause is not obvious →
  stop and report.
- Do not weaken, skip, or narrow any existing assertion to get green. An honest
  red is worth more than a green that hides drift.
