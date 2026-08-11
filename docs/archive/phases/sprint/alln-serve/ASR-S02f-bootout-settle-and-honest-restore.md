# ASR-S02f — settle the bootout before bootstrap, and never claim a restore that did not happen

Status: **ready**
Priority: **P0 — `install-cli` leaves the founder's bench dead ~1 run in 3, and says it restored it.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §4.3
step 7 (rollback restores the prior known-good job), §7 (`install -> enabled`),
§5.3 (one **working** recovery command), and the project law *"A failed worker is
shown failed, never faked."*

Found by dogfooding `c4df8b83` on the founder's live host during the ASR-S06
gate 7/8/10 run, immediately after all three gates passed.

## 1. The defect, measured on the live host

`bash scripts/rebuild_cli.sh` on a **healthy, loaded** host:

```text
Build of product 'alln' complete! (7.03s)
serve failed: com.allnighter.resident-coordinator converge enabled: bootstrap
  failed — prior registration restored: BootstrapError(terminationStatus: 5,
  message: "Bootstrap failed: 5: Input/output error")
```

Measured rate over 6 consecutive `alln install-cli` runs: **2 failures (~33%)**.
On one of them the host was left with:

```json
"state": "degraded",
"desiredState": "enabled",
"supervisor": { "loaded": false, "pid": null },
"recovery": { "reasonCode": "SERVE_UNKNOWN_SUPERVISOR",
              "command": "alln serve status --json" }
```

No launchd job, no daemon process, no scheduling. **The bench is down.** The
plist is present on disk, so the failure is not visible as an absence.

Three separate lies in one failure:

1. **"prior registration restored" is false.** `ServeLifecycle.swift:378-380`
   restores the prior plist bytes and calls `try? bootstrap(...)` — the `try?`
   discards the result. When that restore bootstrap fails too (it does; it is
   the same EIO), the detail string still says the registration was restored.
   The message asserts a recovery that provably did not occur.
2. **The recovery command is a no-op.** `SERVE_UNKNOWN_SUPERVISOR` prescribes
   `alln serve status --json` (`ServeStatusJSON.swift:569`) — the very command
   that produced the message. A user following it loops forever. The command
   that actually fixes this host is `alln serve repair`, verified by hand.
3. **`registryVerified: false` is returned but nothing acts on it.** The
   transaction reports its own failure honestly in one field and contradicts it
   in the adjacent prose.

## 2. Probable mechanism — verify before you fix

`launchctl bootout` is asynchronous. The `.absent` and `.present(.enabled, _)`
paths call `_tryBootout()` and then bootstrap **immediately**, with no wait for
the label to leave the domain. Bootstrapping into a domain that is still tearing
the label down is a textbook `EIO`/`5`. That matches the intermittency exactly:
it is a race, not a broken plist.

The disable path already does this correctly — it calls
`_boundedVerify(expectedLoaded: false)` after bootout. The enabled path does
not. **The fix is to make the enabled path as careful as the disable path
already is**, not to invent a new mechanism.

Confirm the mechanism before coding: if a bounded settle-wait does not drop the
failure rate, say so and stop — do not paper over it with a blind retry.

## 3. Copy-paste prompt

> In `ServeLifecycle`, wait for `launchctl bootout` to actually settle (the label
> is gone from the user GUI domain) before bootstrapping, in every path that
> boots out and then bootstraps — not only the disable path. Then make the
> failure branches tell the truth: capture the result of the restore bootstrap
> instead of discarding it with `try?`, and report "prior registration restored"
> only when the restore was verified. When it was not restored, say the service
> is down and give the recovery command that actually works. Finally, fix the
> `SERVE_UNKNOWN_SUPERVISOR` recovery command so it is not the same read-only
> status call that produced the message.

