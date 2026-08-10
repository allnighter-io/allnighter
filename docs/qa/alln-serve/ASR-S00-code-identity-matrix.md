# ASR-S00 — Code Identity Matrix (measured)

Date: 2026-08-10
Host: founder Mac
macOS: 15.6.1 (24G90), arm64
Work order: `docs/phases/sprint/alln-serve/ASR-S00-launchd-isolation-harness.md`
SSOT: `docs/phases/Alln_Serve_Hotfixes.md` §8 ASR-S00, §4.5, §4.6, §4.2

## Verdict: ALL 16 CHECKS PASSED

The harness ran `PASS: 16  FAIL: 0  SKIP: 0` and left zero harness launchd
state behind.

## 1. Code-identity matrix (3 tracks × 2 cases)

Six cells attempted, all passed.

| Cell | Track | Case | cdhash before | cdhash after | Heartbeat resumed | New cdhash? | lastExit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| adhoc-case-a | adhoc | (a) bootout→replace→bootstrap | `2247d1c8…` | `f18c9d42…` | YES | YES | `0` |
| adhoc-case-b | adhoc | (b) replace underneath→TERM | `2247d1c8…` | `f18c9d42…` | YES | YES | N/A |
| apple-dev-case-a | Apple Development | (a) bootout→replace→bootstrap | `9acd0e75…` | `cf19ff3b…` | YES | YES | `0` |
| apple-dev-case-b | Apple Development | (b) replace underneath→TERM | `9acd0e75…` | `cf19ff3b…` | YES | YES | N/A |
| developer-id-case-a | Developer ID | (a) bootout→replace→bootstrap | `42da5353…` | `2e5bafd3…` | YES | YES | `0` |
| developer-id-case-b | Developer ID | (b) replace underneath→TERM | `42da5353…` | `2e5bafd3…` | YES | YES | N/A |

Every cell recorded the new cdhash in the heartbeat after replacement — launchd
exec'd the replacement bytes in all six scenarios. No LWCR rejection, no
pre-`main` refusal, no `exit 78` observed in any log.

## 2. Restart contract (adhoc track)

| Check | Input | Result | Detail |
| --- | --- | --- | --- |
| exit-zero | `exit(0)` | PASS | No respawn (correct). pid stayed `54315` for 30s. |
| exit-nonzero | `exit(3)` | PASS | Respawned (correct). pid `55970 → 56683`. |
| kill-KILL | `kill -KILL` | PASS | Respawned (correct). pid `56727 → 57415`. |

`KeepAlive = { SuccessfulExit = false }` behaves exactly as §4.2 assumes:
deliberate exit(0) leaves the job loaded but stopped; signal death or nonzero
exit triggers restart.

## 3. Baseline primitives (adhoc track)

| Check | Verdict | Detail |
| --- | --- | --- |
| bootstrap | PASS | Heartbeat appeared, pid `57462`. |
| active check | PASS | Heartbeat alive, `beatCount=2`, same pid. |
| TERM restart | PASS | Restarted. pid `57462 → 58157`. |
| KILL restart | PASS | Restarted. pid `58157 → 58778`. |
| bootout cleanup | PASS | Job removed cleanly; no plist left behind. |
| PATH matches plist | PASS | Heartbeat `path` = `$HARNESS_ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin`. No login shell eval. |
| CWD is neutral | PASS | Heartbeat `cwd` = `$HARNESS_ROOT/cwd`. Not under repo or app bundle. |

