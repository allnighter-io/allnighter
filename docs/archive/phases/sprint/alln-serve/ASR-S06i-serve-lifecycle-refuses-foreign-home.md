# ASR-S06i — serve lifecycle must refuse a foreign `HOME`, not silently act on the real one

Status: **ready**
Priority: **P0 — silently disables the user's background scheduler, persistently.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §2.1
(one host, one supervisor), §2.2 (disable persists), §4.1 (canonical layout), and
the project law *"A command that returns without queued work must leave none
behind … refuse loudly."*
Evidence:
[`2026-08-11-home-override-kills-real-serve.md`](../../../../qa/alln-serve/2026-08-11-home-override-kills-real-serve.md).

## 1. The defect

`HOME=<temp> alln serve disable` boots out the **real** user's LaunchAgent,
deletes the **real** plist, and writes `disabled` to the **real** durable
desired-state file. The temp home gets nothing.

`InstallCLI` honors `HOME` (ASR-S01d). `ServeLifecycle` does not — it defaults to
`FileManager.default.homeDirectoryForCurrentUser`
(`ServeLifecycle.swift:175`, `:182`, `:712`), which resolves via `getpwuid` and
ignores the environment. One command therefore splits: install layout follows
`HOME`, serve lifecycle acts on the real user.

Because a disable persists by design (§2.2, proven by gate 8), the damage does
not self-heal: scheduling stays off across login and `install-cli` will not undo
it. This session tripped it twice by accident while building a gate.

## 2. The decision this slice must make

Two candidate fixes. **The recommended one is (b); justify whichever you choose
in the commit message.**

**(a) Honor `HOME` throughout.** Tempting and wrong on its own: the label
`com.allnighter.resident-coordinator` is scoped to the **user**, not to `HOME`.
A HOME-honoring lifecycle would write a plist under the temp home and still
bootstrap into `gui/$(id -u)` — the same single per-user slot. Two "different"
installs would fight over one label. Honoring `HOME` for paths without also
scoping the label just moves the collision.

**(b) Refuse loudly.** When the effective `HOME` differs from the real user's
home directory, any serve **lifecycle** operation — `enable`, `disable`,
`repair`, `restart`, and the serve half of `install-cli` — refuses with a
structured error naming both paths, and changes nothing. Read-only
`serve status` stays allowed. This matches the queue-honesty law: refuse loudly
rather than act on state the caller did not mean.

Under (b), a cold-install test in a throwaway home does exactly what ASR-S06h
wants — installs the layout, declines the serve half, touches nothing real.

## 3. Copy-paste prompt

> `ServeLifecycle` resolves its plist path, desired-state path and launchd
> operations from the real user's home even when `HOME` is overridden, so running
> any serve lifecycle command with a different `HOME` silently disables the real
> user's background scheduler. Make every serve lifecycle operation detect that
> mismatch and refuse with a structured, named error that changes nothing on
> disk and in launchd. `serve status` must stay readable. Add the check in one
> place that all lifecycle entry points pass through.

## 4. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift` — the
  three `homeDirectoryForCurrentUser` defaults and the converge entry points.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeDesiredState.swift` —
  `storeURL(homeDirectory:)`; already parameterized, so the caller decides.
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift`
  — how a stable error code is declared, for the new refusal code.
- `docs/phases/Alln_Serve_Hotfixes.md` §5.3 exit-code table — pick the right
  exit code and say why. This is a refusal to act on a mismatched request, not a
  health failure.

## 5. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift
Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleEnableTests.swift
Packages/AllnighterCore/Tests/AllnighterCoreTests/ContractRegistryTests.swift
```

If the refusal genuinely belongs in the CLI layer rather than the engine, stop
and say which file you need.

## 6. Do not touch

`InstallCLI`'s existing `HOME` handling — it is correct. The plist shape,
`KeepAlive`, `ThrottleInterval`, `ServeDaemon`, any scheduler, any script.

Do **not** make the refusal overridable by a flag or env var in this slice. A
bypass is a new product decision.

## 7. Steps

1. **One chokepoint.** Every lifecycle path — `enable`, `disable`, `repair`,
   `restart`, converge, and the serve half of install — passes through a single
   check. Scattered checks are how the install/lifecycle split happened.

2. **Compare honestly.** The real home is
   `FileManager.default.homeDirectoryForCurrentUser`; the effective one is what
   the caller supplied / `HOME`. Compare resolved, symlink-canonical paths so
   `/tmp` vs `/private/tmp` does not produce a false mismatch.

3. **Refuse before any mutation.** No bootout, no plist write or delete, no
   desired-state write. Prove byte-for-byte non-mutation in a test — the same
   discipline §5.3 requires of `SERVE_BUSY`.

4. **Name it.** A stable error code with both paths in the message and a
   one-line explanation of why the operation is per-user. A caller that sees this
   must understand immediately that its `HOME` is the problem.

5. **`serve status` stays readable** under a foreign `HOME`. Observation is not
   mutation, and the INFORM-never-BLOCK law applies.

6. **Failing-first.** Write the test that shows a foreign-`HOME` `disable`
   currently boots out the real label, watch it fail, then fix. Record the
   observed failure in the commit message.

## 8. Works Test

```bash
scripts/swift-test.sh --filter 'ServeLifecycleEnableTests|ServeLifecycleTests|ContractRegistryTests'
bash scripts/rebuild_cli.sh
```

Then the live proof, which the PM runs:

```bash
launchctl print gui/$(id -u)/com.allnighter.resident-coordinator >/dev/null && echo LOADED
TMPH=$(mktemp -d); HOME="$TMPH" alln serve disable; echo "exit=$?"
launchctl print gui/$(id -u)/com.allnighter.resident-coordinator >/dev/null && echo "STILL LOADED"
rm -rf "$TMPH"
```

It must refuse, exit non-zero, and leave the agent loaded.

## 9. Done when

- [ ] Foreign-`HOME` lifecycle operations refuse with a stable named code and
      change nothing on disk or in launchd, proven byte-for-byte.
- [ ] `serve status` still works under a foreign `HOME`.
- [ ] Path comparison is symlink-canonical.
- [ ] The choice between (a) and (b) is justified in the commit message.
- [ ] Failing-first observed and recorded.
- [ ] Focused tests and `rebuild_cli.sh` pass. One commit.

## 10. Host-state invariant

Corrective. An agent, test harness, or CI shim that runs `alln` with its own
`HOME` stops silently switching off the founder's background scheduler.

## 11. What this does not claim

It does **not** close §10.1 R1. This defect produces R1's observable state from
an innocuous action, which makes it a candidate explanation for the two
unexplained unloads — but neither incident recorded the environment of what ran
before it, so the link is unconfirmable. Say so in the commit message.
