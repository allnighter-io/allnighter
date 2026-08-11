# ASR-S03f1b — a stopped required scheduler under a live daemon is degraded

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §5.2
(top-level state answers "is useful scheduling alive?"), §7
(`daemon -> scheduler`: a process answering does not mean schedulers work).

**10 of N** in the ASR-S03 cut. Corrects one resolver rule shipped in
`41f39215` (S03f1). Nothing else in that slice is in question — the shape, the
purity, and the other 33 tests are sound.

## 1. The defect

`41f39215` ships this, and a test that locks it in:

```swift
func testStoppedRowDoesNotAloneDegradeWhenOtherwiseHealthy() {
    input.receipt = .present(..., rows: requiredRows(state: .stopped))
    XCTAssertEqual(status.state, .healthy)   // <- every required scheduler stopped
}
```

So: **all seven required schedulers stopped, daemon still answering the health
handshake → `healthy`.**

That is the exact failure this packet exists to eliminate. A daemon whose
scheduler loops have all broken out, still serving `/health`, is the canonical
"serve is running but nothing is happening" wedge. §5.2 exists precisely to stop
status from answering "does a pid exist?" — and this rule reinstates that answer
under a new word.

It is also internally inconsistent: `testHealthyDrop_missingRequiredScheduler`
degrades when a required row is **absent**, while a row that is present and
stopped stays healthy. Absent is strictly *less* alarming than
stopped-while-the-daemon-lives.

## 2. Why the original reasoning was wrong

S03e2c introduced `stopped` to mean "daemon shutdown / cancellation", and the
resolver comment reasons that stand-down pairs with the supervisor rather than
indicating scheduler failure. That is true for the shutdown case — but in the
shutdown case **the handshake also dies**, so that state already resolves to
`degraded` through the supervisor path. It never needed this rule.

What the rule actually covers is the *other* case: a scheduler stopped while the
daemon is alive and answering. `stopped` + live matching handshake is a
contradiction, not a stand-down. Some loop exited and nothing restarted it. That
is a degradation, and it is the most valuable one this resolver can report.

## 3. Copy-paste prompt

> In `ServeStatusJSON`, make a `stopped` **required** scheduler row resolve to
> `degraded` — naming which schedulers stopped — whenever the daemon is
> otherwise live and answering the handshake. Invert
> `testStoppedRowDoesNotAloneDegradeWhenOtherwiseHealthy` to assert `degraded`
> and rename it to say what it now proves. Change nothing else about the
> resolver, the shape, or the other tests.

## 4. Read only

- `git show 41f39215` — the resolver and its test table.
- `docs/phases/sprint/alln-serve/ASR-S03e2c-wire-remaining-and-cancellation.md`
  §10 — where `stopped` came from and what it was meant to mean.

## 5. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusJSON.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeStatusResolverTests.swift
```

## 6. Do not touch

Every other file. Do not change the v2 shape, do not add fields, do not touch
any scheduler, `ServeRuntimeReceipts`, `ServeDaemon`, any CLI file, or any
script. The resolver stays pure — no `FileManager`, `Process`, `URLSession`, or
`Date()`.

## 7. Steps

1. **Invert the test first and watch it fail.** Rename it to
   `testStoppedRequiredSchedulerUnderLiveDaemonIsDegraded` and assert
   `degraded`. Run it against the current resolver and confirm it fails before
   changing any source. That failure is this slice's negative proof.

2. **Resolver rule.** A required row in `stopped`, while the supervisor is
   loaded and the active handshake matches, is a degradation. `recovery` names
   the stopped scheduler ids — not a generic "degraded". One stopped required
   scheduler is enough; do not require all of them.

3. **Do not degrade on `stopped` when the daemon is not live.** If there is no
   matching handshake, the existing supervisor path already decides the state
   and must keep deciding it. This slice adds one rule for one situation; it
   does not reroute the shutdown case.

4. **`cloudRelay` is unaffected.** It is optional and stays `registered` by
   design (S03e2c). A stopped *optional* scheduler does not degrade.

5. **Leave the §7 ban-table tests alone.** They pass and they are correct.

## 8. Works Test

```bash
scripts/swift-test.sh --filter 'ServeStatusResolverTests'
```

## 9. Done when

- [ ] The inverted test was seen to fail against `41f39215` before the source
      changed. Say so in the commit message.
- [ ] One stopped required scheduler under a live matching handshake →
      `degraded`, with `recovery` naming that scheduler id.
- [ ] A stopped *optional* scheduler under a live handshake → still `healthy`.
- [ ] `stopped` rows with no matching handshake resolve exactly as they did
      before this slice — asserted, so the shutdown path is provably unchanged.
- [ ] All 34 pre-existing tests still pass, one of them inverted and renamed.
- [ ] The resolver is still pure. One commit, explicit paths.

## 10. Host-state invariant

Inert. The resolver is still called by nothing (CLI wiring is S03f2). No
command's output changes, no daemon behavior changes.
