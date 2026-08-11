# ASR-S06 gate 8 — disable survives login, and install does not re-enable it

Date: 2026-08-11 (UTC)
Gate: §8 ASR-S06 **gate 8** — a `serve disable` the user did not undo survives a
full logout/login, and a subsequent `install-cli` does not silently re-enable it.
Host: second Mac, macOS 15.6 (24G84), arm64. No `/Applications/Allnighter.app`.
Signing track: **ad-hoc** (`codesign --sign -`).

## Build identity under test

Same pinned build as gate 7 — commit
`ef928f6e76bcbb4fbe27335419650810bc76b795`, `contractVersion` 9.19.0,
`binaryVersion` 1.0.1, cdhash `e8bf976f73b11885cd3d32f26a650a22f6c39f62`,
canonical binary `~/.local/share/allnighter/bin/alln`.
`binary.matches: true` throughout.

## Result: PASS

| Step | `state` | `desiredState` | `supervisor.loaded` | launchctl entry | plist on disk | exit |
| --- | --- | --- | --- | --- | --- | --- |
| after `serve disable` | `disabled` | `disabled` | false | absent | absent | 0 |
| after logout/login (console 08:58 local) | `disabled` | `disabled` | false | absent | absent | 0 |
| after `install-cli` | `disabled` | `disabled` | false | absent | absent | 0 |
| after `serve enable` (restore) | `healthy` | `enabled` | true (pid 85621) | present | present | 0 |

Artifacts: `runs/2026-08-11-gates-7-8-10/gate8-before.json`, `gate8-after.json`,
`gate8-after-install.json`, `gate8-restored.json`.

## The disable is a real teardown, not a flag

`alln serve disable --json` returned `outcome: "disabled"`,
`desiredStateReading: "present(disabled)"`, `registryVerified: true`, and
`detail: "com.allnighter.resident-coordinator disabled: bootout settled, plist
removed, stopped verified"`.

Verified independently of the CLI's own report: no `launchctl list` entry, no
`~/Library/LaunchAgents/com.allnighter.resident-coordinator.plist`, and the
prior daemon pid 84207 was **gone** with no orphaned `alln` process anywhere in
`ps`. The disable settles the process rather than leaving it running unmanaged.

## `install-cli` refused, and said why

```
{ "action" : "alreadyInstalled", "onPath" : true,
  "canonicalPath" : "/Users/openclaw/.local/share/allnighter/bin/alln", … }
serve: desired state is disabled — not enabling (use `alln serve enable` to re-enable)
```

Two properties, both wanted: it did not re-enable, and it did not quietly do
nothing either. The install printed the reason and the exact command to undo it,
so a user who *did* want serve back is not left guessing why the install
"didn't work."

## Restore verified

`serve enable` → `outcome: "enabled"`, `plistWritten: true`,
`bootstrapped: true`, `registryVerified: true`. Status then reported `healthy`,
daemon pid 85621 started 15:59:36Z, health responded 15:59:41Z,
`supervisor.loaded: true`, all seven schedulers registered with no `lastError`.
The host was left working.

## Observation (not a gate failure)

While disabled, `serve status` still carried the previous daemon's identity in
its `daemon` block — `pid: 84207`, `daemonId: f9f47f63…`, `startedAt`
15:51:18Z — for a process that no longer existed. It is paired with
`activeHealthRespondedAt: null` and `state: "disabled"`, so the payload as a
whole does not claim a live daemon, and the pid did not resurrect across the
logout. Read in isolation, though, that pid looks live. Worth a look at whether
the field should be nulled or renamed (`lastKnownDaemon`) when
`desiredState == disabled`. Filed as an observation; it did not affect any gate.

## What this does NOT prove

- One disable/login cycle on one host.
- `install-cli` was the `alreadyInstalled` path. A reinstall that actually
  replaces bytes (post-`rebuild_cli.sh`) while disabled is **not** covered here —
  that is the more dangerous variant and remains untested.
- Reboot is not covered; only logout/login.
- Says nothing about §10.1 R1, which stays open.

## Reproduce

```bash
alln serve disable --json
alln serve status --json          # disabled, loaded false
# log out, log back in, Terminal only
alln serve status --json          # must STILL be disabled
alln install-cli --json
alln serve status --json          # must STILL be disabled
alln serve enable --json          # restore, then confirm healthy
```

## Signature

Recorded by the PM agent; logout/login performed by the founder at the machine.
Per §8 the founder is the signer.

**Signed:** _pending founder countersignature._
