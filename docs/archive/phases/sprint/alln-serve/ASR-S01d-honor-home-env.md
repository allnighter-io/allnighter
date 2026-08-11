# ASR-S01d — honor `HOME` so the canonical layout is provable

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §4.1
(canonical layout), §8 ASR-S06 gate 1 (cold install in a clean user home).

Closes a measurement gap found reviewing ASR-S01c (`fa8dc145`). The install
owner derives the canonical directory from `FileManager.homeDirectoryForCurrentUser`,
which resolves the **passwd** home and ignores an overridden `HOME`. So
`scripts/test-get-alln.sh` — which sandboxes with `HOME=/tmp/...` — cannot
assert that bytes land at `<home>/.local/share/allnighter/bin`; it had to fall
back to "realpath of the symlink is executable". A proof that cannot see the
layout cannot defend it, and ASR-S06 gate 1 needs the same capability.

## 1. Goal

`alln install-cli` resolves the user home from the `HOME` environment variable
when it is set to an absolute existing directory, falling back to
`homeDirectoryForCurrentUser` otherwise — and the installer proof asserts the
real canonical path again.

## 2. Copy-paste prompt

> Make `runInstallCLI` resolve the home directory from `HOME` when it is a set,
> absolute, existing directory, and pass it into `InstallCLI.Request`. Add the
> focused tests. Then restore the canonical-path assertion in
> `scripts/test-get-alln.sh`. Do not change `CanonicalCLIInstall`'s own logic —
> it already takes an injected `homeDirectory`; this slice only decides what the
> CLI hands it.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterCore/InstallCLI.swift` — `Request`
  and how `homeDirectory` defaults today.
- `Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift` lines
  2600–2665 only — `runInstallCLI` as ASR-S01b left it.
- `scripts/test-get-alln.sh` — the scratch-`HOME` harness and the assertion that
  was weakened (`BUG-3: could not resolve canonical binary from symlink`).

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterCore/InstallCLI.swift
Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift   (runInstallCLI only)
Packages/AllnighterCore/Tests/AllnighterCoreTests/InstallCLITests.swift
scripts/test-get-alln.sh
```

## 5. Do not read / do not touch

- Do not change `CanonicalCLIInstall.swift` — it is already injectable.
- Do not touch launchd, `ServeLifecycle`, `ServeStableBinary`, `Apps/`,
  `get-alln.sh`, or `rebuild_cli.sh`.
- Do not weaken or delete the existing safety guards in `test-get-alln.sh`
  (`assert_scratch_home`, the canary mtime checks, the real-`~/.local/bin`
  check). They stay exactly as they are.

## 6. Steps

1. **Home resolution helper** in `InstallCLI`:
   `resolvedHomeDirectory(environment:fileManager:) -> URL`. Returns the `HOME`
   value when it is non-empty, absolute, and an existing directory; otherwise
   `fileManager.homeDirectoryForCurrentUser`. A relative, empty, or
   nonexistent `HOME` falls back — it never fabricates a path and never creates
   the directory to make itself true.

2. **Wire it** in `runInstallCLI`: pass
   `homeDirectory: InstallCLI.resolvedHomeDirectory(environment: ProcessInfo.processInfo.environment)`
   into the `Request`. Change nothing else in that function.

3. **Tests** (`InstallCLITests`): `HOME` set to an existing temp dir wins;
   unset, empty, relative, and nonexistent `HOME` each fall back to
   `homeDirectoryForCurrentUser`; and an install with a scratch `HOME` places the
   canonical binary under `<scratchHome>/.local/share/allnighter/bin/alln`.

4. **Restore the proof** in `scripts/test-get-alln.sh`: assert that the
   installed symlink resolves to exactly
   `$HOME_x/.local/share/allnighter/bin/alln` for the scratch home used in that
   case — a literal path comparison, not just "resolves to something
   executable". Keep every existing assertion and guard.

5. **Negative proof.** Add one case that would fail if the product regressed to
   the passwd home: assert the canonical binary exists under the scratch home
   **and** that no new file appeared at
   `$REAL_HOME/.local/share/allnighter/bin/alln` during the run. Snapshot the
   real path's existence before the run and compare after — the assertion must
   be able to fail.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'InstallCLITests'
bash scripts/test-get-alln.sh
```

## 8. Done when

- [ ] `HOME` pointing at an existing absolute directory decides the canonical
      layout; empty/relative/nonexistent `HOME` falls back without fabricating.
- [ ] A scratch-`HOME` install is asserted at the literal canonical path.
- [ ] The new negative proof fails if bytes land in the real home (verified by
      temporarily inverting it during development, then restoring it).
- [ ] Every pre-existing guard in `test-get-alln.sh` is still present.
- [ ] Both proofs pass. One commit, explicit paths.

## 9. Host-state invariant

Unchanged from S01c: PATH and the canonical binary are owned by `install-cli`;
the live LaunchAgent still runs its frozen staged bytes until ASR-S02. This
slice only changes which home directory the installer reads, which for the
founder's real shell is the same directory it already used.
