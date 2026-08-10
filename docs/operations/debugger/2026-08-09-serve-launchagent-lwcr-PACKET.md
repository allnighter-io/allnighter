# Debug Packet — `alln serve` LaunchAgent dead (LWCR / EX_CONFIG)

**Date:** 2026-08-09  
**Bug Hunt run:** `AC9D2295-329F-4417-A5EC-FA65D010EB1C` (`code_bug_hunt_max`)  
**Host evidence:** dogfood Mac (founder)

```text
Tier: T3 Critical
Symptom / repro:
  App closed. Capacity history advanced on ~30m cadence until ~10:45am PDT,
  then went silent. LaunchAgent com.allnighter.resident-coordinator shows
  KeepAlive but never holds a pid: last exit 78 EX_CONFIG, runs 6700+,
  state "spawn scheduled". Manual `alln serve` starts and health→available.
  `launchctl kickstart -k` does not revive it.

Bug fingerprint:
  orphan LaunchAgent com.allnighter.resident-coordinator
  + macOS LWCR/BTM refuse before exec (exit 78)
  + ServeAutoLaunch not on alln run / app launch
  + capacity/Pending/Boost depend on a live serve with app closed

Attempt count: 1 (investigation; no product fix yet)

Seam:
  launchd/xpcproxy/BTM (LWCR) ↔ ~/Library/LaunchAgents plist
  ↔ alln serve (never reached under LA)
  ↔ CapacityRefreshScheduler / Notify / Pending wake
  ↔ recovery callers (Loop ServeAutoLaunch only)

Truth owner:
  macOS Background Task Management / LWCR admission for the LaunchAgent
  (console: "Unable to get updated LWCR … error 0x3 - No such process";
   "Unable to update LWCR with smd: 3"). Product truth for "is serve up?"
  remains ServeDaemonProbe / coordinator.json — not the plist existing.

Lie-prone layer:
  KeepAlive LaunchAgent present on disk → looks like reboot/crash recovery
  exists. CODE_RED left the orphan LA "on purpose" after `serve install`
  was deleted. Help/tests assert there is no `serve install`. Users (and
  agents) infer launchd will restart serve; it cannot even exec.

Regression considered:
  - Re-adding `serve install` without SMAppService/BTM-correct registration
    recreates this exact death.
  - Widening ServeAutoLaunch to every `alln run` without opt-out / admission
    could spawn duplicate daemons (admission exists; still noisy).
  - Relying on Dock app CapacityResidentService alone reverts Probe_Freshness
    founder ruling ("scheduler requiring app open is wrong").

Isolation harness:
  Optional: throwaway LaunchAgent with same ProgramArguments vs a known-good
  `launchctl bootstrap` of a fresh label after `launchctl bootout` + BTM
  forget — proves whether repair is "re-register" vs "code change".
  Not required to name cause; console already proves pre-exec refuse.

Missing kill test / proof:
  1. `log show` / kickstart: LA still cannot initialize (LWCR) until fixed.
  2. After recovery path ships: kill serve → trigger recovery verb →
     `alln serve --health` → available within N seconds; capacity stamp
     advances with app closed.
  3. Doctor (or serve --health) must fail closed when orphan LA is registered
     but LWCR-blocked (do not report "scheduled/keepalive" as healthy).

Fix boundary (ranked — founder pick):
  A. Immediate honesty: bootout/unload broken LA (stop 10s thrash); doctor
     surfaces "orphan LaunchAgent LWCR-dead; run `alln serve` or loop …".
  B. Product recovery without reboot: call ServeAutoLaunch.ensureRunning from
     high-frequency human/agent fronts that imply a live bench —
     at minimum Mac app launch + `alln bootstrap` / `alln capacity` /
     optionally `alln run` (opt-out preserved). Do NOT invent a second
     capacity scheduler.
  C. Durable login continuity (separate founder ruling): supported install
     via modern BTM/SMAppService (or documented manual `alln serve` +
     login item), replacing the orphan plist. Delete retired install myth.

Proof command / founder test:
  launchctl kickstart -k gui/$(id -u)/com.allnighter.resident-coordinator
  # RED today: still exit 78; log "Unable to get updated LWCR"
  alln serve --health --json   # foregroundOnly when dead
  # After B: open app OR `alln loop step` OR chosen ensureRunning front
  # → health available; Capacity/_newest_success.json advances app-closed
```

## Product progress (2026-08-09)

Code floor for this bug has shipped under `docs/phases/Serve_Continuity.md`:

| Slice | Commit (approx) | What |
| --- | --- | --- |
| SC-S00 | `05afee05` | LaunchAgent honesty in doctor / health |
| SC-S01 | `867d72e3` | `serve repair` + lifecycle remove |
| SC-S03 | `861578aa` | Demand heal on `alln run` + Mac app launch |
| SC-S04a | `ef75ec50` | Staged stable binary under Application Support |
| SC-S04b | `b7eecd78` | `serve enable` / `disable` on staged binary |
| SC-S02 | `5de87193` | install-cli refreshes staged binary + rebinds when enabled |

**Still open for this packet:** logout/login host proof (`SC-S04-logout-login.md`).
SC-S05 admission recycled-PID is **separate** hardening — do not fold into this
debug track.

## Repro (confirmed at intake)

1. `launchctl print gui/$(id -u)/com.allnighter.resident-coordinator`  
   → `last exit code = 78: EX_CONFIG`, `needs LWCR update | managed LWCR`
2. Console every ~10s:  
   `Service could not initialize: Unable to get updated LWCR for (262713FF-…, …/com.allnighter.resident-coordinator.plist, 501), error 0x3 - No such process`  
   `Unable to update LWCR with smd: 3`
3. Same binary: `alln serve` under a normal shell (even with `XPC_SERVICE_NAME` set) stays alive; health → `available`.
4. Therefore EX_CONFIG is **not** ServeDaemonAdmission, not a Swift exit(78), not PATH — **xpcproxy never hands off to alln**.

## What brings serve back (update after 2026-08-09 code floor)

| Trigger | Restarts `alln serve`? | Notes |
| --- | --- | --- |
| Product `alln serve enable` LaunchAgent (staged binary) | **Yes after logout/login — unproven host** | Code shipped; SC-S04 host proof owed |
| Orphan KeepAlive / kickstart (old CODE_RED plist) | **No** when LWCR-wedged | Use `alln serve repair` / `disable` |
| `alln run` / Mac app launch | **Yes** | SC-S03 `ServeAutoLaunch.ensureRunning` |
| `alln loop` ensureRunning sites | **Yes** | Unchanged |
| Manual `alln serve` | **Yes** | Always |
| `install-cli` / `rebuild_cli` | Refreshes staged binary; rebinds if enabled | SC-S02 |

## What must never be allowed again

- Shipping or leaving a KeepAlive LaunchAgent that product code no longer installs, refreshes, or diagnoses — so the machine looks "supervised" while BTM silently refuses exec.
- Documenting or implying reboot/login restores serve when the only LA on disk is an orphan from deleted `alln serve install`.
- Treating `alln run` or Dock launch as sufficient for serve-hosted continuity without an explicit `ensureRunning` (or a supported BTM-registered agent).

## Dissent / open

- Whether `alln run` should auto-serve (noise vs weekly-reboot users) is a founder call; Loop-only was intentional for URN notifications.
- App launch ensuring serve (in addition to CapacityResident) may double-probe briefly; history-recency arbiter already tolerates that (CapacityRefreshScheduler docs).
- Bug Hunt Max seats may refine fix ranking; host console evidence for LWCR is already decisive for "why it did not restart."
