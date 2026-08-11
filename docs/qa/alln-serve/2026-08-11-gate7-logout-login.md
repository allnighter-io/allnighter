# ASR-S06 gate 7 — serve returns after logout/login

Date: 2026-08-11 (UTC)
Gate: §8 ASR-S06 **gate 7** — after a full console logout and login, `alln serve`
is healthy again without the user launching anything.
Host: second Mac, macOS 15.6 (24G84), arm64. No `/Applications/Allnighter.app`
(§9 clean-host precondition holds).
Signing track: **ad-hoc** (`codesign --sign -`).

## Build identity under test

| Field | Value |
| --- | --- |
| Commit | `ef928f6e76bcbb4fbe27335419650810bc76b795` (tree clean at build time) |
| `contractVersion` | `9.19.0` |
| `binaryVersion` | `1.0.1` |
| Built | `2026-08-11T15:34:14Z` |
| Canonical binary | `~/.local/share/allnighter/bin/alln` |
| cdhash | `e8bf976f73b11885cd3d32f26a650a22f6c39f62` |

The tested binary was rebuilt from that commit via `scripts/rebuild_cli.sh`
immediately before the gate; `alln version --json` reported the same sha, and
`serve status` reported `binary.matches: true` on both sides of the logout.

## Result: PASS

| | before (pre-logout) | after (post-login) |
| --- | --- | --- |
| `state` | `healthy` | `healthy` |
| exit code | 0 | 0 |
| `desiredState` | `enabled` | `enabled` |
| daemon pid | 83101 | **84207** |
| daemonId | `32c158e1-933c-43aa-91c0-a51bf794dc11` | **`f9f47f63-1ef6-48b6-b0f2-3e2abceb5d4b`** |
| daemon `startedAt` | 2026-08-11T15:34:36Z | 2026-08-11T15:51:18Z |
| `supervisor.loaded` | true | true |
| `supervisor.lastExitCode` | null | null |
| `binary.matches` | true | true |
| schedulers registered | 7 | 7 |
| `recovery` | null | null |

Artifacts: `runs/2026-08-11-gates-7-8-10/gate7-before.json`, `gate7-after.json`.

## Why this is launchd's restart and not ours

The pid changing is necessary but not sufficient — the gate's real claim is that
*nothing the user did* started the daemon. Three independent facts:

- Console login at **15:50Z** (`last`: `console … Aug 11 08:50`, local = UTC-7).
  Daemon `startedAt` **15:51:18Z** — 78 s after login.
- The first `alln` command of the session ran at ~**15:52:38Z**, roughly 80 s
  *after* the daemon was already up. A status call cannot have started a process
  that predates it.
- `launchctl print` shows `runs = 1`, `last exit code = (never exited)`,
  `state = running`, `program = ~/.local/share/allnighter/bin/alln`. One start,
  by launchd, at load.

Post-login the daemon also did real work before being asked: `capacityRefresh`
`lastSuccessAt` 15:51:25Z (7 s after start), `notifications` 15:52:32Z,
`pmTurnWake` 15:52:38Z. All seven schedulers present, none with `lastError`.

## Incidental coverage

The pre-gate rebuild moved the LaunchAgent's `program` from
`~/Library/Application Support/Allnighter/CLI/alln` to the canonical
`~/.local/share/allnighter/bin/alln`, and repaired a stale `~/.local/bin/alln`
symlink that still pointed into the repo `.build` directory. This gate is
therefore also the first logout/login test of the migrated program path — it
survived. `properties = runatload | inferred program | managed LWCR | has LWCR`.

## What this does NOT prove

- One logout/login cycle on one host. The 2026-08-09 wedge and the second
  unexplained unload (`2026-08-11-live-host-migration.md`) remain unexplained;
  a clean cycle is absence evidence, not a diagnosed fix. §10.1 R1 stays open.
- Says nothing about a *disabled* job surviving login — that is gate 8.
- Says nothing about deadlines that came due during sleep — that is gate 10.
- Reboot is not covered; only logout/login.

## Reproduce

```bash
alln serve status --json > gate7-before.json   # note daemon.pid
# Apple menu -> Log Out, log back in, open Terminal ONLY
alln serve status --json > gate7-after.json    # must be healthy with a NEW pid
last | grep console                            # login time
launchctl print gui/$(id -u)/com.allnighter.resident-coordinator
```

## Signature

Recorded by the PM agent. Per §8 the founder is the signer.

**Signed:** _pending founder countersignature._
