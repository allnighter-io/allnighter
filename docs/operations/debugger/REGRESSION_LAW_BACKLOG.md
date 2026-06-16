# Regression Law Backlog

DEBUGLOG entries without a wall-reachable regression law are tracked here until
each pattern has a gate or test. Expired rows should fail the green wall once
meta-gates exist.

- `GUI-visible work is not fixed until a layout-watcher passes a real render`: owner GUI workflow/Mac app proof harness, status PROCESS-ENFORCED (Debugger + GUI_Workflow + shipped harness: `GUIFixture.swift` + `scripts/gui_proof.sh` + `.claude/agents/layout-watcher.md`); remaining wall-gate is `scripts/check_gui_proof.sh` (S05) flagging a `Sources/*.swift` diff with no watcher PASS/waiver, expiry 2026-06-23

## Closed

- `Mac app launch is process-quiet before explicit setup/recheck/run`: CLOSED
  2026-06-16 by the Launch Authority TCC hotfix (H0–H6). Wall-reachable gates:
  `AppModelTests.testLoadCachedSetupStateDoesNotStartDetection` /
  `testFullSetupProbeWithoutUserIntentDoesNotDetect` (cold launch + non-user
  full probe never start detection),
  `LaunchAuthorityProbeTests` (neutral probe CWD + `smoke:false` runs no model
  call), and a `scripts/check.sh` guard asserting `scripts/dev.sh` builds
  outside the repo. Proof: `bash scripts/check.sh`.
