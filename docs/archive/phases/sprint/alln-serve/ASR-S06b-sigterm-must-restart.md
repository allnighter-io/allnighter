# ASR-S06b — SIGTERM must be signal death, not a clean exit

Status: **ready**
Priority: **P0 — any TERM permanently stops background scheduling. Gate 3 fails today.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §4.2
restart contract, §7 (`exit -> restart`), §8 host matrix item 3.
Failing gate record:
[`docs/qa/alln-serve/2026-08-11-gate3-crash-restart-FAIL.md`](../../qa/alln-serve/2026-08-11-gate3-crash-restart-FAIL.md).

## 1. The defect, measured on the live host

`kill -TERM <daemon pid>` on a healthy host. The process dies immediately and
**launchd never restarts it** — 45 s, job still loaded, zero `alln serve`
processes.

```text
launchctl print gui/501/com.allnighter.resident-coordinator
  state = not running
  runs = 1
  last exit code = 0
  semaphores = { successful exit => 0 }
```

The daemon exits **0** on SIGTERM. With `KeepAlive = { SuccessfulExit = false }`,
exit 0 means deliberate stand-down, so launchd correctly declines to respawn.

**launchd and the plist are behaving correctly. The daemon's signal handling is
the bug.** Do not change the plist. Do not change `KeepAlive`. §4.2 chose that
dictionary form deliberately to avoid a respawn loop, and ASR-S00 proved it on
the real primitive.

## 2. What §4.2 actually specifies

> `SIGTERM` settles runtime receipts and then **re-raises `SIGTERM` under the
> default handler**, so launchd observes signal death and restarts.

The settle happens. The re-raise does not. That is the whole slice.

| Daemon exit | launchd must | Reached by |
| --- | --- | --- |
| exit `0` | **not** restart | admission refusal, unrecoverable configuration |
| signal death | restart after `ThrottleInterval` | TERM, KILL, crash |

## 3. Copy-paste prompt

> The `alln serve` daemon exits 0 when it receives SIGTERM, so launchd treats it
> as a deliberate stand-down and never restarts it. Per §4.2 the daemon must
> settle its runtime receipts and then **re-raise SIGTERM under the default
> handler**, so launchd observes signal death and restarts the job. Find the
> SIGTERM handling in the serve daemon, make the re-raise happen, and keep the
> receipt settling that already works. Do not touch the plist, `KeepAlive`, or
> any launchd registration code. Then fix the gate script so it does not treat
> the transient `starting` state as a failure.

## 4. Read only

- The serve daemon's signal handling — start from `ServeDaemon` and the
  `alln serve` entry point in `AllnighterCLI.swift`. Find where SIGTERM is
  installed and what it does on the way out. Note that §4.2 also names two
  *legitimate* exit-0 paths (admission refusal, unrecoverable configuration);
  those must keep exiting 0.
- `docs/phases/Alln_Serve_Hotfixes.md` §4.2, including the restart-contract
  table and the stand-down visibility requirement.
- `scripts/works-test-serve-continuity.sh` — the `host_is_healthy` /cleanup
  logic that currently calls `starting` unhealthy.

## 5. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift
Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeDaemonSignalTests.swift   (new if absent)
scripts/works-test-serve-continuity.sh
```

If the signal handling lives somewhere else entirely, **stop and say so** rather
than widening the allowlist yourself — name the file you actually need.

## 6. Do not touch

The generated plist or anything that writes it, `KeepAlive`, `ThrottleInterval`,
`ServeLifecycle`, `ServeStatusJSON`, any scheduler, any other script.

## 7. Steps

1. **Find the current handler and say what it does.** Report in the commit
   message whether SIGTERM is trapped and where the exit-0 comes from. A fix
   whose author cannot describe the old behaviour is a guess.

2. **Settle, then re-raise.** Keep the receipt settling. Then restore the
   default disposition for SIGTERM and re-raise it on self, so the process dies
   *by signal*. `exit(0)` and `exit(nonzero)` are both wrong here: nonzero would
   restart, but it would also misreport a clean shutdown as an error and would
   not match §4.2.

3. **Do not break the legitimate stand-downs.** Admission refusal and
   unrecoverable configuration still exit `0` and still must not respawn. A test
   must prove both directions, because a fix that makes *everything* restart
   recreates the slow-motion fork bomb §4.2 exists to prevent.

4. **Keep stand-down visible.** §4.2 requires a stood-down daemon to surface as
   `degraded` with `lastExitCode = 0` and a recovery command. That works today —
   do not regress it.

5. **Fix the gate script's health predicate.** `starting` is a bounded transient
   (ASR-S03f4), not a failure. The script's cleanup currently reports "still not
   healthy after repair" when it samples during that window. Wait out the
   bounded window before declaring the host unhealthy.

6. **Failing-first.** State in the commit message what you observed before the
   fix.

## 8. Works Test

```bash
scripts/swift-test.sh --filter 'ServeDaemonSignalTests|ServeDaemonAdmissionTests'
```

Then the real proof, which the PM runs on the live host — this is the gate:

```bash
bash scripts/works-test-serve-continuity.sh --mutate-product-agent crash-restart
```

Gate 3 passes only when **both** the TERM and KILL halves produce a new daemon
pid with active health, and the host is healthy afterwards.

## 9. Done when

- [ ] SIGTERM settles receipts and then kills the process **by signal**, not by
      `exit(0)`.
- [ ] `launchctl print` after a TERM shows signal death and a respawn, not
      `last exit code = 0` with `state = not running`.
- [ ] Admission refusal and unrecoverable configuration still exit `0` and still
      do not respawn — proven by test, both directions.
- [ ] Stand-down remains visible in `serve status` as `degraded` +
      `lastExitCode: 0` + a recovery command.
- [ ] `works-test-serve-continuity.sh --mutate-product-agent crash-restart`
      passes both halves on the live host.
- [ ] The script no longer calls the bounded `starting` window unhealthy.
- [ ] One commit, explicit paths.

## 10. Host-state invariant

Corrective, and high value. With this slice committed, a stray `kill` or a
system-initiated termination stops being a silent, permanent end to all
background scheduling.

## 11. What this does NOT close

**§10.1 R1 stays open.** This defect has the same fingerprint as the two
unexplained launchd events (job loaded, no process) and is a plausible
explanation for them — but neither incident recorded an exit code, so the link
cannot be confirmed. Do not write a commit message or archive note claiming R1
is solved. Fixing a bug that *could* have caused them is not the same as showing
it *did*.
