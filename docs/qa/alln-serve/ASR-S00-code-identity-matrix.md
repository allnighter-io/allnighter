# ASR-S00 — Code Identity Matrix (measured)

Date: 2026-08-10
Host: founder Mac
macOS: 15.6.1 (24G90), arm64
Work order: `docs/phases/sprint/alln-serve/ASR-S00-launchd-isolation-harness.md`
SSOT: `docs/phases/Alln_Serve_Hotfixes.md` §8 ASR-S00, §4.5, §4.6, §4.2

## Verdict: ALL 16 CHECKS PASSED

The harness ran `PASS: 16  FAIL: 0  SKIP: 0` and left zero harness launchd
state behind.

## Measurement improvements since previous run

**Deploy is now an atomic rename** (matching `Alln_Serve_Hotfixes.md` §4.3 step 5).
The harness copies the source to a temp path on the same directory, then `mv -f`s
it into place. This swaps inodes — a running process holds the old inode until
exit, and launchd execs the new inode on respawn. The previous `cp` overwrote the
same inode in place, which did not model the product transaction.

**buildTag is now a compiled-in Swift declaration**, not a comment. Each source
copy gets `let __harnessBuildTag = "A"` or `"B"` before compilation. The
heartbeat JSON carries this field as an image-derived identity discriminant.
cdhash remains in the receipt but is labeled **path-derived** — it shells out to
`codesign` against whatever bytes sit at `argv[0]` right now, and cannot
distinguish the loaded image from a replaced file at the same path.

**Case (b) now asserts on buildTag as the primary discriminator.** If the
process respawns with buildTag still "A", the harness records FAIL with the
plain statement that launchd re-exec'd the old image and the new-bytes claim was
wrong.

## 1. Code-identity matrix (3 tracks × 2 cases)

All six cells passed with buildTag confirming the correct binary identity.

| Cell | Track | Case | buildTag before | buildTag after | cdhash(path-derived) before | cdhash(path-derived) after | pid before→after | lastExit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| adhoc-case-a | adhoc | (a) bootout→replace→bootstrap | A | B | `cbb973ff…` | `3a00e380…` | 76766→76825 | exited |
| adhoc-case-b | adhoc | (b) replace underneath→TERM | A | B | `cbb973ff…` | `3a00e380…` | 76920→77560 | N/A |
| apple-dev-case-a | Apple Development | (a) bootout→replace→bootstrap | A | B | `ecd01e4c…` | `a9552e5c…` | 77682→77745 | exited |
| apple-dev-case-b | Apple Development | (b) replace underneath→TERM | A | B | `ecd01e4c…` | `a9552e5c…` | 77812→78438 | N/A |
| developer-id-case-a | Developer ID | (a) bootout→replace→bootstrap | A | B | `544c0c36…` | `865bc31f…` | 78562→78654 | exited |
| developer-id-case-b | Developer ID | (b) replace underneath→TERM | A | B | `544c0c36…` | `865bc31f…` | 78723→79393 | N/A |

**What each case proves:**

- **Case (a):** bootout before bytes change + fresh bootstrap after produces a
  new pid executing the replacement binary. The buildTag transitions from A→B
  alongside the cdhash change. This proves the §4.3 product transaction
  ordering (bootout → atomic rename → bootstrap) is correct and sufficient for
  all three signing tracks, including ad-hoc.

- **Case (b):** atomic rename underneath a loaded KeepAlive job + `kill -TERM`
  produces a respawn where launchd execs the **new** bytes. buildTag is "B" in
  all three tracks. The atomic rename (swapping inodes) means the running
  process held the old inode until SIGTERM, and launchd resolved the path to the
  new inode on respawn. This proves launchd re-execs the replaced binary without
  LWCR rejection, pre-`main` refusal, or `exit 78` — across all three signing
  tracks, including ad-hoc.

No cell recorded buildTag "A" after replacement. No LWCR rejection, no
`exit 78`, no pre-`main` refusal was observed in any log.

## 2. Restart contract (adhoc track)

| Check | Input | Result | Detail |
| --- | --- | --- | --- |
| exit-zero | `exit(0)` | PASS | No respawn (correct). pid 79459 held for 30s. |
| exit-nonzero | `exit(3)` | PASS | Respawned (correct). pid 81096→81704. |
| kill-KILL | `kill -KILL` | PASS | Respawned (correct). pid 81756→82366. |

`KeepAlive = { SuccessfulExit = false }` behaves exactly as §4.2 assumes:
deliberate exit(0) leaves the job loaded but stopped; signal death or nonzero
exit triggers restart.

## 3. Baseline primitives (adhoc track)

