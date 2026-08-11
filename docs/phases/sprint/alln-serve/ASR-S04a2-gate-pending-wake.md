# ASR-S04a2 — gate the Pending wake-ticket write

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §2.3
(the preflight guards the write of a deferred obligation; the first audit covers
Pending wake), `AGENTS.md` queue-honesty law ("prove a host will claim before
queuing, and refuse loudly").

Closes the one genuine gap ASR-S04a (`6bacc609`) reported honestly in its audit:
Pending wake was marked **not found (no gate this slice)** because the write path
sat outside that order's touch list. `ServeRequirement` exists and is proven; it
simply has one call site instead of two.

## 1. Goal

`alln pending add` (and any sibling that writes a **wake-scheduled** pending
item) calls `ServeRequirement` before the write, so a wake ticket is never
queued for a daemon that will not claim it.

## 2. Copy-paste prompt

> Add the `ServeRequirement` preflight to the pending wake-ticket write path per
> the Steps. Gate only the deferred write, never plain command entry. Do not
> touch `ServeRequirement` itself, the loop path, or any scheduler.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeRequirement.swift` —
  `require(reason:)` / `writeIfHealthy` and the `Refusal` shape.
- `Packages/AllnighterCore/Sources/AllnighterCLI/LoopEngineCLI.swift` around
  line 446–480 — the one existing gated call site; copy its shape and its
  refusal reporting exactly.
- `Packages/AllnighterCore/Sources/AllnighterCLI/PendingCLI.swift` — `runAdd`
  and the write path it calls.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterCLI/PendingCLI.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeRequirementTests.swift
```
If the wake-scheduled write actually lives in `PendingService` rather than the
CLI, gate it there instead and say so — but gate exactly one layer, not both.

## 5. Do not read / do not touch

- Do not modify `ServeRequirement`, `LoopEngineCLI`, `PendingWakeScheduler`, any
  other scheduler, `ServeDaemon`, or `ServeLifecycle`.
- **Do not run `scripts/rebuild_cli.sh`, `alln install-cli`, or
  `alln serve enable|disable|repair|restart`** — shared machine, those bounce the
  live daemon. Verify with `swift build --package-path Packages/AllnighterCore
  --product alln` and `scripts/swift-test.sh` only.
- Do not gate `pending list`, `show`, `run`, `submit`, `cancel`, or any read.

## 6. Steps

1. **Gate only the wake-scheduled write.** A pending item that carries a future
   wake time is a deferred obligation and is gated. A pending item with **no**
   wake scheduling is not — it is inert until someone acts on it, so gating it
   would be a health sensor vetoing an explicit request (INFORM-never-BLOCK).
   If the distinction is not representable in the current model, **stop and
   report** rather than gating all adds.

2. **Refuse before writing.** On refusal, exit nonzero with the observed state
   and `alln serve repair`, and write **nothing** — no pending record, no
   partial file. Assert the store is byte-for-byte unchanged, not merely that
   the exit code was nonzero.

3. **Match the existing refusal shape** from `LoopEngineCLI` so both gated sites
   report identically. One refusal vocabulary, not two.

4. **Keep the seam injected** so the test never opens a socket or requires a
   live daemon.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'ServeRequirementTests|Pending'
swift build --package-path Packages/AllnighterCore --product alln
```

## 8. Done when

- [ ] A wake-scheduled `pending add` with serve unhealthy refuses and leaves the
      pending store **unchanged** (asserted).
- [ ] The same add succeeds when the handshake reports healthy.
- [ ] A pending add with **no** wake scheduling is unaffected by serve health.
- [ ] Reads (`list`/`show`) are never gated.
- [ ] A live pid with nothing listening still refuses — the handshake, not a pid
      check, decides.
- [ ] Refusal text matches the loop site's shape.
- [ ] Build passes; focused proof passes. One commit, explicit paths.

## 9. Host-state invariant

No install, launchd, or plist change. Adds a refusal on one write path; the live
supervised daemon is untouched.
