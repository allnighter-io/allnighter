# ASR-S01b — install onto the canonical binary

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §2.1
(PATH symlink points at the canonical executable), §4.3 (transaction), §4.6
(identity recorded, not version equality), §5.3 (exit codes).

**2 of 3** in the ASR-S01 cut. ASR-S01a landed `CanonicalCLIInstall`
(`d60efa8a`) but nothing calls it yet. This slice makes `install-cli` use it.

## 1. Goal

`alln install-cli` copies the running binary to the canonical path and points
the PATH symlink at **the canonical path**, not at wherever the running binary
happened to live. The JSON reports the canonical path and the recorded code
identity.

## 2. Copy-paste prompt

> Rewire `InstallCLI.run` to install through `CanonicalCLIInstall` and symlink
> PATH to the canonical binary, extend `InstallCLI.JSON` per Step 3, and update
> `runInstallCLI` to surface the new failure codes with the right exit codes. Do
> not touch launchd, `ServeLifecycle`, `ServeStableBinary`, any script, or
> anything under `Apps/`. Keep every seam injectable — tests must never write to
> the real home directory.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterCore/CanonicalCLIInstall.swift` —
  the owner from S01a: its `install(...)`, `Report`, `Failure`, and the
  `beforeBytesChange` hook.
- `Packages/AllnighterCore/Sources/AllnighterCore/InstallCLI.swift` — current
  `run(_:)`, `Request`, `JSON`, `Outcome`.
- `Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift` lines
  2600–2660 only — `runInstallCLI`, `Options`, and how failures are emitted.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterCore/InstallCLI.swift
Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift   (runInstallCLI only)
Packages/AllnighterCore/Tests/AllnighterCoreTests/InstallCLITests.swift
```

## 5. Do not read / do not touch

- No `Apps/`, no `scripts/`, no `AllnighterEngine` source, no launchd call.
- Do not touch `ServeStableBinary`, `ServeLifecycle`, or `ServeAutoLaunch`.
- Do not add serve enablement, `--no-serve`, or any health check — that is
  ASR-S02. `install-cli` in this slice still does not touch the daemon.
- Do not edit any part of `AllnighterCLI.swift` outside `runInstallCLI`.

## 6. Steps

1. **`Request` gains an injectable canonical installer.** Add a
   `canonicalInstall` closure defaulting to `CanonicalCLIInstall.install`, plus
   the injected `homeDirectory`/`fileManager` already present. Tests replace the
   closure; no test writes to a real home.

2. **New `run(_:)` order.**
   - resolve the running binary as today (unchanged); `--print` still returns
     `.printed` and performs no install;
   - call the canonical installer with the resolved binary as the candidate;
   - on `INSTALL_CANDIDATE_REFUSED`, `SERVE_INSTALL_FAILED`, or
     `SERVE_ROLLBACK_FAILED`, return `.failed` with that exact code and the
     owner's message — do not remap or soften it;
   - when the report is `alreadyCanonical`, continue to the symlink step with
     the canonical path (this is the re-run case, not an error);
   - then create/repair the PATH symlink to point at the **canonical path**.
     Existing `alreadyInstalled` / `repaired` / `installed` semantics are
     preserved, but the comparison target is the canonical path, not the running
     binary.

3. **`JSON` v2.** Bump `schemaVersion` to `2` and add:
   `canonicalPath: String?`, `rollbackPath: String?`,
   `codeIdentity: String?` (the recorded cdhash, `null` when unavailable), and
   `version: String?`. `target` now reports the canonical path. Never emit the
   version string in `codeIdentity`.

4. **`SERVE_ROLLBACK_FAILED` output (§4.3).** When that code is returned, the
   human message must print an absolute-path recovery that does **not** require a
   working `alln` on PATH: a literal `cp "<canonical>.rollback" "<canonical>"`
   line, plus the one-paste faucet as the second option. Assert this in a test —
   the message must not contain the token `alln ` as the first recovery step.

5. **Exit codes in `runInstallCLI` (§5.3).** `CLI_USAGE_ERROR` → `2`;
   `INSTALL_CANDIDATE_REFUSED`, `SERVE_INSTALL_FAILED`,
   `SERVE_ROLLBACK_FAILED`, and `INSTALL_CLI_TARGET_UNWRITABLE` → `1`. Success →
   `0`. JSON mode emits exactly one object on stdout.

6. **Teaching line.** `humanLine` keeps the existing `alln menu --json` next
   step and additionally names the canonical path on an install/repair. Do not
   claim the background scheduler is installed — it is not, until ASR-S02.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'InstallCLITests|CanonicalCLIInstallTests'
```

## 8. Done when

- [ ] A successful install points the PATH symlink at the canonical path, and
      the JSON `target` and `canonicalPath` are the same path.
- [ ] Running from a binary that is already canonical reports
      `alreadyInstalled`/`alreadyCanonical` and still guarantees the symlink.
- [ ] A stale symlink pointing at an old build is repaired to the canonical path.
- [ ] `--print` performs no copy and no symlink write.
- [ ] Each canonical failure code propagates unchanged to `.failed` and exits `1`.
- [ ] The `SERVE_ROLLBACK_FAILED` message leads with a literal `cp` recovery and
      does not require `alln` on PATH (asserted).
- [ ] `codeIdentity` carries the cdhash and is `null` — never the version
      string — when the identity is unavailable.
- [ ] No test writes outside a temporary directory.
- [ ] Focused proof passes. One commit, explicit paths.

## 9. Host-state invariant

With S01a+S01b committed and nothing else, the next `install-cli` writes a
canonical binary and repoints `~/.local/bin/alln` at it. The founder's existing
LaunchAgent still points at the Application Support staged copy and keeps
running — **the staged bytes are deliberately left in place**; ASR-S02 rebinds
the agent and only then removes them. The host has a stale-but-running agent and
a correct PATH binary, which is the ordering guard §8 ASR-S01 requires.
