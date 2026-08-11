# ASR-S06 gate 10 — a deadline that came due while asleep

Date: 2026-08-11 (UTC)
Gate: §8 ASR-S06 **gate 10** — a scheduler deadline that falls due during system
sleep fires promptly on wake (§4.4: within 2 minutes), rather than sleeping
through and waiting out the original interval.
Host: second Mac (**Mac mini**), macOS 15.6 (24G84), arm64.
Signing track: **ad-hoc**.

Sleep was induced by **Apple menu → Sleep**, not a lid close — this host has no
lid. `pmset` confirms a genuine system sleep (`Entering Sleep state due to
'Software Sleep pid=84820'`), which is the state §4.4 is about.

## Build identity under test

Same pinned build as gates 7 and 8 — commit
`ef928f6e76bcbb4fbe27335419650810bc76b795`, `contractVersion` 9.19.0,
cdhash `e8bf976f73b11885cd3d32f26a650a22f6c39f62`.

## Timeline (UTC)

| Time | Event | Source |
| --- | --- | --- |
| 15:59:51 | pre-sleep reading captured | `gate10-before.json` |
| **16:02:00** | **system sleep begins** (`Software Sleep pid=84820`, 627 s) | `pmset -g log` |
| 16:04:36 | `probeRecordRefresh` deadline comes due — **asleep** | pre-sleep `nextWakeAt` |
| 16:04:44 | `capacityRefresh` deadline comes due — **asleep** | pre-sleep `nextWakeAt` |
| **16:12:27** | **wake** (`Wake from Deep Idle … HID Activity`) | `pmset -g log` |
| 16:13:21 | `capacityRefresh` succeeds — **+54 s after wake** | `gate10-after.json` |
| 16:13:54 | `probeRecordRefresh` succeeds — **+87 s after wake** | `gate10-after.json` |
| 16:15:34 | post-wake reading captured | `gate10-after.json` |

Both deadlines fell strictly inside the sleep window. The gate's precondition was
genuinely met — this is not a scheduler that merely happened to tick.

## Result: PASS

| Scheduler | pre-sleep `lastSuccessAt` | post-wake `lastSuccessAt` | latency after wake | pre-sleep `nextWakeAt` | post-wake `nextWakeAt` |
| --- | --- | --- | --- | --- | --- |
| `capacityRefresh` | 15:59:44Z | **16:13:21Z** | **+54 s** | 16:04:44Z | 16:18:21Z |
| `probeRecordRefresh` | null | **16:13:54Z** | **+87 s** | 16:04:36Z | 16:18:54Z |

- `lastSuccessAt` advanced to a time **after the wake**, inside the 2-minute §4.4
  budget, on both rows.
- `nextWakeAt` was **rescheduled forward** from the missed deadline
  (16:04:44 → 16:18:21 = fire time + the 5-minute interval). It is not the stale
  pre-sleep deadline, which is exactly the failure shape §10.1 R2 warned about.
- No `lastError` on any of the seven schedulers; `state: healthy`.

Artifacts: `runs/2026-08-11-gates-7-8-10/gate10-before.json`,
`gate10-after.json`.

## The daemon survived sleep — it was not restarted into looking healthy

Daemon pid **85621**, `startedAt` 15:59:36Z, is identical on both sides of the
sleep. The same process that held the missed deadline is the one that fired it.
Had launchd restarted the daemon on wake, every scheduler would have re-armed
from a fresh start and the measurement would have proved nothing about catch-up.

## Measurement honesty

`notifications` and `pmTurnWake` also show post-wake successes, but they are
**excluded** from the verdict: both run on a ~10 s cadence and would advance
under any behavior, asleep-through or not. A gate that counted them could not
fail. The verdict rests only on the two 5-minute schedulers whose deadlines
provably fell inside the sleep window.

## What this does NOT prove

- One sleep of ~10.5 minutes. Long sleeps (hours, overnight), repeated
  sleep/wake cycles, and sleep across a date boundary are untested.
- Deep-idle wake by HID activity only. Scheduled/maintenance dark wake is not
  covered — `pmset` shows dark-wake requests were registered, but the gate
  measured a user wake.
- Says nothing about a deadline that comes due while the daemon is *disabled*,
  or across a reboot.
- §10.1 R2 is answered for this case, not closed in general.

## Reproduce

```bash
alln serve status --json > gate10-before.json    # note soonest nextWakeAt + lastSuccessAt
# Apple menu -> Sleep. Stay asleep past that deadline (10 min is safe).
# Wake, wait 2 min:
alln serve status --json > gate10-after.json
pmset -g log | grep -iE "Entering Sleep|Wake from"   # prove the deadline fell inside the window
```

## Signature

Recorded by the PM agent; sleep/wake performed by the founder at the machine.
Per §8 the founder is the signer. No PM-executed caveat applies: the sleep and
wake the gate tests were the founder's, and `pmset` corroborates both
independently of anything the agent did.

**Signed: founder, 2026-08-11.**

This closes §10.1 **R2**'s "only proof that counts" — a real sleep past a real
deadline. R2's design concern (every scheduler is a `Task.sleep` poll) is
answered for this case by measurement, not by a fake-clock test.
