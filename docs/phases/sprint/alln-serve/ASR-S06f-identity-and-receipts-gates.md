# ASR-S06f — gates 2 and 5, both inspect-only

Status: **ready**
Priority: **P2 — two unrun host gates that need no mutation at all.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §8
host matrix items **2** and **5**, §6 (runtime receipts), §4.2 (deterministic
plist PATH), §7 (`PATH -> vendor availability`).

Both gates are assertions over `alln serve status --json` and the plist. Neither
signals, rebuilds, or writes. They belong in the same slice because they are the
same kind of check on the same command, and splitting them would double the
harness plumbing for no review benefit.

## 1. The two gates

**Item 2** — "`serve status --json` healthy with canonical binary/agent/daemon
identity equal and every required scheduler registered."

**Item 5** — "Capacity and probe receipts advance from serve with the app absent;
a persisted absolute vendor invocation works under launchd's minimal PATH."

Item 5 is the interesting one. §7's `PATH -> vendor availability` ban says
scheduler spawns must use resolved absolute invocations because launchd's PATH is
a fallback only. `capacityRefresh` spawns real vendor CLIs. So a
`capacityRefresh` `lastSuccessAt` that advances **inside the daemon** is direct
evidence that an absolute vendor invocation worked under the minimal PATH — the
daemon has no login shell and no user PATH.

## 2. Copy-paste prompt

> Add an inspect-only scenario `--assert identity-and-receipts` to
> `scripts/works-test-serve-continuity.sh` covering §8 host matrix items 2 and 5.
> It must not signal, rebuild, or write anything. It asserts identity equality and
> required scheduler registration, then observes two receipts advancing over a
> bounded wait, and reads the installed plist to confirm the daemon's PATH is the
> deterministic minimal one rather than a login shell's.

## 3. Read only

- `scripts/works-test-serve-continuity.sh` — helpers and the stderr/stdout rule.
- `docs/phases/Alln_Serve_Hotfixes.md` §4.2 (plist shape, deterministic PATH),
  §6 (the required scheduler id list), §8 items 2 and 5.
- `~/Library/LaunchAgents/com.allnighter.resident-coordinator.plist` — the
  installed plist, to read `EnvironmentVariables.PATH`.

## 4. Touch only

```text
scripts/works-test-serve-continuity.sh
```

## 5. Do not touch

Any Swift source or test, any other script, `docs/`, `Apps/`.

## 6. Steps

1. **`--assert identity-and-receipts`**, a new *non-mutating* flag, distinct from
   `--mutate-product-agent`. It must be safe to run at any time and must not
   require founder approval. Unknown values stay a usage error.

2. **Item 2 assertions:**
   - `state == healthy`, exit 0;
   - `binary.matches == true` and `runningGitSha == expectedGitSha`;
   - `binary.path` equals the canonical path, and the loaded agent's `program`
     (from `launchctl print`) equals that same path — the agent and the daemon
     name one binary;
   - `daemon.pid == supervisor.pid`;
   - every required scheduler id from §6 is present:
     `pendingWake`, `pmTurnWake`, `boostSeed`, `vendorBackoff`, `notifications`,
     `capacityRefresh`, `probeRecordRefresh`. `cloudRelay` is optional — its
     absence is **omitted, never failed** (§6). Fail on a *missing required* id,
     not on an absent optional one.

3. **Item 5 assertions — receipts advance:**
   - record `lastSuccessAt` for `capacityRefresh` and `probeRecordRefresh`;
   - wait, bounded, until both advance, or time out with a clear message naming
     which did not move and what its `nextWakeAt` was;
   - derive the wait budget from the observed `nextWakeAt` values rather than
     hardcoding a guess, and say what budget was chosen. If a `nextWakeAt` is
     further out than the budget, **skip and say so plainly** — a receipt that
     had no deadline in the window is not a failure, and calling it one would be
     a proof that fails for the wrong reason.

4. **Item 5 — minimal PATH, read from the installed plist:**
   - `EnvironmentVariables.PATH` exists and contains the canonical install dir;
   - it does **not** contain a login-shell-only path such as `/opt/homebrew/bin`
     — §4.2 requires the fallback PATH be the canonical dir plus standard system
     dirs, never an inherited shell PATH.
   - Report the actual PATH string in the output either way.

5. **The Dock app is absent** — assert zero `Allnighter.app` processes, and
   report whether `/Applications/Allnighter.app` exists at all (§9's
   precondition). Absence of the app is a fact worth printing, not an assertion
   that must hold on every host.

6. **Bounded, non-zero on failure, diagnostics on stderr.**

## 7. Works Test

```bash
bash scripts/works-test-serve-continuity.sh                                  # unchanged
bash scripts/works-test-serve-continuity.sh --assert identity-and-receipts   # the new gate
bash scripts/works-test-serve-continuity.sh --bogus                          # usage error
```

All three are safe. **Run all three yourself and paste the real output** —
nothing here mutates the host.

## 8. Done when

- [ ] `--assert identity-and-receipts` exists, mutates nothing, exits non-zero on
      failure.
- [ ] Item 2: identity equality across binary/agent/daemon, and all seven
      required scheduler ids present; optional `cloudRelay` omitted, not failed.
- [ ] Item 5: both receipts observed advancing within a budget derived from
      `nextWakeAt`, with an honest skip when no deadline falls in the window.
- [ ] Item 5: plist PATH asserted minimal and printed.
- [ ] Dock app absence reported.
- [ ] Existing scenarios untouched and still passing.
- [ ] One commit, one file.

## 9. Host-state invariant

Purely additive and read-only. Nothing on the host changes.
