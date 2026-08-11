# ASR-S06g — an idle scheduler is not a failed one

Status: **ready**
Priority: **P2 — gate 5 currently fails for the wrong reason.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §6
(runtime receipts), §8 host matrix item 5, and the project law *"Absence of a
declared signal yields no observation, never an inferred one."*

## 1. Measured

`--assert identity-and-receipts` (ASR-S06f, `0fd6058f`) failed gate 5:

```text
FAIL — gate-5-receipts: receipt did not advance within 115.7s budget —
       probeRecordRefresh lastSuccessAt still None, nextWakeAt='2026-08-11T19:56:42Z'
```

But the daemon is healthy and doing exactly what it should. Receipts:

```text
capacityRefresh      attempt=19:47:22  success=19:47:29  err=None
probeRecordRefresh   attempt=None      success=None      err=None
```

`probeRecordRefresh`'s `nextWakeAt` **does** advance (19:51:42 → 19:56:42), so
the loop is running. It simply has nothing to do:
`ProbeRecordRefreshScheduler.shouldSmoke` returns false while every non-parked
probe record is fresher than `ProbeFreshnessGate.gateInterval` (30 min), and the
loop then re-arms without calling `progress.attempting`.

So the scheduler woke, found no work, and re-armed — correct behaviour, reported
as a failure.

## 2. Two separate problems

**(a) The harness asserts the wrong thing.** Gate 5's substance is *"a persisted
absolute vendor invocation works under launchd's minimal PATH"*.
`capacityRefresh` is the scheduler that spawns vendor CLIs, and it advanced —
that is the evidence. `probeRecordRefresh` only smokes when records are stale, so
requiring it to advance inside a two-minute window is a proof that fails for the
wrong reason on any host whose probes are fresh.

**(b) A real observability gap, worth recording even if not fixed here.** A
scheduler that woke, found nothing due, and re-armed is **indistinguishable in
the receipts from one that never ran at all**: `lastAttemptAt: null`,
`lastSuccessAt: null`, `lastError: null`, `state: waiting`. §6 lists
registered/running/waiting/failed but has no "idle, nothing due". A reader cannot
tell healthy-and-idle from never-started.

This slice fixes (a). For (b), **decide and state a recommendation in the commit
message** — do not implement it here; it is a receipt-schema change and belongs
in its own slice if it is worth doing.

## 3. Copy-paste prompt

> Gate 5's receipt check should assert that `capacityRefresh` advances — it is
> the scheduler that spawns vendor CLIs and therefore the one that proves an
> absolute vendor invocation works under launchd's minimal PATH. A scheduler
> whose `nextWakeAt` advances while it records no attempt has woken and found no
> work; report that plainly as idle and do not fail on it. Keep the honest-skip
> behaviour for a deadline that falls outside the window.

## 4. Read only

- `scripts/works-test-serve-continuity.sh` — the `identity-and-receipts` block.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ProbeRecordRefreshScheduler.swift`
  — `shouldSmoke` and the loop, to confirm the idle path is real and not a bug.
  **Do not change this file.**

## 5. Touch only

```text
scripts/works-test-serve-continuity.sh
```

## 6. Do not touch

Any Swift source or test. Any other script. The receipt schema.

## 7. Steps

1. **`capacityRefresh` advancing is the assertion.** It must advance within a
   budget derived from its `nextWakeAt`, or the gate fails. This is gate 5's real
   content and it must stay able to fail.

2. **Classify a non-advancing scheduler before judging it.** Distinguish three
   cases from receipts alone and report which one was seen:
   - *idle* — `nextWakeAt` advanced while `lastAttemptAt` stayed null: woke,
     nothing due, re-armed. **Not a failure.**
   - *out of window* — `nextWakeAt` beyond the budget: honest skip, as today.
   - *stuck* — `nextWakeAt` did **not** advance and no attempt recorded: that is
     a real failure and must fail.

3. **Never infer a reason you cannot see.** The harness cannot read
   `shouldSmoke`; it may only report what the receipts show. Say "no attempt
   recorded and deadline re-armed — idle", not "probe records are fresh".

4. **Print the classification for every required scheduler**, so the output shows
   what each one was doing rather than only the failures.

## 8. Works Test

```bash
bash scripts/works-test-serve-continuity.sh --assert identity-and-receipts   # must now pass
bash scripts/works-test-serve-continuity.sh                                  # unchanged
bash scripts/works-test-serve-continuity.sh --bogus                          # usage error
```

All three are safe and non-mutating — run them yourself and paste real output.

## 9. Done when

- [ ] `capacityRefresh` advancing is asserted and can still fail.
- [ ] Idle / out-of-window / stuck are distinguished from receipts alone, and
      only *stuck* fails.
- [ ] Every required scheduler's classification is printed.
- [ ] No reason is claimed that the receipts do not show.
- [ ] `--assert identity-and-receipts` passes on this host.
- [ ] A recommendation on the §6 idle-state gap is stated in the commit message,
      not implemented.
- [ ] One commit, one file.

## 10. Host-state invariant

Read-only. Nothing on the host changes.
