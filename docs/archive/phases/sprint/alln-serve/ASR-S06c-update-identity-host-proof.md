# ASR-S06c — vA → vB update host proof (gate 4, first half)

Status: **ready**
Priority: **P1 — the last unrun host gate that needs no product change.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §8
host matrix item 4, §4.3 install/update transaction, §2.1 one canonical binary.
Pattern: [`ASR-S06a`](ASR-S06a-crash-restart-host-proof.md) built the script and
its `crash-restart` scenario; this adds a second scenario to it.

## 1. Gate 4, split

> vA → vB update: one agent, one daemon, new build identity, no orphan/staged
> copy, rollback proven with an injected bootstrap failure.

Two halves with very different risk:

| Half | Needs | Slice |
| --- | --- | --- |
| **update** — one agent, one daemon, new build identity, no orphan/staged copy | nothing new; just perform a real update and assert | **this one** |
| **rollback** — proven with an injected bootstrap failure | a failure-injection seam in production code that does not exist | **ASR-S06d**, next |

This slice is the update half only. **Do not build the injection seam here.** An
env var that can break a real install is a change to production behaviour and it
gets its own review.

## 2. Copy-paste prompt

> Add a second mutating scenario, `update`, to
> `scripts/works-test-serve-continuity.sh`. It performs a real vA → vB CLI update
> on the live host via `scripts/rebuild_cli.sh`, and asserts §8 item 4's update
> half: exactly one LaunchAgent, exactly one daemon, the daemon running the NEW
> build identity, and no orphaned process or staged copy left behind. Default
> inspect-only behaviour and the existing `crash-restart` scenario must be
> untouched.

## 3. Read only

- `scripts/works-test-serve-continuity.sh` — the whole script. Reuse its
  helpers (`read_status_fields`, `assert_singularity`, `wait_for_host_healthy`,
  the cleanup trap) rather than writing new ones. Note the stdout/stderr rule at
  the top: **diagnostics go to stderr**, because helpers return payloads on
  stdout for `$(...)` capture. Breaking that rule is what made gate 3 fail
  spuriously the first time.
- `scripts/rebuild_cli.sh` — how a new build is produced and installed. It
  execs `install-cli` on the freshly built binary.
- `docs/phases/Alln_Serve_Hotfixes.md` §4.3 (the transaction's ordering and what
  it promises) and §2.1 (canonical layout, the staged-copy path that must stay
  empty).

## 4. Touch only

```text
scripts/works-test-serve-continuity.sh
```

One file. No Swift. No other script. No doc.

## 5. Do not touch

Any Swift source or test, `scripts/rebuild_cli.sh`, `scripts/check.sh`, any other
script, `docs/`, `Apps/`. Do not add a failure-injection env var or flag — that
is ASR-S06d.

## 6. Steps

1. **`--mutate-product-agent update`.** A third accepted value alongside
   `crash-restart`; anything else stays a usage error. Bare invocation stays
   inspect-only and unchanged.

2. **Refuse to start from an unhealthy host**, exactly as `crash-restart` does.
   Record before state: daemon pid, daemonId, and the running build identity
   (`binary.runningGitSha`, and the cdhash via `codesign -dvvv` on the canonical
   binary).

3. **Perform a real update** by running `bash scripts/rebuild_cli.sh`. Report its
   exit status. If it fails, fail the scenario with its output — do not retry.

4. **Assert the update half of §8 item 4**, after waiting for health (respect the
   bounded `starting` window the script already understands):
   - `binary.matches: true` and `runningGitSha` equals the expected sha;
   - the build identity **changed** from the before state — a cdhash equal to
     the before cdhash means nothing was actually replaced, and an update proof
     that did not change the binary proves nothing. Say so explicitly if the
     rebuild was a no-op because the tree was unchanged;
   - exactly one loaded LaunchAgent, exactly one daemon process, daemon pid ==
     supervisor pid, zero Dock processes — reuse `assert_singularity`;
   - **no staged copy**: `~/Library/Application Support/Allnighter/CLI/alln`
     must not exist (§2.1 deletes it);
   - **no orphan**: no `alln serve` process whose pid is not the supervisor's,
     and none reparented to PID 1;
   - the PATH symlink `~/.local/bin/alln` still resolves to the canonical
     binary.

5. **Leave the host healthy** on every exit path, via the existing cleanup trap.

6. **Bounded everywhere.** Every wait has a deadline and a clear timeout message.

## 7. Works Test

```bash
bash scripts/works-test-serve-continuity.sh                              # unchanged, inspect-only, exit 0
bash scripts/works-test-serve-continuity.sh --mutate-product-agent crash-restart   # still passes
bash scripts/works-test-serve-continuity.sh --bogus                      # usage error
```

The PM runs the new scenario on the live host — it rebuilds and reinstalls the
founder's CLI, so it is the founder's call, not the implementer's:

```bash
bash scripts/works-test-serve-continuity.sh --mutate-product-agent update
```

**Do not run the `update` scenario yourself.**

## 8. Done when

- [ ] `update` scenario exists; `crash-restart` and inspect-only are unchanged
      and still pass.
- [ ] Before/after build identity is recorded and the change is asserted, with an
      explicit failure when the identity did not change.
- [ ] One agent, one daemon, pid match, zero Dock processes after the update.
- [ ] No staged copy under Application Support; no orphan; PATH symlink still
      resolves to canonical.
- [ ] Refuses to start from an unhealthy host; leaves the host healthy on exit.
- [ ] Diagnostics on stderr, payloads on stdout — the gate 3 lesson holds.
- [ ] No unbounded loop. Non-zero exit on any failure. One commit, one file.

## 9. Host-state invariant

Additive to the harness. The `update` scenario does mutate the founder's install
— it is a real rebuild — but only through the supported path the founder already
runs by hand many times a day.

## 10. Out of scope

The rollback half of gate 4. Gate 4 is **not** recorded as passed by this slice
alone; the record must say the update half passed and the rollback half is
pending ASR-S06d.
