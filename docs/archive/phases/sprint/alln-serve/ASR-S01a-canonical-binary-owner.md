# ASR-S01a — canonical binary owner

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §2.1
(one canonical binary, `~/.local/bin` default), §4.1 (layout), §4.3 steps 1–5 +
7–8 (transaction, rollback), §4.6 (identity, not version string).

ASR-S01 is cut into three ordered sub-slices. **This is 1 of 3** and it is pure
addition: a new owner type plus the PATH-default change. It does not rewire
`InstallCLI.run`, does not touch launchd, and does not touch any script.

## 1. Goal

Introduce `CanonicalCLIInstall` — the single owner that places CLI bytes at
`~/.local/share/allnighter/bin/alln` atomically, preserves the prior bytes as
rollback, and records the candidate's **code identity** (not just its version) —
and make `~/.local/bin` the unconditional default PATH directory.

## 2. Copy-paste prompt

> Add `CanonicalCLIInstall` to `Packages/AllnighterCore/Sources/AllnighterCore/`
> exactly as the Steps below specify, change `InstallCLI.defaultInstallDirectory`
> per Step 5, and add focused tests. Do not modify `InstallCLI.run`, any script,
> `ServeLifecycle`, `ServeStableBinary`, or anything under `Apps/`. Every
> filesystem seam must be injectable so tests never touch the real home
> directory.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterCore/InstallCLI.swift` — the
  injectable-seam style (`Request` with `homeDirectory`/`fileManager`), the
  `Outcome` shape, and stable error codes.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeStableBinary.swift` —
  the existing staging owner this eventually replaces. Read it for the copy /
  permissions / failure vocabulary. **Do not edit or delete it** — its callers
  live in ASR-S02 and ASR-S04.
- `Packages/AllnighterCore/Tests/AllnighterCoreTests/InstallCLITests.swift` —
  test style and how the home directory is faked.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterCore/CanonicalCLIInstall.swift   (new)
Packages/AllnighterCore/Sources/AllnighterCore/InstallCLI.swift            (Step 5 only)
Packages/AllnighterCore/Tests/AllnighterCoreTests/CanonicalCLIInstallTests.swift (new)
Packages/AllnighterCore/Tests/AllnighterCoreTests/InstallCLITests.swift    (Step 5 test only)
```

## 5. Do not read / do not touch

- No `Apps/`, no `scripts/`, no `AllnighterEngine` source, no launchd, no
  `ServeLifecycle`, no `ServeAutoLaunch`, no CLI routing.
- Do not delete `ServeStableBinary` or its tests.
- Do not read `AGENTS.md` or the phase board beyond the sections linked above.

## 6. Steps

1. **Paths.** `CanonicalCLIInstall.canonicalDirectory(homeDirectory:)` =
   `<home>/.local/share/allnighter/bin`; `canonicalBinaryURL(homeDirectory:)` =
   that directory `/alln`; `rollbackBinaryURL` = `<canonical>.rollback`; and
   `identityRecordURL(homeDirectory:)` =
   `<home>/Library/Application Support/Allnighter/installed-binary.json`.
   All derived from an injected `homeDirectory`; never read the real home.

2. **Candidate refusal (§4.3 step 1).** `refusalReason(forCandidate:)` returns a
   non-nil stable reason when the candidate path is inside an `.app` bundle
   (any path component ending `.app`) or under `~/Documents`, `~/Desktop`, or
   `~/Downloads`. Error code `INSTALL_CANDIDATE_REFUSED`. A candidate under
   `~/Library/Developer/…` (what `rebuild_cli.sh` produces) is accepted.

3. **Identity.** `CodeIdentity` = `{ cdhash: String?, version: String? }`.
   Compute `cdhash` by running `codesign -dvvv <path>` and reading the `CDHash=`
   line; the process runner is an injected closure so tests never shell out. A
   `nil` cdhash is recorded as `nil` — **never** substituted with the version
   string and never inferred. `identityRecordURL` stores schema version,
   canonical path, the `CodeIdentity`, and an updated timestamp, written
   atomically.

4. **`install(candidate:homeDirectory:…) -> Result<Report, Failure>`,
   performing §4.3 steps 3, 5, 7, 8 and nothing else:**
   - refuse per Step 2; refuse a candidate that is already the canonical path
     (`sameFile` by resolved path) with a distinct `alreadyCanonical` report —
     no copy, no rollback churn;
   - create the canonical directory if absent;
   - copy the candidate to a temp path **in the canonical directory** (same
     filesystem), preserving the executable bit;
   - if a canonical binary exists, move it to `<canonical>.rollback` first;
   - atomically `rename` the temp into the canonical path;
   - on any failure after the rename, restore the rollback bytes and return
     `.failure` with `SERVE_INSTALL_FAILED`; if the *restore itself* fails,
     return `SERVE_ROLLBACK_FAILED` and **leave `<canonical>.rollback` on disk**;
   - expose a `beforeBytesChange: () -> Result<Void, Failure>` injected hook,
     called after the rollback is preserved and immediately **before** the
     rename. It defaults to success. ASR-S02 plugs the launchd bootout in here
     (§4.3 step 4); this slice only provides the seam and proves it is called at
     the right moment.
   - write the identity record only after the rename succeeds;
   - **do not** delete the rollback bytes — §4.3 step 8 deletes them only after
     active health matches, which is ASR-S02's health check. Report the rollback
     path so the caller can retire it later.

5. **PATH default.** `InstallCLI.defaultInstallDirectory` returns
   `<home>/.local/bin` unconditionally. Delete the `/usr/local/bin`
   writability probe. `/usr/local/bin` stays reachable only through an explicit
   `--path`. Update the doc comment and keep the existing `unwritableMessage`
   guidance for an explicitly chosen `/usr/local/bin`.

6. **Failure vocabulary.** Stable codes only:
   `INSTALL_CANDIDATE_REFUSED`, `SERVE_INSTALL_FAILED`, `SERVE_ROLLBACK_FAILED`.
   Each failure carries a human message naming an absolute path.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'CanonicalCLIInstallTests|InstallCLITests'
```

## 8. Done when

- [ ] Fresh install into an empty fake home creates the canonical binary,
      preserves no rollback, and writes the identity record.
- [ ] Re-install over an existing canonical binary preserves the prior bytes at
      `<canonical>.rollback` and leaves them there.
- [ ] `beforeBytesChange` is proven to be called **after** the rollback exists
      and **before** the canonical bytes change; returning `.failure` from it
      aborts with the canonical bytes byte-for-byte unchanged.
- [ ] A failed rename restores the prior bytes; a failed restore returns
      `SERVE_ROLLBACK_FAILED` and leaves `<canonical>.rollback` present.
- [ ] An `.app`-bundle candidate and a `~/Documents` candidate are both refused
      with `INSTALL_CANDIDATE_REFUSED`, and a `~/Library/Developer` candidate is
      accepted.
- [ ] Candidate already at the canonical path reports `alreadyCanonical` with no
      copy performed.
- [ ] Two candidates with the **same version string but different cdhash**
      produce different recorded identities; a `nil` cdhash stays `nil`.
- [ ] `defaultInstallDirectory` returns `~/.local/bin` even when
      `/usr/local/bin` is writable.
- [ ] Focused proof above passes. One commit, explicit paths.

## 9. Host-state invariant

With only this slice committed, the founder's host is unchanged: new type plus
tests, and a default that only takes effect the next time `install-cli` runs
without `--path`. Nothing copies bytes, touches launchd, or runs at build time.
