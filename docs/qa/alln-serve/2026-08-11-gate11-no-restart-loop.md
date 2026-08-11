# ASR-S06 gate 11 — no restart loop — **PASS, both halves on one build**

Date: 2026-08-11 (UTC)
Gate: §8 ASR-S06 **gate 11** — "induce a persistent stand-down (exit `0`) and
confirm launchd does not respawn and `serve status` reports `degraded` with the
reason. Then induce a crash and confirm it does respawn."
Host: second Mac (Mac mini), macOS 15.6 (24G84), arm64. Ad-hoc track.

**Status: PASS.** Both halves are proven on build `aa8df6ff` — see "CLOSED"
below. This file is written in two layers on purpose: the original partial
finding, which recorded that the halves came from two different builds, is kept
below the closure rather than rewritten. The gap was real when it was written.

## The restart contract under test (§4.2)

| Daemon exit | launchd must | Half |
| --- | --- | --- |
| exit `0` | **not** respawn; status shows `degraded` + reason | stand-down |
| signal death / nonzero | respawn after `ThrottleInterval` | crash |

## Crash half — **PASS**, current build

Gate 3, build `476e9d80`, product label
`com.allnighter.resident-coordinator`. Record:
[`2026-08-11-gate3-crash-restart-PASS.md`](2026-08-11-gate3-crash-restart-PASS.md).

TERM and KILL each produced signal death and a launchd respawn with active
health inside budget; `runs` advanced 1 → 2 → 3. Repeated twice, 24 assertions,
0 failures.

## Stand-down half — observed, but on a build since superseded

Observed while diagnosing the gate 3 failure, on the build **before**
`555f72a8`/`476e9d80`. At that time SIGTERM caused the daemon to exit `0` — a
defect — which incidentally produced exactly the stand-down condition gate 11
asks for, on the real product label:

```text
launchctl print gui/501/com.allnighter.resident-coordinator
  state = not running
  runs = 1
  last exit code = 0
  semaphores = { successful exit => 0 }
```

- **No respawn for 45 s**, polled at 1/2/3/5/8/12/20/30/45 s: job loaded
  throughout, zero `alln serve` processes throughout.
- `alln serve status --json`: `state: degraded`, `supervisor.loaded: true`,
  `supervisor.pid: null`, `supervisor.lastExitCode: 0`,
  `recovery: { reasonCode: "SERVE_STAND_DOWN", command: "alln serve repair" }`.

That is the stand-down half in full — no respawn loop, and the stood-down daemon
visible rather than silently absent (§4.2's requirement).

Full detail:
[`2026-08-11-gate3-crash-restart-FAIL.md`](2026-08-11-gate3-crash-restart-FAIL.md).

## Why it cannot simply be re-run on the current build

ASR-S06b fixed SIGTERM to re-raise, which was the whole point. That removed the
only way a host could induce a supervised exit `0` on demand. The remaining §4.2
exit-`0` paths — admission refusal and unrecoverable configuration — are not
reachable on a healthy supervised host without a new inducer.

So the stand-down half is **not reproducible today**, and this record does not
claim it is.

## Supporting evidence from ASR-S00

ASR-S00 tested both directions of the restart contract on the real launchd
primitive, on an isolated non-product label, across three signing tracks:
`KeepAlive = { SuccessfulExit = false }` with a deliberate exit `0` produced **no**
respawn, and signal death **did** produce one. Matrix:
[`ASR-S00-code-identity-matrix.md`](ASR-S00-code-identity-matrix.md).

That is the platform behaviour proven independently of Allnighter's daemon. What
the product label adds is that Allnighter's own status surfaces it correctly,
which the stand-down observation above shows.

## CLOSED 2026-08-11 — both halves proven on build `aa8df6ff`

ASR-S06j added a self-consuming stand-down marker: a file in the coordinator
directory containing exactly `stand-down`, which the daemon deletes **before**
exiting `0`, so `alln serve repair` recovers on the first try rather than
restarting into another stand-down.

`works-test-serve-continuity.sh --mutate-product-agent stand-down`:

| Assertion | Result |
| --- | --- |
| no canonical daemon process | PASS |
| LaunchAgent **remains loaded** | PASS |
| `launchctl` `last exit code = 0` | PASS |
| `serve status` reports `degraded` | PASS |
| `supervisor.lastExitCode: 0` | PASS |
| status supplies a working recovery command | PASS |
| **no respawn for 35 s** (> 30 s `ThrottleInterval`) | PASS |
| documented recovery restored one healthy daemon and one agent | PASS |

The 35 s window is the point: anything shorter than `ThrottleInterval` would
prove nothing, because launchd would not have respawned yet either way.

`--mutate-product-agent crash-restart` re-run on the **same build**:

```text
TERM summary: time-to-respawn=17s time-to-health=0s
KILL summary: time-to-respawn=29s time-to-health=1s
ALL PASS
```

So both directions of §4.2 now hold on one build, on the product label:
exit `0` → no respawn, visible as `degraded` with a reason; signal death →
respawn with active health. The split-build gap recorded below is closed.

## Verdict (as first recorded — superseded above, kept for the record)

| Half | Status | Label | Build |
| --- | --- | --- | --- |
| crash → respawn | **PASS** | product | `476e9d80` (current) |
| exit 0 → no respawn, degraded + reason | **observed** | product | pre-`555f72a8` (superseded) |
| exit 0 → no respawn | **PASS** | isolated harness | ASR-S00, three signing tracks |

Gate 11 is **not recorded as fully passed on one build**. To close it properly a
stand-down inducer is needed on the current build — see the follow-up below.

## What this does NOT prove

- No single build has shown both halves on the product label.
- "Persistent" stand-down was observed for 45 s, not indefinitely.
- Admission refusal and unrecoverable configuration as exit-`0` sources have unit
  coverage only; neither was induced on a host.
- §10.1 R1 is untouched.

## Follow-up

A stand-down inducer for the current build, so both halves can be demonstrated in
one run. The ASR-S06d injection seam is the obvious pattern — an exact-valued,
loud, non-inherited variable — but the daemon is spawned by launchd from a plist
with a deterministic environment, so the inducer cannot be an environment
variable the harness sets. That design question is why this is a follow-up rather
than part of this record.

## Signature

Recorded by the PM agent from measurements taken during founder-authorized runs.
Per §8 the founder is the signer.

**Signed:** _pending founder countersignature._
