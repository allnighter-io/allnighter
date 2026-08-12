# 2026-08-12 — `alln capacity` empty table (warming socket)

```text
Tier: T2 SSOT
Symptom / repro: Bare `alln capacity` while the Dock app is open prints
  "resident snapshot (warming — no settle yet)" and eight
  "unknown — never sampled" rows. `alln capacity --source kimi` live-acquires
  and returns real numbers.
Bug fingerprint: alln capacity + capacity.sock warmingAnswer + CLI accepts
  any successful socket read as a finished bench
Attempt count: 1
Seam: AllnighterCLI.runCapacity → CapacitySocketClient.read →
  CapacitySocketFastPath.snapshot (warming → launch placeholders)
Truth owner: CapacitySocketFastPath.servesAsFreshSnapshot (one clock:
  CapacityPaintGate.gateInterval). Live numbers: CapacityFetch.liveSnapshot.
Lie-prone layer: CWB-S02 instant path treated a successful AF_UNIX read as
  a reading. Warming (`settledAt == nil`, empty windows) is a launch
  placeholder, not a sample.
Regression considered: BUG_PATTERNS launch-quiet / capacity default-ON
  (must not re-arm Dock TCC acquire). Fast path must remain for a fresh
  settled snapshot.
Isolation harness: not required — kill test is pure (warming/stale/disabled
  miss; settled-within-gate hits).
Missing kill test / proof: CapacitySocketTests
  testServesAsFreshSnapshotRejectsWarmingDisabledAndStale
Proof command / founder test:
  scripts/swift-test.sh --filter CapacitySocketTests
  With app PID 27864 running and socket warming:
    alln capacity            → live acquire, not empty table
    alln capacity --source kimi → still works
    alln capacity --disable && alln capacity → zero probes; then --enable
```

## RCA

Two stacked facts. Today's path/probe/classifier commits did not cause this.

### 1. CLI accepted warming as a finished bench (the empty table)

`git log -L` on `AllnighterCLI.runCapacity` socket block: the
`if let answer = socketAnswer { return CapacitySocketFastPath.snapshot }`
branch has accepted any decodeable payload since CWB-S02 (`683e924d`,
2026-08-03). Later edits only excluded `--source` and `--shadow-pane-reader`.
`warmingAnswer` is `settledAt == nil, windows == []`. FastPath maps that to
`neverSampled` placeholders and returns — no live acquire.

That is why `--source kimi` worked: `--source` skips the socket.

### 2. Resident never settles while this app is open (the exposure)

`AllnighterMacApp` (ASR-S04a, `6bacc609`, 2026-08-10 20:35) removed
`CapacityResidentService.setEnabled` and the wake observer. Launch now binds
`capacity.sock` and publishes `warmingAnswer`. The resident scheduler starts
only from `setEnabled`. `loadLive` is process-quiet. So this session (PID
27864, started 09:15, socket mtime 09:15) has no settle path except GUI
Refresh or in-process `postRunSettled`.

`alln serve` is healthy and writes Capacity JSON to disk. It does not publish
to the Dock socket (read-only, other process). Disk freshness is not the
instant path.

"It worked yesterday" is consistent with the app closed (no socket → cold
live path) or a prior session that had settled (Refresh / older build that
still called `setEnabled` and later fired `.deadline`).

### Today's commits (audited, not the cause)

- `27a99e3f` (`AllnighterSupportRoot` / `AllnighterPaths.support`): XCTest
  hosts redirect; production `alln` and `Allnighter.app` do not. Live socket
  is at the real Application Support path. `capacitySocket` still
  `support/Capacity/capacity.sock`. Path resolver did not split CLI vs app.
- `ff0978aa` (`ProbeRecordMerge`): SetupStore probe records only. No
  `CapacityWindow`, socket, or fetch.
- AgentOS `CapacityClassifier` source-scoping (cited `8186144`): no such
  commit in this repo. Classifier labels run-outcome quota facts; it is not
  on the `alln capacity` strip path and cannot suppress a reading.

## What must never be allowed again

A successful `capacity.sock` read is not a capacity reading. Instant serve
requires a settle instant younger than `CapacityPaintGate.gateInterval`.
Warming and stale miss and live-acquire once.

## Resident settle — not papered over

Re-arming `setEnabled` at Dock launch would restart the 30m deadline under
the app's TCC identity (the reason ASR-S04a removed it) and cannot take
effect without relaunching PID 27864 (forbidden this turn). Serve-owned
refresh does not update the socket. Contained fix is the CLI freshness
contract. The fast path still serves instantly when the resident *has*
settled inside the gate (GUI Refresh or post-run).
