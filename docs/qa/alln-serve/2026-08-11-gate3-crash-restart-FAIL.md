# ASR-S06 gate 3 — TERM/KILL crash restart — **FAIL**

Date: 2026-08-11 (UTC)
Gate: §8 ASR-S06 **gate 3** — "TERM then KILL: launchd supplies a new pid and
active health within 15 s; no extra daemon and no Dock process."
Host: second Mac (Mac mini), macOS 15.6 (24G84), arm64.
Build under test: `06581a5f` (binary built from `8ac10de3` + ASR-S06a script),
contract 9.19.0, ad-hoc.
Signing track: **ad-hoc**.

## Result: FAIL — SIGTERM stands the daemon down instead of restarting it

The TERM half never completed. No replacement daemon appeared within the
script's 90-second budget, so the KILL half never ran.

## Measured

`kill -TERM <daemon pid>` on a healthy host, then polled for 45 s:

| t after TERM | original pid alive | launchd job loaded | live `alln serve` processes |
| --- | --- | --- | --- |
| 1 s | no | yes | **none** |
| 5 s | no | yes | **none** |
| 12 s | no | yes | **none** |
| 30 s | no | yes | **none** |
| 45 s | no | yes | **none** |

`launchctl print gui/501/com.allnighter.resident-coordinator`:

```text
state = not running
runs = 1
last exit code = 0
semaphores = { successful exit => 0 }
```

`alln serve status --json`:

```json
"state": "degraded",
"supervisor": { "loaded": true, "pid": null, "lastExitCode": 0 },
"recovery": { "reasonCode": "SERVE_STAND_DOWN", "command": "alln serve repair" }
```

## Why it fails — the daemon converts a signal into a clean exit

§4.2's restart contract:

| Daemon exit | launchd behavior | Used for |
| --- | --- | --- |
| exit `0` | **no restart** | deliberate stand-down |
| signal death or nonzero exit | restart after `ThrottleInterval` | crash, wedge, external kill |

and the mechanism §4.2 specifies:

> `SIGTERM` settles runtime receipts and then **re-raises `SIGTERM` under the
> default handler**, so launchd observes signal death and restarts.

The re-raise does not happen. The daemon exits **0**. launchd then behaves
exactly as configured — `KeepAlive = { SuccessfulExit = false }` means an exit 0
is a deliberate stand-down and must not be respawned — so it correctly declines
to restart.

**launchd and the plist are right. The daemon's signal handling is wrong.** This
is not a launchd/LWCR problem and it is not a KeepAlive misconfiguration.

## What works correctly, and should not be lost in the fix

The status layer is honest about it. §4.2 requires that "a stood-down daemon is
never silently absent: the job is loaded with no process, and `serve status`
reports `degraded` with `supervisor.lastExitCode = 0`, the stand-down reason,
and a recovery command." That is exactly what it reported —
`degraded`, `lastExitCode: 0`, `SERVE_STAND_DOWN`, `alln serve repair`. The
observation machinery from ASR-S03 did its job; only the behaviour underneath is
wrong.

## Consequence

Any `SIGTERM` reaching the daemon — a shell `kill`, a `pkill`, a tidy-up script,
a system-initiated termination during shutdown or a forced logout — permanently
stops background scheduling, with the launchd job still loaded and no process.
No restart, no retry, no notification. The user finds out when something that
should have happened in the background did not.

**This is a candidate explanation for the two "unexplained" launchd events in
§10.1 R1** — 2026-08-09 and 2026-08-11 — both of which presented as a job that
was not running with nothing obviously wrong. That is precisely the fingerprint
of this defect. It is a *candidate*, not a diagnosis: neither incident recorded
an exit code at the time, so the link cannot be confirmed retroactively. R1 stays
open, and the follow-up slice must not claim to have closed it.

## Host state

Restored. `alln serve repair` returned the host to `healthy` (pid 95957,
`binary.matches: true`, seven schedulers). The gate script's own cleanup also
ran repair, but reported "still not healthy" because it sampled during the new
`starting` window (ASR-S03f4) and treats `starting` as failure — a script defect
recorded in the follow-up slice, not a host problem.

## Follow-up

[`ASR-S06b`](../../phases/sprint/alln-serve/ASR-S06b-sigterm-must-restart.md) —
make `SIGTERM` re-raise under the default handler so launchd observes signal
death, and teach the gate script that `starting` is not a failure state.

## Reproduce

```bash
alln serve status --json                       # note daemon.pid, expect healthy
kill -TERM <pid>
sleep 45
launchctl print gui/$(id -u)/com.allnighter.resident-coordinator | grep -E "state|last exit"
# observed: state = not running, last exit code = 0, no respawn
alln serve repair                              # restore
```

## Signature

**No founder signature required.** §8 names gates **7, 8, 9 and 10** as the
ones needing a human at the machine, and only those. This gate was executed
and measured by the PM agent on the live host; the record above is the
evidence. An earlier draft of this file carried a "pending founder
countersignature" line — that was ceremony this packet does not ask for, and
it is removed.
