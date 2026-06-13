# 05 — Single-Agent Factory

Status: Draft — **first end-to-end "wake up to progress" moment**
Milestone: A (Substrate)
Depends on: 01, 03, 04
Owner: Mac
Created: 2026-06-13

## Goal

Wire the substrate into the first complete loop, entirely on the Mac: capture a
task → create a lane → run one agent → stream events → detect completion → mark
ready. This is Loop A (single-agent night factory) and the proof that the factory
works before any mobile or parallelism is added.

## Non-Goals

- Previews/screenshots (Phase 06), landing (Phase 07), iOS (Phase 09),
  races/councils (Milestone D).

## Approach (per `00`)

- A minimal **dispatch pipeline**: `Task` (created from a typed prompt on Mac) →
  Lane Manager creates a lane → Router picks the one available healthy worker →
  Driver runs in the lane → events stream to the event bus and the command center
  → completion → lane `ready`.
- A minimal **work order** (`00` §7 / source §10.2) is constructed from the task +
  project standing orders + protected paths (enforcement begins here, `00` §10).
- The Lane Inspector (Mac) shows status timeline, logs, transcript, and the git
  diff of the lane branch.
- The **Lane Scheduler** concurrency cap (`00` §11) is introduced (cap = 1 is fine
  for this phase; the mechanism must exist).

## Ordered Slices

- [ ] P05-S01 — Work-order construction from task + standing orders + protected paths.
- [ ] P05-S02 — Dispatch pipeline: task → lane → router (single worker) → driver run.
- [ ] P05-S03 — Live event streaming into the command center (Active Lanes + Lane Inspector).
- [ ] P05-S04 — Completion handling → lane `ready`; show lane git diff.
- [ ] P05-S05 — Lane Scheduler concurrency cap + queue (mechanism, default cap configurable).
- [ ] P05-S06 — Protected-path enforcement at prompt construction (`00` §10).

## Works Test

```text
From the Mac app, type a small implementation task and dispatch it to one agent.
A lane is created, the agent runs in the lane worktree, output streams live into
the Lane Inspector, completion is detected, the lane goes "ready", and the lane's
git diff is visible. The user's active repo is untouched throughout.
```

## Exit Gates

- [ ] Works Test passes end to end on a real repo + real agent.
- [ ] Concurrency cap enforced; queued tasks wait.
- [ ] Protected-path rule applied to the work order.
- [ ] MAC-4, MAC-5 satisfied; core invariant verified.
- [ ] Code Audit CLEAN.

## Closeout

Milestone A complete. Activate Phase 06 (previews) — the first artifact-led
"magic" surface.
