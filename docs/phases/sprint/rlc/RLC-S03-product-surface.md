# RLC-S03 — Product surface

Status: **done** (Mac onboarding fixture demo waived — CLI fake worker shipped)
SSOT: `docs/phases/Rate_Limit_Continuity.md` §Product surface

## Goal

Owner-visible park/resume: truthful `ps`/GUI copy, Resume now / Use another model /
Cancel, two notifications, morning receipt (observed facts only), onboarding
fake-CLI demo.

## Out of scope

Substitution policy guts (S04 may wire "Use another model"); burn estimates.

## Done when

- [x] Parked run copy: "Waiting for {vendor} — resumes around {T}"
- [x] Actions: Resume now / Cancel / Use another model (RLC-S04)
- [x] Park + recovery notifications once each (run-scoped dedup)
- [x] Morning receipt from observed wait coverage (`alln continuity receipt`)
- [x] CLI demo path: `scripts/rlc_fake_limit_worker.sh` (Mac onboarding waived)
- [x] Committed `feat(rlc): S03 — park surface + notifications + receipt`
