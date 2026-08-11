# ASR-S04b — architecture gate, proven by seeded violations

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §8
ASR-S04 (the gate and its seeded-violation requirement), §2.4 (the app owns no
serve lifecycle and no periodic scheduling), §7 rows `CLI -> app` and
`app -> freshness`.

**2 of 2** in the ASR-S04 cut. ASR-S04a (`6bacc609`) deleted the alternate
lifecycle and built `ServeRequirement`; S04a2 (`69d2f1f8`, `ddb039ef`) closed
the Pending wake gap. This slice makes the forbidden architecture
*unrepresentable* rather than merely absent today.

## 1. Goal

`scripts/check_architecture_policy.sh` fails if the app regains serve lifecycle
or periodic scheduling, or if non-lifecycle CLI code spawns `alln serve` — and
each new rule is proven able to fail by a seeded violation.

## 2. Copy-paste prompt

> Add the two rule families below to `config/architecture-policy.json` (and the
> validator if the policy schema cannot express them), then add a seeded-violation
> fixture per rule to the existing `--self-test` so each new rule is proven to
> fail on demand. Change no Swift source.

## 3. Read only

- `scripts/check_architecture_policy.sh` — the `--self-test` fixture harness and
  how fixtures are written.
- `scripts/validate_architecture_policy.py` — `load_policy` / `validate`, i.e.
  what rule shapes the policy schema already supports.
- `config/architecture-policy.json` — the existing rules to extend, and the
  naming/shape conventions to match.

## 4. Touch only

```text
config/architecture-policy.json
scripts/check_architecture_policy.sh
scripts/validate_architecture_policy.py   (only if the schema cannot express a rule)
```

## 5. Do not read / do not touch

- **Change no Swift source.** If a rule fails against the current tree, that is a
  finding — **report it, do not edit the Swift to make the gate pass.** A gate
  that was quietly accommodated proves nothing.
- Do not touch `scripts/check.sh`, `scripts/swift-test.sh`, or any other script.
- **Do not run `scripts/rebuild_cli.sh`, `alln install-cli`, or
  `alln serve enable|disable|repair|restart`** — shared machine; those bounce the
  live daemon.
- Do not weaken, narrow, or add exclusions to an existing rule to make the new
  ones fit.

## 6. Steps

1. **Rule family A — the app owns no serve lifecycle.** App source
   (`Apps/AllnighterMac/Sources/`) may not reference `ServeLifecycle`,
   `ServeInstallation`, `launchctl`, `SMAppService`, or any path that starts
   `alln serve`.

2. **Rule family B — the app hosts no periodic scheduling.** App source may not
   reference `CapacityRefreshScheduler` or `ProbeRecordRefreshScheduler`. §2.4
   allows the app to render durable history and to request an *explicit* user
   refresh through the shared Engine operation; it may not own the schedule.

3. **Rule family C — only lifecycle code spawns serve.** Non-lifecycle CLI/Engine
   code may not construct a process invocation of `alln serve`. Scope the
   allowance to the lifecycle owner (`ServeLifecycle`) and the daemon entry
   point; everything else is forbidden.

4. **Seeded violation per rule — this is the deliverable, not the rules.** §8 is
   explicit: *"A name-based gate that has never failed is not a gate."* For each
   rule family, add a fixture to the existing `--self-test` that writes a file
   violating exactly that rule and asserts the validator **exits nonzero** with a
   message naming that rule. A rule you cannot make fail on demand does not count
   as the negative proof §7 requires — if you cannot seed it, say so plainly
   rather than adding the rule unproven.

5. **Do not over-match.** Each rule must not fire on a legitimate construct: a
   comment mentioning the symbol, a doc string, a test fixture, or the app
   rendering `alln serve status` output. Add a fixture per rule proving the
   *legitimate* case still passes — a gate that fails on prose is a gate someone
   will disable.

6. **Report the current-tree result.** State whether every new rule passes
   against `HEAD` as-is. If one fails, name the file and line and stop; do not
   edit Swift.

## 7. Works Test

```bash
bash scripts/check_architecture_policy.sh
bash scripts/check_architecture_policy.sh --self-test
```

## 8. Done when

- [ ] Rules A, B, and C exist in `config/architecture-policy.json`.
- [ ] Each rule family has a seeded-violation fixture that makes the validator
      exit nonzero naming that rule (three failures proven on demand).
- [ ] Each rule family has a legitimate-construct fixture that still passes.
- [ ] `bash scripts/check_architecture_policy.sh` passes against `HEAD`, or the
      failure is reported with file and line and **no Swift was edited**.
- [ ] `--self-test` passes.
- [ ] No existing rule was weakened, narrowed, or given a new exclusion.
- [ ] No Swift source changed. One commit, explicit paths.

## 9. Host-state invariant

Scripts and config only. Nothing builds, installs, or touches launchd; the live
supervised daemon is untouched.
