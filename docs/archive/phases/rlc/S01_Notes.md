# RLC-S01 convergence notes

RLC-S01 promotes the existing `CapacityObservation` into unified-run truth. A
parked run records that observation on `RunBlocker.resource = .vendorBackoff`
and in its append-only `TeamRun.attempts`; it does not create a second
rate-limit type or classifier.

## Pending versus unified-run ownership

- `PendingResume.capacityObservation` remains the capacity fact for work that is
  already a Pending item.
- An accepted unified run that waits on a vendor stays the same run and does
  **not** mint a Pending item.
- Pending wake scheduling remains the Pending path. Coordinator reconciliation
  for unified-run vendor parks belongs to RLC-S02; S01 adds no wake runtime.
- `CapacityClassifier` remains the only classifier for both consumers.
- Existing `SeatReseat` text cues remain eligible for immediate reseating until
  RLC-S04 freezes selection-origin and substitution precedence. They are not a
  second source of durable capacity truth.

The S01 policy helper parks only high-confidence account limits. Busy,
unavailable, unknown-capacity, auth, and manual-action observations continue
through their existing paths.
