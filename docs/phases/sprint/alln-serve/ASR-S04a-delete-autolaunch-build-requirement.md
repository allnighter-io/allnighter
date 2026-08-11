# ASR-S04a — delete detached auto-launch, build `ServeRequirement`

Status: **ready**
Seat: **Grok 4.5** (`model_grok`, grok CLI) — larger coupled slice by founder
direction 2026-08-11.
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §2.3
(launchd owns continuity; commands never spawn a detached substitute; the
preflight guards the *write of a deferred obligation*, never command entry),
§5.1 (retired grammar), §7 (`CLI -> app`), §10 (detached auto-launch deleted and
deny-listed).

**1 of 2** in the ASR-S04 cut. The architecture gate + seeded violation is
**S04b** and is deliberately not in this slice.

These two halves ship together on purpose. §8 says so: `ServeRequirement`
"replaces the very call sites this slice deletes." Deleting `ensureRunning`
without the replacement leaves a window where a command silently queues a
deferred obligation and no daemon ever claims it — the exact queue-honesty
failure `AGENTS.md` forbids.

## 1. Goal

An ordinary command can never start an unsupervised `alln serve` child. A
command that intends to create a **future background obligation** first asks one
shared `ServeRequirement` preflight and refuses loudly if the supervised daemon
is not actively healthy.

## 2. Copy-paste prompt

> Delete `ServeAutoLaunch`, `ServeAutoLaunchCLI`, the retired opt-out grammar,
> and the app's periodic capacity/probe ownership. Build `ServeRequirement` and
> convert the call sites per the audit in Step 4. Every launchd/health seam
> stays injected. Do not add the architecture gate — that is S04b.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeAutoLaunch.swift` and
  `Packages/AllnighterCore/Sources/AllnighterCLI/ServeAutoLaunchCLI.swift` —
  what is being deleted, and the opt-out grammar to retire.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeHealthClient.swift` +
  `ServeDaemonProbe.swift` — the active handshake `ServeRequirement` must use.
  Health is **observed**, never assumed.
- `Packages/AllnighterCore/Sources/AllnighterCLI/LoopEngineCLI.swift` lines
  20–40, 200–245, 410–430 only — the three live `ensureRunning` call sites.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeRequirement.swift        (new)
