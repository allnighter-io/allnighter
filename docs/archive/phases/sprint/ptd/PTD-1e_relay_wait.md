# PTD-1e — PMTurnStatusWait + pilot/relay --wait-for

Status: **READY**
Depends: PTD-1d
Packet: [`PM_Turn_Delivery.md`](../../PM_Turn_Delivery.md)

## Slice packet

```text
Slice: PTD-1e — shared wait helper + relay status --wait-for
Goal: Add PMTurnStatusWait (or extend existing) for pilot status and relay-status:
      --wait-for parked|terminal --timeout N (required pair).
      Return waitOutcome matched|timedOut|terminalMismatch; embed pmTurn on match.
      Register PM_TURN_WAIT_TIMEOUT (alias RELAY_WAIT_TIMEOUT); exit 3 on timeout.
Out of scope: RunCLI --no-wait ack (next slice), teaching flip, wake
Truth owner: PilotCLI, RelayCLI, shared wait helper
Works Test: hermetic wait match/mismatch/timeout tests
Proof: swift test --filter 'PMTurnStatusWait|PilotCLI|RelayCLI'
Done when: committed `ptd: pilot and relay status --wait-for`
```

## Spec reminders

- Pilot: `parked` = awaitingPM|escalated; refuse `terminal` on pilot with usage error
- Relay: `parked` and `terminal` legal
- No `running` target on relay
- Mirror team status wait cadence (50ms–5s)
- agentAction on timeout: same waiter with longer timeout

Commit: `ptd: pilot and relay status --wait-for`