## 4. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift`
  — `_tryBootout`, `_boundedVerify`, `bootstrap`, and every `ConvergenceResult`
  built on a failure branch. Note that `_boundedVerify(expectedLoaded: false)`
  already exists and is used by the disable path.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusJSON.swift:569`
  — the `SERVE_UNKNOWN_SUPERVISOR` recovery.
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleTests.swift`
  and `ServeLifecycleEnableTests.swift` — four existing tests assert the literal
  string `"prior registration restored"` (lines 410, 428 and 330, 627). They
  encode the current lie. Update them to assert the honest wording for the case
  they actually simulate.

## 5. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift
Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusJSON.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleTests.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleEnableTests.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeStatusResolverTests.swift
```

## 6. Do not touch

`ServeDaemon`, any scheduler, `CanonicalCLIInstall`, the install-transaction
byte/rename ordering (§4.3 steps 3–5 are proven and out of scope), any script,
`ContractRegistry`, `Apps/`.

Do **not** change the plist shape. Do **not** add a `--force`. Do **not** make
the retry unbounded — §4.3 forbids unbounded retry, recursive self-launch, and
`kickstart` loops.

## 7. Steps

1. **Settle the bootout.** After a successful bootout, poll until the label is
   absent from the domain, bounded (a few seconds, small fixed ceiling). Only
   then write the plist and bootstrap. Apply this to **every** bootout →
   bootstrap path, including `.present(.enabled, _)`, not just the one you
   reproduce on.

2. **Bounded retry on a transient bootstrap failure, or none at all.** If a
   settle-wait alone does not fix it, at most a small fixed number of attempts
   with a short backoff. A ceiling that a test can prove. Never a loop.

3. **Stop discarding the restore result.** Replace `try? bootstrap(...)` in the
   failure branches with a captured result. The `ConvergenceResult` must carry
   whether the prior registration is actually loaded again.

4. **Make the detail string match the field.** `"prior registration restored"`
   only when the restore verified. Otherwise it must say plainly that serve is
   **not** running and name `alln serve repair`. `registryVerified` and the
   prose may never disagree.

5. **Fix the `SERVE_UNKNOWN_SUPERVISOR` recovery command.** It must be a command
   that can change the state it describes. `alln serve status --json` cannot.

6. **Failing-first.** Write the test that reproduces the unrestored-after-failed-
   bootstrap case and watch it fail against today's code before you fix it. State
   the observed failure in the commit message.

## 8. Works Test

```bash
scripts/swift-test.sh --filter 'ServeLifecycleTests|ServeLifecycleEnableTests|ServeStatusResolverTests'
```

Then the real proof on the live host — the unit tests do not replace it:

```bash
for i in 1 2 3 4 5 6 7 8 9 10; do
  alln install-cli --json >/dev/null 2>&1 || echo "iter $i: install FAILED"
  alln serve status --json | python3 -c "import json,sys; d=json.load(sys.stdin); print('iter', $i, d['state'], d['supervisor']['loaded'])"
done
```

**Ten consecutive `install-cli` runs must leave the supervisor loaded every
time.** The pre-fix baseline is 2 failures in 6.

## 9. Done when

- [ ] Bootout is verified settled before any bootstrap, in every path.
- [ ] 10/10 consecutive `install-cli` runs on the live host leave
      `supervisor.loaded: true`. Baseline was ~2 in 6 failing.
- [ ] A failed restore is reported as a failed restore. No branch claims
      "prior registration restored" without a verified restore.
- [ ] `registryVerified` and the human detail string never contradict.
- [ ] `SERVE_UNKNOWN_SUPERVISOR` names a command that can change the state.
- [ ] A failing-first test reproduced the unrestored case before the fix.
- [ ] No unbounded retry, no `kickstart`, no self-launch. One commit, explicit paths.

## 10. Host-state invariant

Corrective, and the highest-value fix in the packet right now. With this slice
committed, the founder's routine `rebuild_cli.sh` stops occasionally killing his
own background scheduler while reporting that it put it back. Nothing about run
semantics, scheduling, or the plist changes.
