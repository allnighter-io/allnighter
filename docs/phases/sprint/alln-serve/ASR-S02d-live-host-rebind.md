# ASR-S02d — live-host rebind off the staged path

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §2.1
(delete the staged copy), §4.3 step 4 (bootout before the canonical bytes
change), §8 ASR-S02 (the migration belongs in this slice, not ASR-S05), §10.1 R4
(the frozen-daemon intermediate state this slice closes).

**4 of 5** in the ASR-S02 cut. This is the first slice whose code path is
designed to change the founder's **running** agent. Everything it does is still
driven by an explicit `serve enable`/`repair`; nothing auto-runs at build time.

## 1. Goal

Converging an enabled installation migrates a host whose LaunchAgent still
points at `~/Library/Application Support/Allnighter/CLI/alln`: boot out that
registration, write the canonical plist, bootstrap it, verify, and **only then**
remove the staged bytes. Also supply the launchd bootout to
`CanonicalCLIInstall.beforeBytesChange` so §4.3 step 4 is enforced by the
installer rather than by convention.

## 2. Copy-paste prompt

> Add the staged-path migration to the convergence routine and wire the bootout
> into `CanonicalCLIInstall.beforeBytesChange`, exactly per the Steps. Every
> launchctl and filesystem seam stays injected; no test may run a real
> `launchctl`, touch the real LaunchAgents directory, or delete real staged
> bytes. Do not add `SMAppService`, install-time enablement, or health handshakes.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift` — the
  convergence routine as ASR-S02c left it, and every injected seam.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeStableBinary.swift` —
  `defaultDestinationURL()`, i.e. the staged path being retired.
- `Packages/AllnighterCore/Sources/AllnighterCore/CanonicalCLIInstall.swift` —
  the `beforeBytesChange` hook signature and where it is called.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift
Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift   (runInstallCLI only)
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleTests.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleEnableTests.swift
```

## 5. Do not read / do not touch

- Do not delete `ServeStableBinary` itself — `ServeAutoLaunch` still references
  it and is deleted in ASR-S04. This slice retires the *bytes on disk*, not the
  type.
- Do not touch `ServeDaemon`, `ServeAutoLaunch`, `ServeDesiredState`, any script,
  or `Apps/`.
- Do not add `SMAppService`/`statusForLegacyPlist`, install-time default
  enablement, `--no-serve`, or the active health handshake.
- Do not edit `AllnighterCLI.swift` outside `runInstallCLI`.

## 6. Steps

1. **Detect the legacy registration.** Read the existing plist's
   `ProgramArguments[0]`. It needs migration when it resolves to the staged
   destination rather than the canonical binary. Detect by resolved path, not by
   string matching the label — the label is unchanged across the migration.

2. **Migration order, and it is not negotiable:**
   1. boot out the existing label;
   2. write the canonical plist;
   3. bootstrap;
   4. verify registered (the bounded S02c verify);
   5. **only after a successful verify**, remove the staged bytes.

   If any step before 5 fails, restore the prior plist, re-bootstrap the prior
   job, and leave the staged bytes **untouched**. A host that ends this slice
   with the old agent running is a correct failure; a host with no agent and no
   staged bytes is not recoverable without a reinstall.

3. **Never remove staged bytes on a non-migration path.** Disable, restart,
   repair-to-disabled, and any failed convergence all leave them alone. Removing
   them is exclusively the tail of a *successful* migration.

4. **Wire `beforeBytesChange`.** In `runInstallCLI`, pass a closure that boots
   out the serve label to `CanonicalCLIInstall`'s hook, so §4.3 step 4 happens
   inside the install transaction — after the rollback is preserved, before the
   canonical rename. Two rules:
   - a bootout of a label that is not loaded is **success**, not failure;
   - a genuine bootout failure aborts the install before the bytes change, which
     is the intended behavior — the canonical bytes stay as they were.

5. **Bootout failures are currently swallowed.** ASR-S02c's converge writes
   `do { try bootout(label) } catch { }` on every path. That is right for a
   not-loaded label but wrong for a real failure: convergence then writes the
   plist and bootstraps anyway, which can leave two registrations. Distinguish
   the two — treat "not loaded / no such service" as success and a genuine
   bootout failure as a convergence failure that restores and returns, rather
   than proceeding. The migration in Step 2 depends on this: migrating after a
   failed bootout is how a host ends up with two agents.

6. **Say what happened.** The convergence result reports whether a migration
   occurred, the path migrated from, and whether staged bytes were removed. A
   migration is a notable event on a real host; it is logged and surfaced, never
   silent.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'ServeLifecycleTests|ServeLifecycleEnableTests|InstallCLITests'
```

## 8. Done when

- [ ] A fixture host whose plist names the staged path migrates in exactly the
      Step 2 order, asserted as an **ordered** sequence of seam calls — not just
      "all of them happened".
- [ ] Staged bytes are removed **only** after a successful verify; a failure at
      bootout, plist write, bootstrap, or verify leaves them present.
- [ ] A failed migration restores the prior plist and re-bootstraps the prior
      job.
- [ ] A host already pointing at the canonical binary performs no migration and
      removes nothing.
- [ ] Disable, restart, and repair-to-disabled never remove staged bytes.
- [ ] `beforeBytesChange` boots out the label; a not-loaded label is success; a
      real bootout failure aborts the install with the canonical bytes unchanged
      (asserted byte-for-byte).
- [ ] The result reports the migration explicitly.
- [ ] No test runs a real `launchctl`, writes to the real LaunchAgents dir, or
      deletes real staged bytes.
- [ ] Focused proof passes. One commit, explicit paths.

## 9. Host-state invariant

Committing this slice changes nothing by itself — the migration runs only when
the founder explicitly runs `install-cli`, `serve enable`, or `serve repair`.
The first such run is the moment R4 (§10.1) closes: the agent rebinds to the
canonical binary and the daemon starts tracking installs again. Because Step 2
verifies before deleting and restores on failure, the worst outcome of that run
is the host it already has.
