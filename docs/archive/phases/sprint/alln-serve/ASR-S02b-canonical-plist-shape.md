# ASR-S02b — canonical LaunchAgent plist shape

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §4.2
(required plist properties + the restart contract), §7 (`exit -> restart`
inference ban).

**2 of 4** in the ASR-S02 cut. S02a landed `ServeDesiredState` (`aa67241f`,
`e9c1b195`). This slice fixes the plist the product generates. It changes the
*shape written on the next enable/repair*; it does not itself write, bootstrap,
or touch the running agent — that is S02c.

## 1. Goal

`ServeLifecycle.AgentPlist` emits every property §4.2 requires, with
`KeepAlive` as a **dictionary** (`SuccessfulExit = false`), so a deliberate
exit `0` stands down instead of respawning every 30 seconds forever.

## 2. Copy-paste prompt

> Replace `ServeLifecycle.AgentPlist` with the §4.2 shape described in the Steps
> and update the plist-writing path to create the directories launchd needs
> before the plist is written. Do not change enable/disable/repair control flow,
> do not call `launchctl`, and do not touch the running agent. Update the
> existing lifecycle tests to the new shape rather than adding a parallel type.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift` —
  `AgentPlist`, its coding keys, and where the plist is encoded and written.
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleTests.swift`
  — the existing plist assertions to update.
- `docs/qa/alln-serve/ASR-S00-code-identity-matrix.md` §4 — the exact plist
  proven to work on this host. Match it; do not invent keys it does not have.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleTests.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleEnableTests.swift
```

## 5. Do not read / do not touch

- Do not change which binary path `ProgramArguments` points at. It still points
  at the staged path in this slice; **S02c** repoints it at the canonical
  binary. Repointing it here would leave the founder's host with a plist naming
  a path no agent has been rebound to.
- Do not touch `ServeDesiredState`, `CanonicalCLIInstall`, `InstallCLI`,
  `ServeStableBinary`, `ServeAutoLaunch`, any CLI file, any script, or `Apps/`.
- Do not call `launchctl`, bootstrap, bootout, or start/stop anything.
- Do not add enable-by-default, `--no-serve`, or health checking.

## 6. Steps

1. **`AgentPlist` gains the §4.2 properties**, encoded with launchd's exact key
   names: `WorkingDirectory`, `StandardOutPath`, `StandardErrorPath`,
   `ThrottleInterval` (`30`), `ProcessType` (`Background`), and
   `EnvironmentVariables` carrying a deterministic `PATH` and `HOME`.

2. **`KeepAlive` becomes a dictionary.** Model it as a small `Codable` type
   encoding `{ "SuccessfulExit": false }` — never a bare `Bool`. §4.2's table is
   the contract: exit `0` means stand-down and must produce **no** restart;
   signal death or a nonzero exit restarts after `ThrottleInterval`.
   `KeepAlive = true` would respawn a refusing daemon every 30 seconds, which is
   the fork-bomb failure in slow motion.

3. **PATH value.** The canonical install directory first, then
   `/usr/bin:/bin:/usr/sbin:/sbin`. Nothing else. It never evaluates a login
   shell. `HOME` is the user's home directory, set explicitly rather than
   inherited.

4. **Directories exist before the plist is written.** The write path must create
   the `WorkingDirectory` (`~/Library/Application Support/Allnighter/ProbeScratch`)
   and the log directory (`~/Library/Logs/Allnighter/`) first. §4.2 is explicit:
   launchd fails the spawn when `WorkingDirectory` is missing, and that failure
   looks exactly like the wedge this packet exists to fix. A missing-directory
   failure must be returned as a failure, never swallowed.

5. **Encoding proof.** The plist is written as an XML property list. Assert
   against the **encoded bytes**, not just the Swift struct — a `Codable` shape
   that round-trips in Swift can still emit the wrong plist type for `KeepAlive`.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'ServeLifecycleTests|ServeLifecycleEnableTests'
```

## 8. Done when

- [ ] The encoded plist contains `<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>`
      — asserted against the serialized output, and a test fails if it degrades
      to `<true/>`.
- [ ] Every §4.2 property is present with the stated values.
- [ ] `EnvironmentVariables.PATH` is exactly the canonical install directory plus
      the four standard directories, and `HOME` is set explicitly.
- [ ] `WorkingDirectory` and the log directory are created before the plist is
      written; a failure to create either is returned, not swallowed.
- [ ] `ProgramArguments` still points at the staged path (unchanged in this
      slice), and a test pins that so the S02c repoint is a deliberate edit.
- [ ] No test performs a real `launchctl` call.
- [ ] Focused proof passes. One commit, explicit paths.

## 9. Host-state invariant

With this slice committed, the founder's host is unchanged: the loaded agent
keeps running, and its on-disk plist is not rewritten because nothing in this
slice writes one. The new shape takes effect the next time `serve enable` or
`repair` runs, which is S02c.
