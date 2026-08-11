# ASR-S06a — the crash-restart host proof script (gate 3)

Status: **ready**
Priority: **P1 — gate 3 is one of two remaining host gates that need no new product code.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §8
ASR-S06 (`scripts/works-test-serve-continuity.sh` and host matrix item 3), §4.2
restart contract, §9 Works Test.

**Build the script the packet has mandated since 2026-08-10 and never got.**
`scripts/works-test-serve-continuity.sh` does not exist. Gates 7, 8, 9 and 10
were all run by hand because of that, and gate 3 has never been run at all.

## 1. What gate 3 claims

> TERM then KILL: launchd supplies a new pid and active health within 15 s; no
> extra daemon and no Dock process.

Plus the §4.2 restart contract this is the real-primitive proof of:

| Daemon exit | launchd behavior |
| --- | --- |
| exit `0` | **no restart** — deliberate stand-down |
| signal death or nonzero exit | restart after `ThrottleInterval` |

`ThrottleInterval` is 30 s in the live plist, so a restart may legitimately take
up to ~30 s to *begin*. The gate's 15 s budget is measured **from the moment
launchd starts the replacement**, not from the kill. Do not write a test that
fails on a correct 30 s throttle; measure both numbers and report them
separately.

## 2. Copy-paste prompt

> Write `scripts/works-test-serve-continuity.sh`, a host proof script for
> `alln serve` continuity. Default mode is **inspect-only** and must not touch
> the real daemon: it reads `alln serve status --json` and reports what it sees.
> A `--mutate-product-agent <scenario>` flag opts into the destructive path, and
> the only scenario in this slice is `crash-restart`. That scenario sends TERM to
> the live daemon, waits for launchd to supply a replacement, and asserts the
> §4.2 restart contract on the real primitive. It must restore a healthy host
> before it exits, including when it fails partway.

## 3. Read only

- `scripts/works-test-wall-cooldown.sh` — the house pattern for a works-test
  script: `set -uo pipefail`, `log`/`pass`/`fail` helpers, a `FAILURES` counter,
  a `trap cleanup EXIT`, and a non-zero exit when any check failed. Match it.
- `docs/phases/Alln_Serve_Hotfixes.md` §4.2 (restart contract, `ThrottleInterval`,
  what exit `0` means) and §8 host matrix item 3.
- `alln serve status --json` output shape — `daemon.pid`, `daemon.daemonId`,
  `daemon.activeHealthRespondedAt`, `supervisor.loaded`, `supervisor.pid`,
  `supervisor.lastExitCode`, `state`.

## 4. Touch only

```text
scripts/works-test-serve-continuity.sh
```

One new file. Nothing else — no Swift, no other script, no doc.

## 5. Do not touch

Any Swift source or test, `scripts/check.sh`, `scripts/rebuild_cli.sh`, any
other script, `docs/`, `Apps/`.

## 6. Steps

1. **Inspect-only is the default and is safe.** Bare invocation reads status and
   reports; it never signals, boots out, or writes. A reader must be able to run
   it on a working machine with no consequence. Exit non-zero only if the host is
   genuinely not healthy.

2. **Gate the destructive path behind `--mutate-product-agent crash-restart`.**
   Refuse any other scenario name with a usage error. No `--force`, no "all".

3. **Record the before state**: daemon pid, daemonId, `startedAt`,
   `supervisor.loaded`. Refuse to proceed unless the host starts `healthy` —
   a crash-restart proof that begins from a broken host proves nothing.

4. **TERM, then observe.** Send `TERM` to the daemon pid. Poll
   `alln serve status --json` until a **different** daemon pid appears with a
   matching active health response. Report two separate numbers: seconds until
   the replacement process appeared, and seconds from its appearance to active
   health. Assert the second is ≤ 15 s. Report the first against the 30 s
   `ThrottleInterval` without failing the gate on a legitimate throttle.

5. **Assert singularity.** After the restart, exactly one daemon process
   (`ps` for the canonical binary path), exactly one loaded agent
   (`launchctl list`), and daemon pid == supervisor pid. Zero Dock/`Allnighter`
   app processes at any point — the §2.4 claim.

6. **Then KILL.** Repeat with `KILL` (`-9`) on the new pid. Signal death must
   also produce a restart. Both halves must pass.

7. **Always leave the host healthy.** A `trap`-based cleanup runs
   `alln serve repair` and re-checks status if the script exits at any point
   without a healthy host, and says loudly that it did so. A proof script that
   leaves the founder's bench dead is worse than no proof script.

8. **Bounded everywhere.** Every poll has a deadline and a clear timeout
   message. No unbounded `while true`.

## 7. Works Test

```bash
bash scripts/works-test-serve-continuity.sh                 # inspect-only; must be safe and exit 0
bash scripts/works-test-serve-continuity.sh --bogus-flag    # usage error, exit non-zero
```

The mutating run is the founder's to authorize and the PM will run it:

```bash
bash scripts/works-test-serve-continuity.sh --mutate-product-agent crash-restart
```

## 8. Done when

- [ ] Bare invocation is inspect-only, touches nothing, and reports host state.
- [ ] Destructive path requires `--mutate-product-agent crash-restart`; any
      other scenario is a usage error.
- [ ] TERM produces a new daemon pid with active health, and the script reports
      time-to-respawn and time-to-health as two separate numbers.
- [ ] KILL (`-9`) also produces a restart. Both halves asserted.
- [ ] Exactly one daemon, one loaded agent, daemon pid == supervisor pid, zero
      Dock processes after each restart.
- [ ] The script refuses to start from an unhealthy host.
- [ ] Cleanup leaves the host healthy on every exit path, and says so.
- [ ] No unbounded loop. Non-zero exit when any check fails.
- [ ] One commit, one new file.

## 9. Host-state invariant

Additive. With this slice committed and nothing else, the founder gains an
inspect-only diagnostic and an opt-in crash proof. The daemon, plist, schedulers
and canonical binary are untouched unless the mutating flag is passed.

## 10. Out of scope

Host matrix item 4 (vA → vB update, rollback with an injected bootstrap failure)
is the **next** slice, not this one. Do not add an `update-rollback` scenario
here — injecting a bootstrap failure needs a seam that does not exist yet, and
mixing it in would make this script unreviewable.
