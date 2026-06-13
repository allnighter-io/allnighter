# 03 — Lane Manager (Worktree Factory)

Status: Draft — **the moat. Build carefully.**
Milestone: A (Substrate)
Depends on: 01, 02
Owner: Mac
Created: 2026-06-13

## Goal

Implement the hidden concurrency factory: create, track, recover, and clean up
**isolated lanes**, each a git worktree + branch + port + process supervision
group, without ever touching the user's active working directory. This is the
hard local infrastructure that is the product's barrier to entry (`00` §T3).

No agent runs yet (Phase 04) — this phase proves the substrate with a fixture
process.

## Non-Goals

- Running real agents (Phase 04) or previews (Phase 06).
- Landing/merge (Phase 07) — creation and teardown only here.

## Approach (per `00` §9)

- **`GitClient`** gains worktree ops: `worktreeAdd(path, branch, baseCommit)`,
  `worktreeRemove`, `worktreePrune`. Branch naming
  `allnighter/<task-slug>/<short-lane-id>`.
- **Lane Manager** actor owns lane lifecycle and the `created → preparing →
  running …` transitions (validated via Core's state machine).
- **Port broker** (`00` §9.5): allocate/release from range `43100–43999`, persist.
- **Process supervisor** (`00` §9.6): spawn into a per-lane **process group**;
  terminate the group on stop; no orphans.
- **Reconciler** (`00` §9.2): on app launch, reconcile persisted lanes vs actual
  worktrees/processes/ports; surface orphans in Diagnostics; never auto-destroy.
- **Cleanup** (`00` §8.7 of source / retention): worktree kept 7 days default,
  artifacts 30 days, preference/summary data indefinitely; cleanup is delayed and
  uses `worktree remove` + `prune`, never `rm -rf` of tracked work.
- **Kill switch** (`00` §10): per-lane stop + global `stop-all` terminate process
  groups, mark `killed`, keep worktrees, never touch main.

## Ordered Slices

- [ ] P03-S01 — Hidden project root + `Worktrees/`, `Logs/`, `Artifacts/` per lane; lane record persistence in GRDB.
- [ ] P03-S02 — Branch naming + `GitClient` worktree add/remove/prune.
- [ ] P03-S03 — Port broker (allocate/probe/persist/release).
- [ ] P03-S04 — Process supervisor: spawn a fixture process into a process group, stream stdout/stderr to lane logs, clean stop with no orphan.
- [ ] P03-S05 — Lane state transitions wired to Core's state machine; emit `lane.*` events to the event bus.
- [ ] P03-S06 — Reconciler on launch (worktree/process/port reconciliation, Diagnostics list for orphans).
- [ ] P03-S07 — Cleanup with retention windows; global + per-lane kill switch.
- [ ] P03-S08 — Diagnostics for failed worktree creation (clear, actionable messages).

## Works Test

```text
Create three lanes from one enrolled repo. Verify:
- three worktrees exist outside the active repo, on three branches off the same base commit;
- the active repo working tree is byte-for-byte unchanged (git status clean/identical);
- a fixture process in each lane streams events and stops with zero orphan processes;
- stop-all marks all three "killed" and leaves the worktrees intact;
- after relaunch, the Reconciler restores/transitions lane state correctly.
```

## Exit Gates

- [ ] Works Test passes; **core invariant verified** (active dir untouched).
- [ ] No orphan processes after stop (assert via process-group check).
- [ ] Reconciler recovers cleanly from a forced quit mid-lane.
- [ ] MAC-3, MAC-8, MAC-13 satisfied.
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 04. Promote any lifecycle/recovery truths into `00` §9.
