# layout-watcher verdict — Home rail, all row states (repaired)

Reviewed 2026-08-15 against **11 captures rendered fresh this session** at
current HEAD, after two rounds of repair. This supersedes the earlier
`home-surfaces` seal, which deliberately covered only the 5 fixtures that
rendered real content.

## VERDICT: PASS — all 11 fixtures, zero P1

Now including the six that previously proved nothing.

## Round 1 — the fixtures rendered nothing

`home-rail`, `-th2`, `-unr`, `-loops-attention`, `home-thread-states`,
`home-with-threads` showed "No conversations" under every project while their
seeders staged pinned/draft/running/replied/unread rows. Clean PNGs of an empty
surface — which reads as coverage and is therefore worse than no proof.

Two causes, both fixed:
- Seeders never called `store.bindProject`, so `projectSections()` dropped every
  seeded thread. The presenter's filter was left alone — hiding unbound threads
  is correct product behavior; the seeding was what was wrong.
- `RootView` never seeded `ProjectsViewModel`, so the rail fell back to the
  developer's real disk projects. A proof that differs per machine is not proof.
  All six now show `halo-app` / `websitemd.studio` / `FareWellMarket` on any
  machine.

## Round 2 — repairing them exposed two real defects

Neither was reachable while the fixtures rendered nothing.

**P1 — unread was invisible on a running thread.** `Running + unread` and
`Running — no unread` rendered pixel-identical dots at `RGB(129,155,247)`, same
size, same position. Unread renders amber elsewhere in the same list, so running
state silently overwrote it. A user with a running thread carrying unread worker
replies saw no unread signal and would miss the reply.

Fixed by composing an amber ring around the blue fill when
`running && ordinaryUnread`. `ThreadDisplayState`'s precedence was deliberately
NOT changed — running staying primary is intentional and
`testRunningWinsOverEverything` still passes (5/5). The unread fact was never
lost; `ThreadRailRowState.railAttention` already carried it, and the dot renderer
simply never read it. Accessibility labels added ("Running" vs "Running,
unread") where none existed.

Verified by pixel sampling rather than by eye:

| Row | Pixels | Box | Colors |
| --- | --- | --- | --- |
| Running + unread | 268 | 18×18 | blue ×140 **+ amber ×60** |
| Running — no unread | 164 | 14×14 | blue only |
| Selected unread | 164 | 14×14 | amber only |

**P1 — the 4-state fixture rendered only 3 states.** No row read as the fourth
state. Diagnosis was seeding, not treatment: `.pending` already had a correct
distinct dot in the row component; nothing ever staged it.
`seedFixtureThreadStates` now arms a real `PendingItem` through `PendingStore` —
the same production path `HomeView.refreshArmedPending` reads — rather than
faking a row. Four states now render distinctly (blue running, amber replied,
dashed-ring draft, neutral pending) and the title bar correctly shows
"1 pending".

## Per-fixture

| Fixture | Verdict |
| --- | --- |
| home-rail | PASS — pinned section, per-project groups, ellipsis truncation |
| home-rail-th2 | PASS |
| home-rail-unr | PASS — running+unread now distinguishable from running |
| home-rail-loops-attention | PASS — "1 loop needs you" badge; three distinct loop treatments |
| home-thread-states | PASS — all four states render distinctly |
| home-with-threads | PASS |
| home-trial-chip / home-keep-going-chip | PASS — bench chip row wraps 6+3, fully labeled |
| keep-going-sheet / command-palette | PASS — scrim, centering, z-order clean |
| projects-rail | PASS |

## P2 — advisory, not blocking

The "stopped" loop row in `-loops-attention` has no leading indicator at all,
which reads closer to "indicator failed to load" than to a deliberate stopped
state, though dimmed text does differentiate it. Left deliberately rather than
guessing at a third dot treatment inside a P1 pass.

## Standing lesson

A fixture that produces a clean PNG while never painting the surface it is named
for is a defect, not a pass — and it actively conceals whatever bugs live in that
surface. These six hid two P1s, one of them a real user-facing data-loss-of-signal
bug, for as long as they rendered nothing.

Reviewers: `.claude/agents/layout-watcher.md` (Sonnet) across two rounds; the
round-2 reviewer failed the surface on pixel evidence after the repair. PM
independently re-verified both P1 fixes by sampling pixels.
