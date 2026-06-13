# 17 — Quota Harvester

Status: Draft
Milestone: E (Intelligence layer)
Depends on: 05, 11, 16
Owner: Mac + iOS
Created: 2026-06-13

## Goal

Prevent prepaid agent capacity from expiring unused (Thesis T1). Track estimated
quota windows honestly, detect idle workers, and nudge the user to spend
expiring capacity on appropriately sized backlog tasks before reset — within
user-defined ceilings and quiet hours.

## Non-Goals

- Auto-dispatch is **opt-in only** and off by default. Speculative source mining
  is Phase 22.

## Approach (per source §18, `00` §11)

- **Inputs:** agent availability, estimated quota remaining, reset time, user
  spend ceiling, quiet hours, machine power state, backlog, task size estimate,
  standing orders, priority.
- **Honest estimation** (`00` §10): values are labeled — "Claude looks about 40%
  unused in this window," never "42% remaining." Per-driver estimator
  (`quota_estimate` capability), with manual window config fallback.
- **Behaviors:** show idle workers; suggest dispatches; prefer small tasks near
  reset; avoid long tasks when the machine may sleep; never wake the user unless a
  task is explicitly configured to interrupt; **auto-dispatch only when enabled**.
- Surfaced on Mac (Workers) and iOS (Home: idle/busy, next reset).

## Ordered Slices

- [ ] P17-S01 — Manual quota-window config + per-driver estimator (best-effort).
- [ ] P17-S02 — Estimated usage tracking with explicit "estimated" UI copy.
- [ ] P17-S03 — Idle-worker detection + reset-time nudge.
- [ ] P17-S04 — User spend ceilings + quiet hours.
- [ ] P17-S05 — Opt-in auto-dispatch of small near-reset tasks (off by default).

## Works Test

```text
As a quota window nears reset with idle capacity, Allnighter suggests backlog
tasks sized to use it, labeled with honest estimates. Quiet hours and ceilings
suppress dispatch. Auto-dispatch only acts when explicitly enabled.
```

## Exit Gates

- [ ] Works Test passes; all quota copy is honestly labeled as estimated.
- [ ] MAC-17 satisfied; ceilings + quiet hours respected.
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 18 (QA worker).
