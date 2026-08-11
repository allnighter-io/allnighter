# ASR-S06 gate 3 — TERM/KILL crash restart — **PASS** (after ASR-S06b)

Date: 2026-08-11 (UTC)
Gate: §8 ASR-S06 **gate 3** — "TERM then KILL: launchd supplies a new pid and
active health within 15 s; no extra daemon and no Dock process."
Host: second Mac (Mac mini), macOS 15.6 (24G84), arm64.
Build under test: `476e9d80` (ASR-S06b + fixup), contract 9.19.0, ad-hoc.
Harness: `scripts/works-test-serve-continuity.sh --mutate-product-agent crash-restart`.

**This gate failed first.** The failing run and the defect it found are recorded
separately in
[`2026-08-11-gate3-crash-restart-FAIL.md`](2026-08-11-gate3-crash-restart-FAIL.md).
That record stands; this one does not replace it. A gate that only ever shows a
pass hides the thing it caught.

## Result: PASS — 24 assertions, 0 failures, run twice

| Half | time-to-respawn | ThrottleInterval budget | time-to-health after respawn | §8 budget |
| --- | --- | --- | --- | --- |
| TERM | 16 s | 30 s | **1 s** | 15 s |
| KILL | 28 s | 30 s | **0 s** | 15 s |

Per-restart assertions, all passing on both halves:

- exactly one daemon process for the canonical binary;
- exactly one loaded LaunchAgent (`com.allnighter.resident-coordinator`);
- `daemon.pid == supervisor.pid`;
- **zero** Dock/`Allnighter` app processes at any point (§2.4);
- host `healthy` after both halves.

Evidence: `runs/2026-08-11-gate3/gate3-pass.log`.

An earlier hand-measured cycle observed respawn and active health both at **1 s**
after TERM — launchd does not always wait out the throttle. The 16 s and 28 s
figures above are the harness's measurements on back-to-back restarts, where the
throttle does apply. Both are inside budget; the gate's 15 s bound is on
respawn→health, which was 1 s and 0 s.

## What made it pass

`ServeDaemon` now restores the default SIGTERM disposition and re-raises the
signal after settling receipts, so the process dies **by signal** and launchd
restarts it per §4.2. Before the fix the daemon exited `0`, which
`KeepAlive = { SuccessfulExit = false }` correctly treats as a deliberate
stand-down — no respawn, ever.

The launchd job's own counter is the cleanest witness: `runs` stayed at **1**
indefinitely before the fix, and advanced **1 → 2 → 3** across restarts after it.

## What this does NOT prove

- **§10.1 R1 is not closed.** This defect shares a fingerprint with the two
  unexplained launchd events (job loaded, no process), and is a plausible
  explanation for them — but neither incident recorded an exit code, so the link
  cannot be confirmed retroactively. Do not archive the packet implying the
  2026-08-09 LWCR root cause is identified.
- **The re-raise itself is not unit-tested.** `shouldReraiseSIGTERM(after:)`
  carries the decision logic and is covered; the two-line delivery
  (`signal(SIGTERM, SIG_DFL)` then `raise(SIGTERM)`) is proven only by this host
  gate. An injectable seam was tried, failed to compile under Swift 6 strict
  concurrency, and was deliberately dropped — see `476e9d80`.
- **No unit test has executed on this host at all.** XCTest is unavailable
  (`xcode-select` points at CommandLineTools).
- Only TERM and KILL are covered. A daemon that wedges without dying, or one
  killed while holding active obligations, is untested.
- Host matrix item 4 (vA → vB update, rollback with an injected bootstrap
  failure) remains unrun.

## Reproduce

```bash
bash scripts/works-test-serve-continuity.sh                                  # inspect-only
bash scripts/works-test-serve-continuity.sh --mutate-product-agent crash-restart
launchctl print gui/$(id -u)/com.allnighter.resident-coordinator | grep "runs ="
```

## Signature

Recorded by the PM agent; the destructive run was founder-authorized. Per §8 the
founder is the signer.

**Signed:** _pending founder countersignature._
