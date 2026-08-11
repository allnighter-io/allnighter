# ASR-S06d — rollback proven with an injected bootstrap failure (gate 4, second half)

Status: **ready**
Priority: **P1 — closes gate 4; §4.3 step 7 has never run on a real host.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §8
host matrix item 4, §4.3 steps 7–8 (restore on failure, delete rollback bytes
only after health), §7 (`install -> enabled`).
Prior: [`ASR-S06c`](ASR-S06c-update-identity-host-proof.md) passed the update
half; record
[`2026-08-11-gate4-update-half-PASS.md`](../../../../qa/alln-serve/2026-08-11-gate4-update-half-PASS.md).

## 1. What is unproven

§4.3 step 7:

> On any failure after step 5, restore binary, symlink, and plist; bootstrap the
> prior known-good job when one existed; return a nonzero structured failure.

ASR-S02f's unit tests cover the logic. **No host has ever executed it.** Gate 4
requires it be proven with an injected bootstrap failure, and there is no way to
inject one today, which is why this half has never run.

Note the real-world stakes: the transient EIO bootstrap failure ASR-S02f fixed
was *the same code path*, and on one occasion it left the bench dead. This gate
is how that path gets a real receipt.

## 2. The seam — design it to be impossible to trip by accident

This slice adds, to production code, a way to make a real install fail. That is
justified by §8 but it must be built defensively.

Required properties:

1. **Opt-in by an exact value**, not by presence. `ALLNIGHTER_SERVE_TEST_INJECT`
   must equal a specific literal (e.g. `bootstrap-failure`) — an empty or
   unrecognised value injects nothing. Follow the `ALLNIGHTER_SUPPORT_DIR`
   reading pattern in `AllnighterPaths.swift`.
2. **One injection point only** — the bootstrap call inside the install/converge
   transaction. Not a general "fail any step" switch.
3. **Loud.** When active, it must say so on stderr, unmistakably, every time. A
   silent way to break installs is a liability.
4. **Not persistent.** Process-scoped environment only. It never lands in the
   plist, the desired-state file, or any durable record.
5. **Never inherited by the daemon.** The generated plist has a deterministic
   environment (§4.2); the injection variable must not reach it. A daemon that
   inherits this would fail to bootstrap forever.

If any of these cannot be met cleanly, **stop and say so** rather than shipping a
weaker seam.

## 3. Copy-paste prompt

> Add a narrowly-scoped test seam that makes the `launchctl bootstrap` step of
> the serve install transaction fail on demand, gated on the environment
> variable `ALLNIGHTER_SERVE_TEST_INJECT` being exactly `bootstrap-failure`. It
> must announce itself loudly on stderr, apply only to that one call, never be
> inherited by the spawned daemon, and never be persisted. Then add an
> `update-rollback` scenario to `scripts/works-test-serve-continuity.sh` that
> uses it to prove §4.3 step 7 on the live host: the failed update restores the
> prior binary, symlink and plist, re-bootstraps the prior known-good job, and
> the host ends healthy on the ORIGINAL build with a nonzero exit from the
> install command.

## 4. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift` — the
  bootstrap call sites, `_bootstrapWithBoundedRetry`, and
  `_restorePriorRegistration` from ASR-S02f. The injection belongs where the real
  `bootstrap` closure is constructed, not inside the retry helper.
- `Packages/AllnighterCore/Sources/AllnighterEngine/AllnighterPaths.swift` — the
  house pattern for reading an environment override.
- `Packages/AllnighterCore/Sources/AllnighterCore/AllnighterSpawnEnvironmentPolicy.swift`
  — how variables are scrubbed before spawning a child. The injection variable
  must be scrubbed the same way so no daemon inherits it.
- `scripts/works-test-serve-continuity.sh` — the `update` scenario to model the
  new one on. Diagnostics to stderr, payloads to stdout.

