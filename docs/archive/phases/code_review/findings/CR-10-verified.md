# CR-10 — verified

## Summary
CR-10 filed **no P0 claims** ("P0 — None"), so there are zero P0 verdicts to
uphold or reject. The two P1 findings were both checked against the inlined
sources and are **materially correct as written** — the `newestSuffix`
O(drops × n) hot-path cost and the re-entrant `DispatchQueue.sync` deadlock
are both fully grounded in the inlined code with no reliance on actor
suspension. The P2 nits were spot-checked and none are materially wrong; they
are not re-summarized here per the verify rules.

## P0 adjudication

No P0 claims were filed in CR-10 (findings section "P0 — None"). Nothing to
uphold or reject.

## P1 notes

### P1 — `newestSuffix` is O(drops × n) on the streaming hot path — Upheld
- **Mechanism confirmed in source.** `append` re-checks
  `text.utf8.count > capBytes` on every call
  (`StreamingPartialBuffer.swift:37`); after truncation `text` is reset to a
  suffix ≤ `capBytes` (`:38`), so the next `text += delta` re-exceeds the cap
  and re-enters `newestSuffix` on every subsequent append. Inside
  `newestSuffix` (`:49-56`) the `while out.utf8.count > maxBytes, !out.isEmpty`
  loop drops one `Character` per iteration via `out = out.dropFirst()` and
  re-evaluates `out.utf8.count` (O(remaining bytes)) each iteration. The
  claimed ~128 M byte-touches for a 2 KB ASCII delta over a 64 KB cap follows
  from the loop bound (~2048 iterations) × ~64 KB per `utf8.count` scan.
- **No actor suspension involved.** Pure synchronous value-type code; the
  reject-on-actor-suspension criterion does not apply.
- **Verdict:** Upheld.

### P1 — Re-entrant `DispatchQueue.sync` deadlocks on same root — Upheld
- **Mechanism confirmed in source.** The lane key is
  `rootDirectory.standardizedFileURL.path`
  (`ThreadStoreWriteSerializer.swift:15`); the same root resolves to the same
  `Lane` and thus the same `DispatchQueue` (`:17-24`). The body runs via
  `lane.queue.sync(execute: body)` (`:26`). `DispatchQueue.sync` is
  non-reentrant by contract — a nested `sync` onto the same queue from within
  the running work item deadlocks. No reentrancy guard exists in the inlined
  source (no `dispatch_get_specific` key, no `OS_ALLOCATOR_KEY`, no recursive
  lock). The static entry point (`:32-34`) routes back through the same
  `Registry`, so a nested call for the same root hits the same queue.
- **Hedge acknowledged.** Whether the deadlock actually triggers depends on
  `body` calling back into `synchronized` for the same root, which is not
  provable from the inlined sources (`ThreadStore.updateTurn` is opaque). The
  finding states this hedge explicitly ("If `body` calls
  `ThreadStoreWriteSerializer.synchronized(rootDirectory: ...)` for the same
  root"). The latent-risk claim stands.
- **No actor suspension involved.** Synchronous `DispatchQueue.sync` only.
- **Verdict:** Upheld (as a latent risk, matching the finding's framing).

## Greps avoided
No files outside the two inlined sources
(`StreamingPartialBuffer.swift`, `ThreadStoreWriteSerializer.swift`) were
read or grepped. `ThreadStore.updateTurn`, the wiring-layer flush timer, and
the store's write implementation were treated as opaque, matching CR-10's
scope. The P2 full-text-flush I/O finding remains hedged on that unknown
store contract and was not re-investigated.