## 4. Exact working plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.allnighter.serve-launchd-harness</string>
  <key>ProgramArguments</key><array>
    <string>/Users/mike/Library/Developer/Allnighter/ServeLaunchdHarness/bin/harness-adhoc-current</string>
    <string>/Users/mike/Library/Developer/Allnighter/ServeLaunchdHarness/beats/heartbeat-adhoc-case-a.json</string>
    <string>run</string>
  </array>
  <key>WorkingDirectory</key><string>/Users/mike/Library/Developer/Allnighter/ServeLaunchdHarness/cwd</string>
  <key>StandardOutPath</key><string>/Users/mike/Library/Developer/Allnighter/ServeLaunchdHarness/logs/<stamp>/stdout-run.log</string>
  <key>StandardErrorPath</key><string>/Users/mike/Library/Developer/Allnighter/ServeLaunchdHarness/logs/<stamp>/stderr-run.log</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict>
    <key>SuccessfulExit</key><false/>
  </dict>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>ProcessType</key><string>Background</string>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>/Users/mike/Library/Developer/Allnighter/ServeLaunchdHarness/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict></plist>
```

## 5. Signing identities used

| Track | Identity | cdhash A | cdhash B |
| --- | --- | --- | --- |
| adhoc | `codesign --force --sign -` | `2247d1c88223d661104e22cf68990a4ca1503dbc` | `f18c9d42f386818c4a5d548dffe2d988ae45c804` |
| apple-dev | `Apple Development: Michael Reining (7RU34H8XPD)` | `9acd0e754fae7653f08f2e48793bd80d7db46bca` | `cf19ff3b8d717893d379e647afe2533fcce4df0e` |
| developer-id | `Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)` | `42da5353aa7a1a8515a722124e671bbf5908cc3f` | `2e5bafd3d1946e1176346491db072b41906cdd98` |

Two genuinely different cdhashes were produced and verified per track. The
script fails loudly when cdhashes collide (they never did).

## 6. Product delta — which branch conditions fired

From `docs/phases/Alln_Serve_Hotfixes.md` §8 ASR-S00 branch conditions and §10
first checkbox:

**§4.5 code-identity assumption (the load-bearing assumption): CONFIRMED.**

> A bootout before the bytes change, followed by a fresh bootstrap after, is
> sufficient to keep a per-user LaunchAgent valid across an ad-hoc-signed binary
> replacement whose cdhash differs.

Case (a) — bootout → replace bytes → bootstrap — passed on all three signing
tracks, including ad-hoc. The §4.3 transaction ordering (bootout before bytes
change) is proven correct and sufficient.

**Branch condition: "case (a) fails ad-hoc but passes team-signed → §4.6 wins" — did NOT fire.**

Ad-hoc case (a) passed. No signing slice is required as a prerequisite. The
ad-hoc track (today's shipping reality) survives binary replacement with a
different cdhash, provided the bootout-before-replacement invariant is
maintained.

**Branch condition: "case (b) succeeds where the incident failed → say so plainly" — FIRED.**

Case (b) — replace bytes underneath a loaded KeepAlive job with no rebind,
then kill TERM — passed on all three signing tracks, including ad-hoc. Launchd
exec'd the new bytes on respawn. No LWCR rejection, no `exit 78`, no pre-`main`
refusal was observed. The 2026-08-09 LWCR wedge had another cause — changing the
cdhash of an ad-hoc-signed binary underneath a loaded LaunchAgent did **not**
reproduce the incident's exit-78/LWCR behavior on this host on macOS 15.6.1.

**§10 first checkbox: SETTLED.** The code-identity assumption is proven across
all three signing tracks on a real host. The bootout-before-replacement
invariant is confirmed as correct practice. Whether it is strictly required
(since case-b also passed) is an engineering decision; the conservative posture
is to keep it.

**Implication for ASR-S01:** Proceed with the ad-hoc track unchanged. §4.6
signing slice is not a prerequisite. The incident's LWCR root cause requires
separate investigation — changing cdhash alone does not reproduce it.

## 7. Host-state invariant verified

- `launchctl print gui/501/com.allnighter.serve-launchd-harness` → could not find service
- No `*.plist` under `$HARNESS_ROOT`
- `com.allnighter.resident-coordinator` is untouched and running (same state as before)
- Only files created: `tools/ServeLaunchdHarness/{run.sh,main.swift,README.md}` and this file
