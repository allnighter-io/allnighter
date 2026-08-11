# ASR-S02c — convergent supervisor transaction

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §2.1
(the agent points at the canonical binary), §4.3 steps 4/6/7 (bootout before the
bytes change; bounded verify; restore on failure), §5.1 (`enable`/`disable`/
`restart`/`repair` contracts), §7 (`plist -> supervision`, `user disable ->
repair`).

**3 of 5** in the ASR-S02 cut. S02a landed the desired-state store; S02b landed
the plist shape. This slice makes the four lifecycle verbs one transaction and
repoints the agent at the canonical binary. The **live-host migration** (booting
the founder's existing staged-path agent and removing the staged bytes) is
**S02d** — do not attempt it here.

## 1. Goal

`enable`, `disable`, `restart`, and `repair` become one convergent owner that
reads desired state, refuses to act on a state it cannot read, points
`ProgramArguments` at the canonical binary, and restores the prior working
registration when convergence fails.

## 2. Copy-paste prompt

> Rework `ServeLifecycle`'s enable/disable/repair paths into a single convergence
> routine per the Steps, add `restart`, and repoint `ProgramArguments` at the
> canonical binary. `bootout` and every launchctl seam stays injected — no test
> may run a real `launchctl`. Do not add the staged-path migration, the
> `SMAppService` authorization read, or install-time enablement; each is a later
> slice.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift` — the
  current `enable`/`disable`/`refreshAfterInstall` bodies and every injected
  seam (`bootout`, `plistExists`, `removePlist`, `stage`).
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeDesiredState.swift` —
  `read`, `write`, `Reading`, and `effectiveState`.
- `Packages/AllnighterCore/Sources/AllnighterCore/CanonicalCLIInstall.swift` —
  `canonicalBinaryURL` and the `beforeBytesChange` hook this slice will later
  supply.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleTests.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleEnableTests.swift
```

## 5. Do not read / do not touch

- **Do not migrate the live host.** Booting out an agent that points at the
  Application Support staged path, and deleting those staged bytes, is S02d.
  Nothing in this slice may remove staged bytes.
- Do not touch `ServeStableBinary`, `ServeAutoLaunch`, `ServeDaemon`,
  `CanonicalCLIInstall`, `InstallCLI`, any CLI file, any script, or `Apps/`.
- Do not add `SMAppService`/`statusForLegacyPlist`, install-time default
  enablement, `--no-serve`, or scheduler receipts.
- No test may invoke a real `launchctl`, write to the real
  `~/Library/LaunchAgents`, or touch the real desired-state file.

## 6. Steps

1. **`ProgramArguments` points at the canonical binary.** Replace the staged
   path with `CanonicalCLIInstall.canonicalBinaryURL(homeDirectory:)`. The
   staged-binary staging call (`stage`) is no longer part of enable — remove it
   from the convergence path. Leave `ServeStableBinary` itself alone.

2. **Refuse a plist that names a missing executable.** Before writing the plist,
   verify the canonical binary exists and is executable. If it does not, return
   a failure with `SERVE_INSTALL_FAILED` naming the absolute path and the
   command that creates it (`alln install-cli`). **Do not create, stage, or copy
   the binary to make yourself true.** Writing a plist that points at a
   nonexistent executable hands launchd exactly the missing-executable thrash
   §4.2 warns about.

3. **One convergence routine.** `converge(desired:)` reads
   `ServeDesiredState` and acts:
   - `.present(.disabled)` or `.absent` treated per §4.1 migration (absent →
     enabled) — but the *absence* is reported in the result so the caller can
     log a migration instead of implying a file existed;
   - `.unreadable` → **do not converge**. Return a `degraded` result carrying the
     reason. Do not bootstrap, do not boot out, and do not rewrite the state
     file. Converging on a corrupt file would re-enable a service the user
     disabled, which is the §7 `user disable -> repair` ban;
   - enabled → ensure plist + registration + a bounded verify;
   - disabled → boot out **before** removing the plist, then verify stopped.

4. **The four verbs become thin callers of `converge`:**
   - `enable` — write desired `enabled`, then converge;
   - `disable` — write desired `disabled`, then converge (bootout precedes plist
     removal so KeepAlive cannot resurrect it);
   - `restart` — one bootout + bootstrap + verify; **no** desired-state write;
   - `repair` — converge to the recorded desired state. §5.1 is explicit that
     repair **restores** an enabled agent and never merely deletes. Today's
     delete-only behavior is the bug; a test must pin that repair reinstalls.

5. **Restore on failure (§4.3 step 7).** Capture the prior plist bytes before
   writing. If the write or bootstrap fails, restore those bytes and re-bootstrap
   the prior job when one existed, then return a nonzero structured failure. A
   convergence that fails must not leave the host with neither the old nor the
   new registration.

6. **Bounded verify.** Verification is a single bounded wait (≤10s, injected
   clock/sleep) for the supervisor to report the job loaded. **This is not the
   §5.2 active health handshake** — that requires the loopback daemon response
   and lands in ASR-S03. Name the limit honestly in the result: this slice can
   prove *registered*, not *healthy*. Do not report `healthy`.

7. **No unbounded retry**, no `kickstart` loop, no recursive self-launch, and no
   success-with-a-warning. The verb's result covers the whole requested
   transaction.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'ServeLifecycleTests|ServeLifecycleEnableTests|ServeDesiredStateTests'
```

## 8. Done when

- [ ] `ProgramArguments` resolves to the canonical binary path; a test pins it
      and would fail if it reverted to the staged path.
- [ ] Enable with a **missing** canonical binary refuses with
      `SERVE_INSTALL_FAILED`, writes no plist, and creates no binary.
- [ ] `.unreadable` desired state performs **no** bootout and **no** bootstrap
      and returns `degraded` with the reason.
- [ ] Explicit `disabled` survives a converge — no bootstrap occurs.
- [ ] `disable` boots out **before** the plist is removed (ordering asserted).
- [ ] `repair` on an enabled desired state **reinstalls** the agent; a test
      fails if it only deletes.
- [ ] A failed bootstrap restores the prior plist bytes and re-bootstraps the
      prior job; the host is left with the old registration, not none.
- [ ] The verify step reports `registered`, never `healthy`, and is bounded by
      an injected clock.
- [ ] No staged bytes are removed anywhere in this slice.
- [ ] No test runs a real `launchctl` or writes to the real LaunchAgents dir.
- [ ] Focused proof passes. One commit, explicit paths.

## 9. Host-state invariant

With this slice committed and nothing run, the founder's host is unchanged — the
loaded staged-path agent keeps running and no plist is rewritten. The first time
`serve enable`/`repair` runs, it will refuse unless a canonical binary exists
(Step 2), which is the correct failure: it names `alln install-cli` rather than
pointing launchd at a path with no executable. S02d then performs the live
rebind and retires the staged bytes.