## 5. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift
Packages/AllnighterCore/Sources/AllnighterCore/AllnighterSpawnEnvironmentPolicy.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleEnableTests.swift
Packages/AllnighterCore/Tests/AllnighterCoreTests/AllnighterSpawnEnvironmentPolicyTests.swift
scripts/works-test-serve-continuity.sh
```

## 6. Do not touch

`CanonicalCLIInstall`, the plist shape, `KeepAlive`, `ThrottleInterval`,
`ServeDaemon`, any scheduler, `ServeStatusJSON`, any other script, `Apps/`.

Do not add a `--force` install. Do not change the retry bounds from ASR-S02f.

## 7. Steps

1. **Build the seam** to the five properties in §2. Injection reads the
   environment once, at the point the real bootstrap closure is built.

2. **Scrub it before spawning.** Add it to the spawn-environment policy's scrub
   list next to `ALLNIGHTER_TOOL_TOKEN`, with a test proving a child never
   inherits it. This is the property that keeps a test seam from becoming a
   permanent outage.

3. **Fix the weak assertion inherited from ASR-S06c** (recorded in the gate 4
   record): the `update` scenario compares cdhashes, but `rebuild_cli.sh`
   regenerates a build timestamp so the cdhash changes on *every* rebuild —
   the assertion cannot fail. Compare the **git sha** before and after as well,
   and when HEAD has not moved, report the run as a same-version reinstall
   instead of letting it read as a vA → vB proof.

4. **Add the `update-rollback` scenario.** Record the before state (binary sha,
   cdhash, daemon pid, plist bytes). Run the update with injection active.
   Assert:
   - the install command exits **nonzero**;
   - the canonical binary is byte-identical to the before state (the ORIGINAL
     build, not the candidate);
   - the PATH symlink still resolves to the canonical binary;
   - the plist is restored and the prior job is loaded again;
   - the host ends **healthy** on the ORIGINAL `runningGitSha`;
   - exactly one daemon, one agent, pid match, zero Dock processes;
   - no `<canonical>.rollback` left behind once health is confirmed (§4.3 step 8),
     **or** if one remains, say so plainly — §4.3 keeps rollback bytes on a
     *failed* rollback, and which case happened must be reported, not assumed.

5. **Leave the host healthy and the seam off.** The scenario unsets the variable
   before it exits, on every path, and the existing cleanup trap still runs.

6. **Failing-first** on the unit tests: prove the injected failure actually
   reaches the transaction before wiring the scenario.

## 8. Works Test

```bash
scripts/swift-test.sh --filter 'ServeLifecycleTests|ServeLifecycleEnableTests|AllnighterSpawnEnvironmentPolicyTests'
bash scripts/rebuild_cli.sh
bash scripts/works-test-serve-continuity.sh                                     # inspect-only, unchanged
bash scripts/works-test-serve-continuity.sh --mutate-product-agent crash-restart # unchanged
```

The PM runs the destructive new scenario on the live host:

```bash
bash scripts/works-test-serve-continuity.sh --mutate-product-agent update-rollback
```

**Do not run `update-rollback` or `update` yourself.**

## 9. Done when

- [ ] Injection is gated on an exact literal value, announces itself on stderr,
      applies to one call, is never persisted.
- [ ] A test proves a spawned child does **not** inherit the variable.
- [ ] A test proves an unset or wrong value injects nothing.
- [ ] The `update` scenario now compares git sha and names a same-version
      reinstall as such.
- [ ] `update-rollback` scenario exists and asserts every item in step 4.
- [ ] Inspect-only and `crash-restart` unchanged and still passing.
- [ ] Failing-first observed; `rebuild_cli.sh` and the focused tests pass.
- [ ] One commit.

## 10. Host-state invariant

The seam is inert unless the exact value is set. `update-rollback` deliberately
breaks an install and must leave the host healthy on the original build — that is
the whole point of the gate, and the scenario fails if it does not.

## 11. Out of scope

`SERVE_BUSY` (exit 75, update refused while obligations are active) is a
different §8 assertion and is not this slice.
