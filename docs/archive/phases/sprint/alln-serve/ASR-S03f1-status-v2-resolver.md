# ASR-S03f1 — `ServeStatusJSON` v2 shape and state resolver

Status: **done, one rule corrected** — `41f39215` (Cursor Grok 4.5)
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §5.2
(the v2 shape and the five states) and §7 (every inference ban this resolver
must refuse to make).

**9 of N** in the ASR-S03 cut. Closes the S03e2 wiring
(`69a52bbd`, `e1e7448d`, `e99cb778`), which made the receipt tell the truth.
This slice makes something finally *read* it.

Two deliverables:

1. The `ServeStatusJSON` v2 type, exactly §5.2's shape.
2. A **pure** resolver: inputs in, one status out, no I/O.

Wiring `alln serve status` / `--health` to emit it, and the §5.3 exit codes, is
**S03f2** — do not touch any CLI file here.

## 1. Goal

`alln serve --health --json` today emits `CoordinatorHealth` v1, whose top-level
state is `available`. That word answers "is a process there?" §5.2 replaces it
with five states that answer "is useful scheduling alive?" This slice builds the
shape and the decision, isolated from all the I/O that feeds it, so the decision
can be tested exhaustively.

## 2. Why the resolver must be pure

Every §7 inference ban is a rule about **how inputs combine**. If the resolver
also gathers its own inputs, each ban's negative proof needs a fake filesystem,
a fake launchctl, and a fake socket to exercise one boolean. That is how bans
end up untested and how §10.1's "proof that could never fail" gets written.

A pure function taking already-gathered observations makes every ban a table
row. Gathering is S03f2's problem.

## 3. Copy-paste prompt

> Add `ServeStatusJSON` (schemaVersion 2) matching §5.2 of
> docs/phases/Alln_Serve_Hotfixes.md exactly, and a pure resolver that maps
> already-gathered observations to one of the five top-level states. No file
> reads, no launchctl, no sockets, no Date() inside the resolver. Do not touch
> any CLI file, CoordinatorHealth, or ServeDaemonProbe.

## 4. Read only

- `docs/phases/Alln_Serve_Hotfixes.md` §5.2 (shape + five states), §6 (required
  vs optional scheduler ids), §7 (the ban table — **every row is a test case**).
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeRuntimeReceipts.swift`
  — `SchedulerRow`, `SchedulerState` (including `stopped` from `e99cb778`), the
  required-vs-optional id split.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeDesiredState.swift`
  — the desired-state enum and its `Reading`.
- `Packages/AllnighterCore/Sources/AllnighterCore/CanonicalCLIInstall.swift`
  — `CodeIdentity`, the existing type for §5.2's `expectedCodeIdentity` /
  `runningCodeIdentity`. Do not invent a second one.
- `Packages/AllnighterCore/Sources/AllnighterCore/CoordinatorHealth.swift`
  — v1, for reference only. It stays; nothing is migrated in this slice.

