# ASR-S02a — serve desired-state store

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §2.2
(disable persists across updates), §4.1 (`serve-desired-state.json`), §7 (the
`user disable -> repair` inference ban).

**1 of 4** in the ASR-S02 cut: **S02a** desired-state store (this), **S02b**
canonical plist shape, **S02c** convergence transaction + live-host rebind,
**S02d** install-time default enablement with `--no-serve`.

Pure addition. Nothing calls this store yet, so committing it changes no host
behavior at all.

## 1. Goal

One owner for the answer to "does this user want the background scheduler?",
durable across CLI updates, so a later update can never silently re-enable a
service the user disabled.

## 2. Copy-paste prompt

> Add `ServeDesiredState` to `Packages/AllnighterCore/Sources/AllnighterEngine/`
> exactly as the Steps below specify, plus focused tests. Do not wire it into
> `ServeLifecycle`, `InstallCLI`, the CLI, or anything else — this slice only
> creates the owner. Every path is derived from an injected home directory so
> tests never touch the real one.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift` —
  where serve paths are derived today and the `Result`/outcome vocabulary in
  use. Do not edit it.
- `Packages/AllnighterCore/Sources/AllnighterCore/CanonicalCLIInstall.swift` —
  the atomic-write and injected-`homeDirectory` pattern to copy.
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleTests.swift`
  — test style for this target.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeDesiredState.swift        (new)
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeDesiredStateTests.swift (new)
```

## 5. Do not read / do not touch

- Do not edit `ServeLifecycle`, `ServeStableBinary`, `ServeAutoLaunch`,
  `InstallCLI`, `CanonicalCLIInstall`, any CLI file, any script, or `Apps/`.
- Do not call `launchctl`, write a plist, or start/stop anything.
- Do not add an `alln serve enable/disable` command path — that is S02c.

## 6. Steps

1. **Location.** `ServeDesiredState.storeURL(homeDirectory:)` =
   `<home>/Library/Application Support/Allnighter/serve-desired-state.json`.
   Home is injected; never read the real home inside the type.

2. **Shape.** `{ schemaVersion: Int, state: "enabled" | "disabled", updatedAt: Date }`
   and nothing else. §4.1 is explicit: no credentials, no vendor data, no paths,
   no pid. Adding any other field is out of scope.

3. **`read(homeDirectory:) -> Reading`** where `Reading` distinguishes:
   - `.absent` — no file. **Absence is not "disabled."** The caller-facing
     `effectiveState` for `.absent` is `enabled` (§4.1 migration rule), but the
     reading must still report that it was absent so S02c can log a migration
     rather than pretend a file existed.
   - `.present(state, updatedAt)`.
   - `.unreadable(reason)` — file exists but is corrupt, truncated, or a future
     schema version. **This must not silently become `enabled`.** Report it, and
     expose `effectiveState` as the last-known-safe value: `enabled` only when
     the corruption is total, and never overwrite the file as a side effect of
     reading it.

4. **`write(_ state:homeDirectory:) -> Result<Void, Failure>`.** Creates the
   parent directory if absent, writes atomically (temp file in the same
   directory + rename), stamps `updatedAt` from an injected clock closure so
   tests are deterministic. Stable failure code `SERVE_DESIRED_STATE_WRITE_FAILED`.

5. **No inference.** The type exposes no "should I enable?" helper and makes no
   launchd or process observation. It answers exactly one question: what did the
   user last ask for. Deciding what to do about that is S02c's job.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'ServeDesiredStateTests'
```

## 8. Done when

- [ ] Absent file reads `.absent` with `effectiveState == .enabled`, and the
      absence is distinguishable from an explicit `enabled` file.
- [ ] A written `disabled` state reads back `disabled` — including after a
      simulated "later update" that rewrites nothing.
- [ ] Corrupt JSON, truncated JSON, and a higher `schemaVersion` each read
      `.unreadable` with a reason, and reading never rewrites the file.
- [ ] Write is atomic: a failure mid-write leaves the prior file intact
      (assert by pointing the temp write at an unwritable location).
- [ ] The injected clock controls `updatedAt`; no test asserts on wall time.
- [ ] No test touches the real home directory.
- [ ] Focused proof passes. One commit, explicit paths.

## 9. Host-state invariant

With this slice committed, the founder's host is unchanged: a new type with no
callers. No file is created on disk until something calls `write`, which nothing
does until ASR-S02c.
