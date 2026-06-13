# 22 — Speculative Builds

Status: Draft
Milestone: F (Always-on and ship)
Depends on: 15, 17, 19, 21
Owner: Mac + iOS
Created: 2026-06-13

## Goal

When agents are idle and the user has opted in, do proactive, clearly-labeled,
**draft-only** work from approved local sources — turning idle capacity and the
preference model into "I noticed X and drafted Y on spec." Always easy to discard.

## Non-Goals

- Any non-draft (landing) output without explicit user action. Anything outside
  approved sources or standing orders.

## Approach (per source §11.7, `00` §10, §11)

- **Opt-in per project** + standing-orders enforcement gate everything.
- **Sources (approved):** TODO comments, GitHub issues, failed tests, Sentry, app
  reviews, previous user notes. v1 starts with **TODO comments + GitHub issues**.
- **Local-worker preferred** (Phase 19) for mining + drafting; idle/power/thermal
  rules from `00` §11 decide when to run.
- All output is **draft-only** (`00` §10 risk tier), clearly labeled as
  speculative, surfaced in Morning Pull ("I noticed onboarding drop-off and
  drafted two lighter signup flows on spec. Keep either?"), easy to discard.

## Ordered Slices

- [ ] P22-S01 — Per-project speculation toggle + standing-orders enforcement.
- [ ] P22-S02 — Source: TODO comments → draft work orders.
- [ ] P22-S03 — Source: GitHub issues → draft work orders.
- [ ] P22-S04 — Draft-only classification + clear "speculative" labeling.
- [ ] P22-S05 — Morning Pull presentation + one-tap keep/discard.

## Works Test

```text
With speculation enabled and the bench idle, Allnighter mines a TODO, drafts a
small fix on spec in a draft-only lane, labels it speculative, and presents it in
Morning Pull with keep/discard. Discard removes it cleanly.
```

## Exit Gates

- [ ] Works Test passes; output is draft-only and clearly labeled.
- [ ] Respects opt-in, standing orders, idle/power rules.
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 23 (distribution & dogfood).