## 5. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusJSON.swift          (new)
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeStatusResolverTests.swift (new)
```

## 6. Do not touch

`CoordinatorHealth`, `ServeDaemonProbe`, `ServeHealthClient`, `ServeLifecycle`,
`ServeDaemon`, any scheduler, anything under `Sources/AllnighterCLI`, any
script, `Apps/`, `ContractRegistry`.

## 7. Steps

1. **The shape is §5.2, field for field**: `schemaVersion: 2`, `desiredState`,
   `state`, `supervisor{kind,label,loaded,authorization,pid,lastExitCode}`,
   `binary{path,expectedGitSha,runningGitSha,expectedCodeIdentity,runningCodeIdentity,matches}`,
   `daemon{daemonId,pid,startedAt,activeHealthRespondedAt}`, `schedulers[]`,
   `recovery`. Do not add fields, drop fields, or rename them to taste. Codable,
   stable key order.

2. **One input struct** carrying already-gathered observations: desired state,
   supervisor observation, binary expectation vs. what the running daemon
   reports, the active-health handshake result, and the receipt reading. Every
   input that could be unknown is `Optional` or has an explicit `unknown` case —
   there is no "assume healthy" default anywhere.

3. **The resolver is `static func resolve(_ input:) -> ServeStatusJSON`.** No
   `FileManager`, no `Process`, no networking, no `Date()`. Timestamps arrive as
   inputs.

4. **`healthy` is the narrowest state.** It requires *all* of: desired enabled,
   authorization enabled, supervisor loaded, an **active** health response whose
   daemon id and pid match the durable record, `binary.matches == true`, and
   every **required** scheduler id present. Anything short of that is not
   healthy. A live pid alone never contributes.

5. **`binary.matches` is identity, not version.** False when either the git sha
   or the code identity differs. Two builds sharing a version string are not the
   same executable (§7 `version -> identity`).

6. **Scheduler rules from §6.** A missing *required* id is `degraded`. A missing
   *optional* id (`cloudRelay`) is omitted, never painted failed, and never
   degrades. A `failed` row degrades. A `stopped` row means the daemon stood
   down — pair it with the supervisor observation rather than reading it as a
   failure.

7. **`degraded` always names why.** `recovery` is non-null for every
   non-healthy, non-disabled state and carries a stable reason code plus one
   real command. It is never a bare `true`/`null` that forces the caller to
   guess.

8. **Absence never becomes an inference.** If an input is unknown, the resolver
   fails closed to `degraded` with an explicit "unknown" reason. It never
   upgrades unknown to healthy, and it never reports a locally computed value as
   an observed one.

## 8. Works Test

```bash
scripts/swift-test.sh --filter 'ServeStatusResolverTests'
```

## 9. Done when

- [ ] **Every row of §7's ban table has a test that fails when the ban is
      violated.** Write the table first. A ban with no failing case is not
      implemented, and a resolver that cannot be made to report the wrong state
      on demand has not been tested.
- [ ] Named cases, each asserted: plist present + job absent → `degraded`;
      recycled live pid, no handshake → `degraded`; equal version, different
      cdhash → `degraded` with `matches == false`; missing `capacityRefresh` row
      → `degraded`; missing `cloudRelay` → still `healthy`; a `failed` row →
      `degraded`; desired disabled + nothing loaded → `disabled`; macOS approval
      revoked → `requiresApproval`; stood-down daemon (loaded, exit 0, no
      process) → `degraded` naming stand-down, not `disabled`.
- [ ] `healthy` is unreachable if any single one of its six conditions is
      dropped — six tests, one per dropped condition.
- [ ] Every non-healthy, non-disabled result has a non-null `recovery` with a
      reason code and a command string.
- [ ] The resolver performs no I/O — assert by construction (no `FileManager`,
      `Process`, `URLSession`, or `Date()` in the file) and say so in the commit.
- [ ] Round-trips through `CoreJSON` with §5.2's exact keys.
- [ ] `CoordinatorHealth` is unmodified and still what the CLI emits. No
      command's output changes in this slice.
- [ ] No test writes outside a temp directory. One commit, explicit paths.

## 10. Host-state invariant

Inert. This slice adds a type and a function that nothing calls yet. No command
changes, no daemon behavior changes, no file on disk changes.

## 11. Closeout — 2026-08-11

Landed `41f39215`. Re-verified outside the seat: 34 tests green, exit 0. Purity
confirmed by inspection — `FileManager`, `Process`, `URLSession`, and `Date()`
appear in the file only inside the doc comment asserting their absence. Scope
held to the two permitted files.

Coverage matches the work order: 12 `testBan_*` cases (one per §7 row), 9 named
scenarios, 6 healthy-drop cases, 3 fail-closed cases, and a §5.2 key round-trip.

**One rule is wrong and is corrected in
[`ASR-S03f1b`](ASR-S03f1b-stopped-required-scheduler-degrades.md).**
`testStoppedRowDoesNotAloneDegradeWhenOtherwiseHealthy` asserts that every
required scheduler `stopped`, with the daemon still answering the handshake,
resolves to `healthy`. That is the "serve is running but nothing is happening"
wedge — the answer §5.2 exists to stop status from giving. The shutdown
reasoning behind it does not apply, because at shutdown the handshake dies and
the supervisor path already returns `degraded`.

**Tooling note.** Two `scripts/swift-test.sh` invocations returned the
`alln-test-guard: raw 'swift test' is blocked` refusal instead of running, while
a third identical invocation ran clean to exit 0. The wrapper is the only
sanctioned path to the Green Wall, so an intermittent refusal is worth watching.
Not diagnosed further here; recorded so a second sighting is recognised as a
pattern rather than a one-off.
