# Live-host migration — first real run of the ASR-S02d rebind

Date: 2026-08-11 (UTC)
Build under test: `0612b8ec` (`scripts/rebuild_cli.sh` → `install-cli`)
Signing track: ad-hoc (dogfood track, `scripts/build-universal.sh` semantics)
Operator: founder-approved recovery (High-Risk Stop cleared before running)
Slices exercised: ASR-S01a–d, ASR-S02b, ASR-S02c, ASR-S02d, ASR-S03d

This is **not** an ASR-S06 release gate. Gates 7–10 (logout/login,
disable-survives-login, three-cycle rebuild, sleep) remain unrun. This records a
real-host migration that happened during development and closes §10.1 **R4**.

## 1. Why it was run

Mid-session inspection found the host in an unsupervised state:

| Observation | Value |
| --- | --- |
| launchd job | **not loaded** — `launchctl print` found no service |
| Plist on disk | present, mtime 2026-08-10T23:29Z, **old shape** |
| Plist `KeepAlive` | `1` (bare boolean — the §4.2 respawn-loop shape) |
| Plist `ProgramArguments[0]` | `~/Library/Application Support/Allnighter/CLI/alln` (staged) |
| Running daemon | pid 61396, **PPID 1 (orphaned)**, started 23:33Z |
| Daemon executable | `~/Library/Developer/Allnighter/CLI/arm64-apple-macosx/debug/alln` |
| Active obligations | 0 |

The scheduler was alive and answering health, but launchd was not supervising
it: a daemon death would have silently ended background scheduling. Something
during the session booted the job out without re-bootstrapping it. **The cause
was not identified** — the plist mtime (23:29Z) and daemon start (23:33Z)
bracket the ASR-S02b/S02c window, but no step was proven responsible. This is
recorded as unknown rather than guessed.

## 2. What was run

```bash
bash scripts/rebuild_cli.sh   # builds to Library/Developer scratch, then install-cli
```

Install output (verbatim):

```text
serve enabled: com.allnighter.resident-coordinator migrated from
  /Users/mike/Library/Application Support/Allnighter/CLI/alln to
  /Users/mike/.local/share/allnighter/bin/alln — staged bytes cleaned
already installed: /Users/mike/.local/bin/alln → /Users/mike/.local/share/allnighter/bin/alln
Canonical binary: /Users/mike/.local/share/allnighter/bin/alln
```

## 3. Result — measured after the run

| Check | Before | After | Verdict |
| --- | --- | --- | --- |
| launchd job state | not loaded | `running`, pid 12567, `last exit code = (never exited)` | PASS |
| Agent `program` | staged path | `~/.local/share/allnighter/bin/alln` | PASS |
| `KeepAlive` | `1` | `{ SuccessfulExit => 0 }` | PASS (§4.2) |
| `ThrottleInterval` | absent | `30` | PASS |
| `ProcessType` | absent | `Background` | PASS |
| `WorkingDirectory` | absent | `…/Allnighter/ProbeScratch` | PASS |
| Log paths | absent | `~/Library/Logs/Allnighter/alln-serve-{stdout,stderr}.log` | PASS |
| `EnvironmentVariables` | absent | `HOME=/Users/mike`, `PATH=<canonical>:/usr/bin:/bin:/usr/sbin:/sbin` | PASS (§4.2) |
| Staged bytes | present | directory empty | PASS (verify-then-delete) |
| Serve processes | orphan pid 61396 @ PPID 1 | exactly one, pid 12567 | PASS |
| Daemon pid vs agent pid | n/a | equal (12567) | PASS |
| Health | pid-inferred `listening: true` | **active handshake**, `listening: true`, port 53096 | PASS (§5.2, ASR-S03d) |
| `binaryGitSha` | `21c77439` (stale) | `0612b8ec` (HEAD) | PASS |

## 4. What this proves, and what it does not

**Proves, on a real host:** the S02d migration performs bootout → canonical
plist → bootstrap → verify → staged-byte removal in order and reaches a
supervised, single-daemon, canonical-binary end state; the S02b plist shape is
what launchd actually accepts; the S03d active handshake answers against a real
daemon; and PATH, launchd, and the running daemon now name **one** executable.

**Does not prove:** logout/login survival (gate 7), disable persistence across
login (gate 8), the three-cycle rebuild loop (gate 9), or sleep/wake (gate 10).
It is a single migration on one host, not a repeated proof — and the migration
path it exercised is the *staged→canonical* one, which by design can only ever
run once per host. A second run takes the already-canonical path instead.

**Does not bear on §10.1 R1.** The LWCR/exit-78 wedge did not appear here, but
one clean migration is not evidence about a fault whose cause is still
unidentified. Gate 9 remains the detector.

## 5. Packet effect

- **§10.1 R4 (frozen daemon) is CLOSED.** The agent tracks installs again.
- §10.1 R1, R2, R3 unchanged.
- ASR-S06 gates 1–11 all still unrun and unsigned.
