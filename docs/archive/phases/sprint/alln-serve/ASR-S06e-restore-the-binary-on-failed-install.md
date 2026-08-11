# ASR-S06e — a failed install must restore the binary, not just the plist

Status: **ready**
Priority: **P0 — §4.3 step 7 is half-implemented and gate 4 fails because of it.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §4.3
steps 7–8, §7 (`install -> enabled`).
Failing gate record:
[`2026-08-11-gate4-rollback-half-FAIL.md`](../../../../qa/alln-serve/2026-08-11-gate4-rollback-half-FAIL.md).

## 1. The defect, measured on the live host

The first real execution of §4.3 step 7, via ASR-S06d's injected bootstrap
failure. §4.3 requires:

> On any failure after step 5, restore **binary**, symlink, and plist; bootstrap
> the prior known-good job when one existed; return a nonzero structured failure.

Measured, with a pre-run copy of the binary taken outside the harness:

```text
pre-run copy (the original)              sha256 41b2693afd7b4055…
canonical binary after failed install    sha256 fb7522e4be221984…   <- candidate
alln.rollback                            sha256 41b2693afd7b4055…   <- original, unused
```

Plist restored ✔. Prior job re-bootstrapped ✔. Nonzero exit ✔.
**Binary not restored ✘.** The rollback file was written correctly and then never
used.

It looked green from the outside because the candidate came from the same commit,
so `runningGitSha` still matched. Had HEAD moved, the host would be running a
build the failed install was supposed to undo.

## 2. Copy-paste prompt

> When the serve install/converge transaction fails after the canonical bytes
> have been replaced, restore the binary from `<canonical>.rollback` as well as
> the plist, then re-bootstrap the prior known-good job. Decide and state which
> owner does it — `CanonicalCLIInstall`, which performs the rename and writes the
> rollback file, or `ServeLifecycle`, which discovers the bootstrap failure — and
> make the ordering explicit so the restored binary is in place before the prior
> job is bootstrapped. Report honestly when the binary restore itself fails, and
> never delete rollback bytes in that case.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterCore/CanonicalCLIInstall.swift` —
  who writes `<canonical>.rollback`, when the rename happens, and the
  `beforeBytesChange` hook §8 ASR-S02 describes. This is probably the right
  owner; confirm before choosing.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift` —
  `_restorePriorRegistration` and the converge failure branches from ASR-S02f.
  Note what it restores today: plist bytes, then bootstrap. Not the binary.
- `docs/phases/Alln_Serve_Hotfixes.md` §4.3 steps 3–8, and the
  `SERVE_ROLLBACK_FAILED` requirement: rollback bytes stay at
  `<canonical>.rollback` and are never deleted, and the recovery printed must not
  require a working `alln` on PATH.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterCore/CanonicalCLIInstall.swift
Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift
Packages/AllnighterCore/Tests/AllnighterCoreTests/CanonicalCLIInstallTests.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleEnableTests.swift
scripts/works-test-serve-continuity.sh
```

Touch the **fewest** of these that does the job. If the honest owner is
`CanonicalCLIInstall` alone, do not also edit `ServeLifecycle`.

## 5. Do not touch

The plist shape, `KeepAlive`, `ThrottleInterval`, `ServeDaemon`, any scheduler,
`ServeStatusJSON`, the injection seam's gating, any other script.

## 6. Steps

1. **Name the owner in the commit message.** One owner restores binary, symlink
   and plist together. Two owners each restoring part of the state is how this
   defect happened.

2. **Ordering matters.** The restored binary must be in place *before* the prior
   job is bootstrapped — launchd would otherwise start the candidate bytes under
   the restored registration, which is the mixed state §2.1 exists to prevent.

3. **Symlink too.** §4.3 names binary, symlink and plist. Verify the PATH symlink
   after restore; it happens to be correct today because the canonical path did
   not move, but the assertion belongs in the test.

4. **A failed binary restore is `SERVE_ROLLBACK_FAILED`.** Do not delete
   `<canonical>.rollback`, and print an absolute-path recovery that does not
   require a working `alln` on PATH — a literal `cp` of the rollback bytes back
   into place. §4.3 is explicit that a user with a broken PATH binary cannot be
   told to run an `alln` subcommand.

5. **Step 8 still holds.** Rollback bytes are deleted only after active health
   matches the candidate build. A successful install still cleans up.

6. **Fix the harness summary line.** The script printed
   `PASS — update-rollback host proof passed` alongside `2 FAILURE(S)` in the
   same run. A summary that claims a pass with failures outstanding is the exact
   contradiction this packet removes. It must reflect `FAILURES`.

7. **Failing-first.** With the injected bootstrap failure, assert the canonical
   binary equals the prior bytes and watch it fail before fixing. Record the
   observed failure in the commit message.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'CanonicalCLIInstallTests|ServeLifecycleEnableTests|ServeLifecycleTests'
bash scripts/rebuild_cli.sh
```

The PM runs the gate on the live host:

```bash
shasum -a 256 ~/.local/share/allnighter/bin/alln
bash scripts/works-test-serve-continuity.sh --mutate-product-agent update-rollback
shasum -a 256 ~/.local/share/allnighter/bin/alln     # must equal the pre-run value
```

**Do not run `update-rollback` or `update` yourself.**

## 8. Done when

- [ ] A failed install restores the canonical binary to the prior bytes, proven
      by sha256 equality, not by version string.
- [ ] Binary is restored before the prior job is bootstrapped.
- [ ] Symlink verified after restore.
- [ ] A failed binary restore reports `SERVE_ROLLBACK_FAILED`, keeps
      `<canonical>.rollback`, and prints an `alln`-free absolute-path recovery.
- [ ] A successful install still deletes rollback bytes only after health.
- [ ] Harness summary line reflects `FAILURES`.
- [ ] Failing-first observed; focused tests and `rebuild_cli.sh` pass.
- [ ] One commit.

## 9. Host-state invariant

Corrective. A failed CLI update stops leaving the founder's host on bytes the
install already decided to abandon.

## 10. Note on the current host

`~/.local/share/allnighter/bin/alln.rollback` (48 MB) is on the host right now,
left by the failing gate as evidence. Once this slice lands and the gate passes,
the successful-install path should clean it up per step 8; if it does not, say so
rather than deleting it by hand.