| Check | Verdict | Detail |
| --- | --- | --- |
| bootstrap | PASS | Heartbeat appeared, pid 82417. |
| active check | PASS | Heartbeat alive, `beatCount=2`, same pid. |
| TERM restart | PASS | Restarted. pid 82417→83041. |
| KILL restart | PASS | Restarted. pid 83041→83653. |
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
  <key>StandardOutPath</key><string>/Users/mike/Library/Developer/Allnighter/ServeLaunchdHarness/logs/&lt;stamp&gt;/stdout-run.log</string>
  <key>StandardErrorPath</key><string>/Users/mike/Library/Developer/Allnighter/ServeLaunchdHarness/logs/&lt;stamp&gt;/stderr-run.log</string>
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

| Track | Identity | cdhash A (path-derived) | cdhash B (path-derived) |
| --- | --- | --- | --- |
| adhoc | `codesign --force --sign -` | `cbb973fff36693cbf12c2d75e1cf8bc9a0e5c215` | `3a00e380f20fa876a747ed7e0a83113d3901c4af` |
| apple-dev | `Apple Development: Michael Reining (7RU34H8XPD)` | `ecd01e4ce56ab36a82a4e8a0b2baf948d72d14ef` | `a9552e5c607850267420d2a6902fcaf4a7f49b56` |
| developer-id | `Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)` | `544c0c36c6d5810cf96867bcd622715a5efbc718` | `865bc31f49b08149bbdb16af9adf18846d8313d5` |

Two genuinely different cdhashes were produced and verified per track. The
script fails loudly when cdhashes collide (they never did). cdhash is
path-derived via `codesign -dvvv` against `argv[0]`; buildTag is the in-image
identity discriminant.

## 6. Product delta — which branch conditions fired

From `docs/phases/Alln_Serve_Hotfixes.md` §8 ASR-S00 branch conditions and §10
first checkbox:

**§4.5 code-identity assumption (the load-bearing assumption): CONFIRMED.**

> A bootout before the bytes change, followed by a fresh bootstrap after, is
> sufficient to keep a per-user LaunchAgent valid across an ad-hoc-signed binary
> replacement whose cdhash differs.

Case (a) — bootout → atomic rename → bootstrap — passed on all three signing
tracks, including ad-hoc. The buildTag transitioned from A→B in every cell,
proving the replacement binary was loaded. The §4.3 transaction ordering
(bootout before bytes change, atomic rename matching step 5) is proven correct
and sufficient.

**Branch condition: "case (a) fails ad-hoc but passes team-signed → §4.6 wins" — did NOT fire.**

Ad-hoc case (a) passed. No signing slice is required as a prerequisite. The
ad-hoc track (today's shipping reality) survives binary replacement with a
different cdhash, provided the bootout-before-replacement invariant is
maintained.

**Branch condition: "case (b) succeeds where the incident failed → say so plainly" — FIRED.**

Case (b) — atomic rename underneath a loaded KeepAlive job with no rebind, then
kill TERM — passed on all three signing tracks, including ad-hoc. Launchd
exec'd the new bytes on respawn (buildTag:B, image-derived proof). No LWCR
rejection, no `exit 78`, no pre-`main` refusal was observed. The 2026-08-09
LWCR wedge had another cause — changing the cdhash of an ad-hoc-signed binary
underneath a loaded LaunchAgent via atomic rename did **not** reproduce the
incident's exit-78/LWCR behavior on this host on macOS 15.6.1.

**§10 first checkbox: SETTLED.** The code-identity assumption is proven across
all three signing tracks on a real host with an image-derived identity
discriminant. The bootout-before-replacement invariant is confirmed as correct
practice. Whether it is strictly required (since case-b also passed) is an
engineering decision; the conservative posture is to keep it.

**Implication for ASR-S01:** Proceed with the ad-hoc track unchanged. §4.6
signing slice is not a prerequisite. The incident's LWCR root cause requires
separate investigation — changing cdhash alone does not reproduce it.

## 7. Harness improvements (this revision)

- **Deploy is atomic rename** (cp + mv -f), matching §4.3 step 5. The old
  inode stays valid for the running process; launchd resolves the new inode on
  respawn. Deploy failures record the errno text rather than aborting silently.
- **buildTag is compiled into the binary** (`let __harnessBuildTag = "A"/"B"`),
  not a Swift comment. It is the primary image-derived identity discriminant in
  the heartbeat JSON.
- **cdhash is labeled path-derived.** It shells out to `codesign` against
  `argv[0]` and reports whatever bytes sit at that path right now — useful but
  not image-derived proof.
- **Case (b) assertions use buildTag.** If buildTag is "B", the new bytes were
  exec'd (PASS). If buildTag is still "A", launchd re-exec'd the old image
  (FAIL, with a plain statement that the new-bytes claim was wrong).

## 8. Host-state invariant verified

- `launchctl print gui/501/com.allnighter.serve-launchd-harness` → could not find service
- No `*.plist` under `$HARNESS_ROOT`
- `com.allnighter.resident-coordinator` is untouched and running (same state as before)
- Only files created: `tools/ServeLaunchdHarness/{run.sh,main.swift}` and this file
