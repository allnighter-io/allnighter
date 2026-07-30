# PTD-1f — Run no-wait delivery ack + teaching flip

Status: **READY**
Depends: PTD-1e
Packet: [`PM_Turn_Delivery.md`](../../PM_Turn_Delivery.md)

## Slice packet

```text
Slice: PTD-1f — delivery.path wait on all --no-wait + teaching flip
Goal:
  1. RunCLI, PilotCLI, RelayCLI --no-wait --json ack includes delivery.path: wait
     with exact status --wait-for command (prefer absolute alln path when known).
  2. Team status --wait-for terminal returns pmTurn on match (if not already).
  3. Teaching flip: HelpTopicRegistry, Bootstrap, TeachingSnippet, recipes,
     ContractRegistry, AsyncTeamContracts (retire pollStatus primary nextAction),
     RELAY_ROUND_IN_FLIGHT agentAction → status waiter not poll.
  4. Run `alln dev export-contracts` and commit generated artifacts if contract changed.
Out of scope: PTD-2 wake (--delivery wake)
Proof: swift test --filter 'PMTurn|RunNoWait|PilotCLI|HelpTopic'; export-contracts --check
Done when: committed `ptd: no-wait delivery ack and teaching flip`
```

Commit: `ptd: no-wait delivery ack and teaching flip`
