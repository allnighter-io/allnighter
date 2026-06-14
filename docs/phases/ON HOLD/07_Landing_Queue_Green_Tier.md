# 07 — Landing Queue (Green Tier)

Status: Draft
Milestone: B (Proof and previews)
Depends on: 03, 05, 06
Owner: Mac + Shared Core
Created: 2026-06-13

## Goal

Turn a completed lane into a trustworthy **landing card** and let the user land
green-tier work into the target branch with **one tap and one-tap revert**.
Finished work earns trust through tests, preview, conflict status, and risk
tiers — never blind-merge (Principle 5).

## Non-Goals

- Assisted-tier repair agent and draft-only PR automation are scaffolded but the
  **green tier** is the deliverable here. Auto-land is explicitly excluded from v1
  (`README` §5.5).

## Approach (per `00` §9.4, §10)

- **Risk classifier v0** assigns a `RiskTier`:
  - `green_land`: tests pass, no merge conflicts, preview booted, no protected
    paths touched.
  - `assisted_land`: conflicts, flaky tests, or uncertain preview.
  - `draft_only`: broad/risky change, protected paths, schema/billing/secrets,
    speculative work.
- **Merge simulation with no side effects:** `git merge-tree --write-tree
  <target> <branch>` detects conflicts and yields the merged tree (`00` §9.4).
- **Test execution:** run the project `test_command` in the lane; capture result.
- **Landing card** leads with outcome summary, screenshot/preview, test result,
  risk tier, touched-area summary, revert availability. Diff available, not the
  headline.
- **Land:** merge the lane branch into the target; capture merge SHA; write
  **revert metadata**. **Revert:** `git revert -m 1 <merge_sha>` — never reset or
  delete work.
- Protected-path touch → forced `draft_only` (`00` §10).

## Ordered Slices

- [ ] P07-S01 — Diff + touched-area summary for a lane branch.
- [ ] P07-S02 — Test command execution + captured result on the card.
- [ ] P07-S03 — Merge simulation via `git merge-tree` (conflict detection).
- [ ] P07-S04 — Risk classifier v0 (green/assisted/draft-only) incl. protected-path rule.
- [ ] P07-S05 — Landing queue + landing card (artifact-led).
- [ ] P07-S06 — One-tap green land (merge + merge SHA + post-merge check).
- [ ] P07-S07 — Revert metadata + one-tap revert (`git revert -m 1`).

## Works Test

```text
A completed lane with passing tests, a booted preview, no conflicts, and no
protected paths becomes a green-tier landing card. One tap merges its branch into
the target branch and records revert metadata. One tap revert produces a clean
rollback commit. A lane that touches a protected path is forced to draft-only and
explains why.
```

## Exit Gates

- [ ] Works Test passes; green land + revert verified on a real repo.
- [ ] Merge simulation never mutates the working tree.
- [ ] MAC-12 satisfied; `00` §10 risk-tier + protected-path rules enforced.
- [ ] Code Audit CLEAN.

## Closeout

Milestone B complete. Activate Phase 08 (mobile transport).
