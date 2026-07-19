# RLC-S04 — Authorized substitution

Status: **ready** (after RLC-S02; can parallelize lightly with S03 if needed)
SSOT: `docs/phases/Rate_Limit_Continuity.md` §Substitution

## Goal

Substitution authorized by selection provenance only — Auto/declared fallbacks hop;
explicitly named worker never silent-hops. Capability filter, quiescence proof,
visited-set + hop bound, same run id + sequential attempts.

## Precedence with park (load-bearing)

When `VendorBackoffPolicy.shouldPark` is true on a single-worker mutating/
accepted run: **park wins** over immediate `SeatReseat` (unless Auto hop is
explicitly allowed by provenance table and user opted into cross-vendor). Spec
the table in code comments + tests.

## Done when

- [ ] Provenance table enforced
- [ ] Incompatible / visited / named-worker hops refused
- [ ] Original worker quiescent before substitute starts
- [ ] Bounded hop count; one source at a time
- [ ] Committed `feat(rlc): S04 — authorized substitution on park`
