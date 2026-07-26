# Pilot long jobs — CEO decision brief

Status: **Needs founder sign-off** before build
Updated: 2026-07-26
Owner: Allnighter product (CLI / Pilot)

---

## The ask (one paragraph)

Approve a small fix so that when Allnighter runs a long job overnight (deploys,
database repair, multi-step ship), **killing a “waiting” window does not look
like the job failed.** Today a monitoring window can die while the real work
keeps going — and the AI assistant often concludes “failed” and starts again,
which wastes money and can duplicate work. We want durable job status to be the
source of truth, and waiting windows to be disposable.

**Approve?** Yes / No

---

## What went wrong (plain story)

We ran a real Pilot loop on a production-shaped deploy (websitemd.studio). The
worker did the hard, slow work correctly — including fixing a real database
auth bug and landing a one-command ship path. Mid-flight, the **waiting
window** the assistant was using got stopped by the host environment (Cursor).

Nothing about the actual job had failed. The job was still running and had
already made good commits. The assistant only knew “the wait was killed,” which
reads as failure unless something tells it otherwise.

We recovered by checking job status again. That recovery depended on a human
memory note in another repo — not on Allnighter teaching the right habit. Next
time, without that note, the likely mistake is: declare failure and start a
second job while the first is still holding the write lock.

Separately: “start the job in the background” is **broken on a clean machine**.
It only appeared to work in one repo because an old leftover shortcut file was
sitting in that folder. On a normal checkout, background start fails. That is a
real bug, not an inconvenience.

---

## What we are recommending

Four small product changes, in this order:

1. **Fix background start** so it works on every clean checkout, from any
   folder. (Stops the silent “only works if leftover junk is present” failure.)

2. **Teach the AI the right habit immediately:** for long jobs, start work, then
   **check status** on a timer — do not treat a dead waiting window as a dead
   job. Teaching first cuts harm before any fancy polish.

3. **When a waiting window is killed, print a clear goodbye:** “Job still
   running — check status; do not restart.” Right now death looks like an empty
   kill with nothing useful on screen. That single message prevents the worst
   wrong story.

4. **Make status answers clearer for long jobs:** is the owner process still
   alive? When was the last real progress? How long should I wait before asking
   again? Commit counts are optional color, not proof of life (many good rounds
   never commit).

We are **not** asking for a new “deploy mode,” a second timeout system, or
auto-restarting waiters as if they owned the job.

---

## Why you should care

| If we do nothing | If we ship this |
| --- | --- |
| Long real work (deploy, migrate, ship) keeps succeeding underneath while the assistant often thinks it failed | Assistant treats status as truth; waiting windows can die without drama |
| Risk of **double work** under the same lock (wasted spend, messy repos) | Re-check status before any restart |
| Background start secretly broken except where leftover files mask it | Background start works on clean machines |
| Only “remember the quirk” people recover correctly | Product teaches the recovery |

This is trust infrastructure for overnight / unattended use. If Allnighter lies
about long jobs, founders will not leave it running.

---

## What we are explicitly not doing

- Not auto-restarting waiting windows as if they were the job
- Not inventing a special “deploy timeout” separate from normal time limits
- Not raising timeouts for every short chat just because deploys are long
- Not teaching “commits appeared ⇒ job is alive” (wrong for investigate / no-commit rounds)
- Not rebuilding Pilot or Relay from scratch

---

## Scope and cost (feel)

Small, bounded CLI / Pilot work. No Mac redesign. No iOS. No new cloud service.
No new billing or permissions.

Roughly: fix one broken start path, change teaching copy, make killed waiters
speak clearly, enrich status for long polls. Ship in four short slices; first
two alone already remove most of the damage.

---

## Success looks like

- You can start a long Pilot job in the background on a fresh machine and it
  actually starts.
- If the waiting window dies, the last thing on screen says the job is still
  running and how to check — not a blank “killed.”
- The assistant’s default instructions say: check status; do not restart while
  status says running.
- If the real job owner process dies mid-round, status says so clearly and tells
  the assistant to **inspect** before doing anything else (not blind retry).

---

## Decision

| Option | Meaning |
| --- | --- |
| **Approve** | Build the four slices above in order (fix start → teach → clear death message → richer status) |
| **Approve with cuts** | Say which slices to drop (recommend keeping 1–3; 4 can wait) |
| **Reject** | Leave current behavior; accept that long jobs will keep confusing assistants when wait windows die |

Founder sign-off: _______________  Date: _______________

---

## Appendix — for builders only (skip for sign-off)

Routing detail and slice IDs live in git history of this file’s earlier
revisions and in code SSOTs (`PilotCLI`, `RelayCoordinator`, archived
`Pilot_Relay` / `Pilot_DX`, idle-stall hotfix). Implementers: ship order
**S01 → S03 → S04 → S02**; SIGTERM/goodbye envelope leads the watch slice;
`waitHintSeconds` ~45s while running; commit count is supplementary; dead
**waiter** must not orphan the round; dead **owner** orphans once with inspect
nextAction. Do not expand scope past the CEO brief above without a new
sign-off.
