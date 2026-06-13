# 18 — QA Worker

Status: Draft
Milestone: E (Intelligence layer)
Depends on: 06, 07
Owner: Mac
Created: 2026-06-13

## Goal

Add an automated QA pass that exercises a lane's running preview and produces a
**plain-language QA summary** attached to the landing card, raising trust before
landing. Reuses the Playwright capture sidecar from Phase 06.

## Non-Goals

- Full test authoring or coverage analysis. Native-app UI testing is post-v1
  (v1 QA targets web previews).

## Approach (per source §17 of Local-AI note / PRD §17)

- **QA work order** drives the Playwright sidecar to click through the lane
  preview (key flows from the project config or inferred), capturing
  pass/fail per flow + screenshots of failures.
- A worker (any healthy worker; **local worker preferred** once Phase 19 lands, for
  privacy/cost) interprets Playwright output into a short summary:
  "login works; settings fails on rotate."
- QA result attaches to the landing card and informs the risk classifier
  (assisted-tier on QA failure).

## Ordered Slices

- [ ] P18-S01 — QA work-order definition + flow source (config/inferred).
- [ ] P18-S02 — Playwright click-through of the lane preview with per-flow result.
- [ ] P18-S03 — Failure screenshots as artifacts.
- [ ] P18-S04 — Plain-language QA summary generation.
- [ ] P18-S05 — Attach QA result to landing card + feed risk classifier.

## Works Test

```text
A completed UI lane runs a QA pass that clicks through the preview and produces a
summary like "login works; settings fails on rotate," attached to the landing
card; a QA failure downgrades the lane to assisted-tier.
```

## Exit Gates

- [ ] Works Test passes on the sample web app.
- [ ] QA result visible on the landing card and affects risk tier.
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 19 (local workers).
