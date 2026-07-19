# RLC-S04 — Authorized substitution

Status: **delivered** (RLC-S04)
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

- [x] Provenance table enforced
- [x] Incompatible / visited / named-worker hops refused
- [x] Original worker quiescent before substitute starts
- [x] Bounded hop count; one source at a time
- [x] Committed `feat(rlc): S04 — authorized substitution on park`
