# ASR-S06j — a stand-down inducer, so gate 11 can be proven on one build

Status: **ready**
Priority: **P2 — gate 11's stand-down half is only evidenced on a superseded build.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §4.2
(restart contract, stand-down visibility), §8 host matrix item **11**.
Evidence:
[`2026-08-11-gate11-no-restart-loop.md`](../../../../qa/alln-serve/2026-08-11-gate11-no-restart-loop.md).

## 1. Why this exists

Gate 11 needs both halves on one build:

| Half | Status |
| --- | --- |
| crash → respawn | **PASS** on the current build (gate 3) |
| exit `0` → no respawn, `degraded` + reason | observed only on the build **before** `555f72a8` |

The stand-down half was observed because SIGTERM exiting `0` was itself a defect.
ASR-S06b fixed that — correctly — and in doing so removed the only way a host
could induce a supervised exit `0`. The remaining §4.2 exit-`0` paths (admission
refusal, unrecoverable configuration) are not reachable on a healthy supervised
host without an inducer.

## 2. Why the ASR-S06d pattern does not transfer

ASR-S06d's seam is an environment variable, read by the CLI process the harness
invokes. That works for an **install**, which the harness runs directly.

It cannot work here. The daemon is spawned by **launchd** from a plist with a
deterministic `EnvironmentVariables` block (§4.2), so nothing the harness exports
reaches it. Adding the variable to the plist would mean mutating the real plist
to run a test — worse than the problem.

**Therefore the inducer must be a file**, read by the daemon at startup, in a
path the daemon already owns.

## 3. Required properties

1. **Exact content, not mere presence.** The file must contain a specific literal
   (e.g. `stand-down`). Any other content, or an empty file, induces nothing.
2. **Consumed on read.** The daemon deletes the marker *before* standing down.
   This is the property that keeps the inducer from becoming a permanent outage:
   without it, `alln serve repair` would start a daemon that immediately stands
   down again, and the bench could not be recovered by the documented command.
3. **Loud.** Announce on stderr and in the serve log before exiting, naming the
   marker path.
4. **Exit `0` with a stand-down reason**, so §4.2's contract is exercised
   exactly: launchd must not respawn, and `serve status` must report `degraded`
   with `supervisor.lastExitCode: 0` and a recovery command.
5. **One check point**, at daemon startup, before schedulers register.

If (2) cannot be done safely — for example if the daemon cannot delete the file
before launchd observes the exit — **stop and say so**. An inducer that can wedge
the founder's bench into an unrecoverable loop is worse than an unproven gate.

## 4. Copy-paste prompt

> Add a startup marker file that makes `alln serve` stand down: on daemon start,
> if a specific file in the Allnighter coordinator directory contains exactly
> `stand-down`, delete the file, log loudly to stderr and the serve log, and exit
> `0` with a stand-down reason before any scheduler registers. Deleting it first
> is what keeps `alln serve repair` able to recover. Then add a
> `--mutate-product-agent stand-down` scenario to
> `scripts/works-test-serve-continuity.sh` that writes the marker, restarts the
> job, and proves §4.2: launchd does **not** respawn, and `serve status` reports
> `degraded` with `lastExitCode: 0` and a working recovery command. It must
> restore a healthy host on every exit path.

## 5. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift` — startup
  order, and where the SIGTERM handling from ASR-S06b lives.
- `Packages/AllnighterCore/Sources/AllnighterEngine/AllnighterPaths.swift` — the
  coordinator directory the daemon already owns.
- `docs/phases/Alln_Serve_Hotfixes.md` §4.2, especially: *"A stood-down daemon is
  never silently absent: the job is loaded with no process, and `serve status`
  reports `degraded` with `supervisor.lastExitCode = 0`, the stand-down reason,
  and a recovery command."*
- `scripts/works-test-serve-continuity.sh` — the `crash-restart` scenario as the
  model, and its cleanup trap.

## 6. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeDaemonSignalTests.swift
scripts/works-test-serve-continuity.sh
```

## 7. Do not touch

The plist shape, `KeepAlive`, `ThrottleInterval`, `ServeLifecycle`, any
scheduler, `ServeStatusJSON`, the ASR-S06d install injection seam.

## 8. Steps

1. **Marker check first**, before schedulers register, so a stand-down is clean
   rather than half-started.
2. **Delete before exiting.** Order matters: consume, then log, then exit `0`.
   A test must prove the file is gone after the stand-down.
3. **Exit `0`, not a signal.** ASR-S06b made SIGTERM die by signal; this path
   must do the opposite, and both must keep working. A test must prove both
   directions still hold.
4. **The scenario restarts the job** the supported way (`alln serve repair`, or
   bootout/bootstrap through the existing helpers), then asserts:
   - no process for the canonical binary;
   - the launchd job **still loaded**;
   - `launchctl print` shows `last exit code = 0`;
   - **no respawn** across a bounded observation — say how long, and note that
     `ThrottleInterval` is 30 s so the window must exceed it to mean anything;
   - `serve status` reports `degraded`, `supervisor.lastExitCode: 0`, and a
     recovery command that can actually change the state.
5. **Then restore and prove it.** Run the recovery command, wait for healthy, and
   assert the host ends healthy with one daemon and one agent. The cleanup trap
   is the backstop, not the plan.
6. **Failing-first** on the unit test: prove the marker path is reached and the
   process exits `0` before wiring the scenario.

## 9. Works Test

```bash
scripts/swift-test.sh --filter 'ServeDaemonSignalTests|ServeDaemonAdmissionTests'
bash scripts/rebuild_cli.sh
bash scripts/works-test-serve-continuity.sh --assert identity-and-receipts   # unchanged
```

The PM runs the destructive scenario on the live host:

```bash
bash scripts/works-test-serve-continuity.sh --mutate-product-agent stand-down
```

**Do not run it yourself.**

## 10. Done when

- [ ] Marker with exact content induces a stand-down; wrong content or empty
      induces nothing.
- [ ] The marker is deleted before the exit, proven by test — `serve repair`
      recovers on the first try.
- [ ] Stand-down exits `0`; SIGTERM still dies by signal. Both proven.
- [ ] Scenario proves no respawn past `ThrottleInterval`, job still loaded,
      `last exit code = 0`, and `serve status` `degraded` with a working recovery.
- [ ] Host healthy at the end, on every exit path.
- [ ] Failing-first observed. Focused tests and `rebuild_cli.sh` pass.
- [ ] One commit.

## 11. Host-state invariant

The scenario deliberately stops the founder's scheduler and must restore it. The
inducer is inert without the marker file, and self-consuming once used.
