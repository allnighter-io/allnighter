# PTD-2 — Universal wake delivery

Status: **READY**
Depends: PTD-1 complete (through 476a3086)
Packet: [`PM_Turn_Delivery.md`](../../PM_Turn_Delivery.md)

## Slice packet

```text
Slice: PTD-2 — --delivery wake + serve hook
Goal:
  1. --delivery wake only with --no-wait on run, pilot handoff, relay dispatch.
     Fail PM_TURN_WAKE_UNCONFIGURED before dispatch if no pmTurnWake.command.
  2. ServeDaemon scans Runs/*/pm-turn.json AND Relays/*/pm-turn.json for new sequences.
  3. Receipt ledger (kind, subjectId, sequence); hook stdin = full PMTurnJSON; retry backoff.
  4. pmTurnDelivery failure projection on status when wake fails.
Out of scope: iOS client, per-CLI wake config
Proof: hermetic serve/hook tests; swift test --filter 'PMTurnWake|ServeDaemon'
Done when: committed `ptd: wake delivery on pm-turn`
```

Commit: `ptd: wake delivery on pm-turn`