Packages/AllnighterCore/Sources/AllnighterEngine/ServeAutoLaunch.swift         (delete)
Packages/AllnighterCore/Sources/AllnighterCLI/ServeAutoLaunchCLI.swift         (delete)
Packages/AllnighterCore/Sources/AllnighterCLI/LoopEngineCLI.swift
Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift                     (stale comment only)
Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift
Apps/AllnighterMac/Sources/CapacityStripModel.swift
Apps/AllnighterMac/Sources/AllnighterMacApp.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeRequirementTests.swift (new)
Apps/AllnighterMac/Tests/CapacityStripModelTests.swift
```
Delete `ServeAutoLaunchTests` and any test that only covers deleted behavior —
§8 says replace obsolete tests, do not preserve tests for deleted behavior.
Other files may be touched **only** where the compiler forces it; list each one
in the report.

## 5. Do not read / do not touch

- Do **not** add the architecture gate or edit
  `scripts/check_architecture_policy.sh` / `validate_architecture_policy.py` —
  that is S04b, and it needs a seeded violation to prove it can fail.
- Do not touch `ServeLifecycle`, `ServeDesiredState`, `ServeRuntimeReceipts`,
  `ServeDaemon`, any scheduler, or `scripts/`.
- **Do not run `scripts/rebuild_cli.sh` or `alln install-cli`, and do not run
  `alln serve enable|disable|repair|restart`.** This machine is shared and those
  bounce the live daemon. Verify with
  `swift build --package-path Packages/AllnighterCore --product alln` and
  `scripts/swift-test.sh` only.
- Do not change run semantics. `alln run` must stay runnable with serve dead.

## 6. Steps

1. **Delete detached auto-launch.** Remove `ServeAutoLaunch`,
   `ServeAutoLaunchCLI`, and the three live call sites in `LoopEngineCLI`
   (≈ lines 31, 236, 420). Remove `--no-auto-serve` and `ALLN_NO_AUTO_SERVE`
   from the flag surface and `ContractRegistry`, and add both to
   `RetiredVocabulary` so they fail loudly rather than being silently ignored.
   Fix the now-false comments in `RunCLI.swift:171-173`.

2. **Build `ServeRequirement`.** One shared preflight:
   `require(reason:) -> Result<Void, Refusal>`. It observes supervised health
   through the **active handshake** (`ServeHealthClient` via `ServeDaemonProbe`),
   never a pid check or a plist check. On failure it returns the observed state
   and the recovery command `alln serve repair`. Health seams injected; no test
   opens a socket.

3. **Scope — the part most easily got wrong.** §2.3 draws a sharp line, and this
   slice must honor it exactly:
   - **Gated:** the *write of a deferred obligation* — a wake ticket, a park, a
     scheduled notification, a Boost seed, a vendor-backoff continuation, a
     cloud-relay entry.
   - **Not gated:** anything that runs now and returns its own result. `alln run`
     and an attended `alln loop` turn stay runnable with serve dead or disabled.

   Gating command entry would turn a health sensor into a veto, which the
   INFORM-never-BLOCK law forbids. Gating only the deferred write is the
   queue-honesty law. Put the refusal in exactly one place: `ServeRequirement` is
   the only code in the product allowed to make it.

4. **Audit table in the report.** For each §2.3 entry — Loop obligations,
   Pending wake, Boost seed, vendor-backoff continuation, notification
   scheduling, cloud relay — state the call site and a verdict of **gated** or
   **attended, not gated**, with one line of justification. A site you could not
   locate is reported as *not found*, never silently omitted.

5. **App stops owning periodic scheduling (§2.4).** Remove the periodic/wake
   portion of the app's capacity/probe acquisition and the socket-vs-disk truth
   split. The app keeps: rendering durable history, an explicit user refresh
   through the shared Engine operation, and the read-only status projection. It
   must not own a timer, a wake observer, or a silent vendor-CLI acquire.

6. **Retire the false teaching string.** `AllnighterCLI.swift:678` prints
   "Stop it with `kill <pid>` if you want a fresh one", which contradicts the
   supervised lifecycle. Replace it with the supported command. (This one line
   only — the broader teaching sweep is ASR-S05.)

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'ServeRequirementTests|CapacityStripModelTests|LoopEngine'
swift build --package-path Packages/AllnighterCore --product alln
```

## 8. Done when

- [ ] `ServeAutoLaunch` and `ServeAutoLaunchCLI` no longer exist; no source file
      references them (grep-provable, excluding `.build/`).
- [ ] `--no-auto-serve` / `ALLN_NO_AUTO_SERVE` are gone from flags, help, and
      `ContractRegistry`, and are present in `RetiredVocabulary`.
- [ ] `ServeRequirement` refuses when the active handshake fails, naming the
      observed state and `alln serve repair`.
- [ ] `ServeRequirement` uses the **handshake** — a test proves a live pid with
      nothing listening still refuses.
- [ ] A deferred-obligation write refuses when serve is unhealthy **and writes
      nothing** (assert the store is unchanged, not just the exit code).
- [ ] `alln run` and an attended `alln loop` turn still work with serve dead —
      asserted, because this is the law most at risk from this slice.
- [ ] The audit table covers all six §2.3 entries with explicit verdicts.
- [ ] The app owns no timer, wake observer, or periodic capacity/probe
      acquisition; explicit refresh still works.
- [ ] `AllnighterCLI.swift:678` no longer teaches `kill <pid>`.
- [ ] Package builds; focused proof passes. One commit, explicit paths.

## 9. Host-state invariant

No install, launchd, or plist change. The supervised daemon on the founder's
machine keeps running the canonical binary untouched — this slice only removes
the ability of *other* commands to spawn a rival, and adds a refusal where work
would otherwise be queued for a daemon that will not claim it.
