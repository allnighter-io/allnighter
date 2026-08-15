# layout-watcher verdict — Home / Root / WorkspaceMode

Reviewed 2026-08-15 against **11 captures rendered fresh in this session** at
current HEAD. Sealed against **only the 5 that rendered real content** — see the
blocked-fixtures finding below, which is the most important thing on this page.

## VERDICT: PASS on the 5 sealed fixtures — zero P1

| Fixture | Verdict |
| --- | --- |
| home-trial-chip | PASS |
| home-keep-going-chip | PASS |
| keep-going-sheet | PASS |
| command-palette | PASS |
| projects-rail | PASS |

## The fix this round was for

`HomeMarketingEmptyState.benchChips` used an `HStack` whose own comment read
*"Single row — no wrap"*. At ~8 ready CLIs, SwiftUI compressed every chip to fit:
names clipped mid-word into indistinguishable stubs, and in the worst variant an
overflow row rendered ten chips with **no label at all**.

Confirmed fixed. Nine ready CLIs (Antigravity, Claude, Codex, Cursor, Grok,
Kimi, Muse, OpenCode, Qwen) wrap cleanly across two rows (6 + 3), each chip fully
readable with icon, name and ready dot, centered, no overflow past the 760pt
content column.

## Overlay states — the historical P1 class

`keep-going-sheet` and `command-palette`: correct scrim, centered overlay, full
content visible, no clipping, no detachment, no z-order error. The failure mode
that broke the Team dropdown does not recur.

## ⚠️ SIX FIXTURES PROVE NOTHING — not sealed

`home-rail`, `home-rail-th2`, `home-rail-unr`, `home-rail-loops-attention`,
`home-thread-states`, `home-with-threads` render **no seeded content at all** —
the sidebar shows "No conversations" under every project, zero thread rows,
despite each seeder deliberately staging pinned/draft/running/replied/unread rows
to exercise exactly that surface (CR4e grouped rail, TH2 triage, UNR unread
matrix, 4-state rows).

Root cause, traced through `ThreadsPresenter.swift` / `ThreadRailRowState.swift`:
`projectSections()` drops any thread whose `projectId` does not match a loaded
project — the code comment says so outright. The seed functions in
`ThreadsFixtureSeeder.swift` (`seedFixtureRail`, `seedFixtureRailControls`,
`seedFixtureUnreadMatrix`, `seedFixtureThreadStates`, `seedFixtureThreads`)
never call `store.bindProject`, so their threads are silently excluded. And
because `RootView` never seeds `ProjectsViewModel` for these fixtures, it falls
back to real disk state — which is why the sidebar shows this machine's actual
projects instead of deterministic fixture data.

`home-rail-loops-attention` is a partial exception: its threads *are* bound to
`prj_halo` and that project loads, yet rows still do not render. Unresolved.

**Why this matters more than any layout nit:** these six fixtures pass the
harness and produce clean PNGs while never painting the surface under test. They
are decorative. Sealing HomeView against them would have recorded
`watcher: PASS` over code no one has ever seen rendered — the same shape of lie
as a stale capture, arriving through a different door.

`projects-rail` proves the row-rendering code itself is sound: pinned row,
per-project groups, ellipsis-truncated titles, "1 more" overflow, right-aligned
timestamps, correct dot colors. So this is a **fixture content gap, not a SwiftUI
defect**. Follow-up belongs on `ThreadsFixtureSeeder.swift`.

**Consequence for this seal:** `HomeView` is proven for the marketing hero, the
bench table and the populated project-grouped rail. It is **NOT** proven for the
TH2 triage, UNR unread-matrix, or draft/running/replied row treatments — those
code paths have never been rendered.

## Minor, non-blocking

Search boxes in several captures show garbled partial text ("he be", "od on",
"ild t", "BUil"). Content, not layout — most likely stray keystrokes captured on
a shared machine during rendering rather than a code defect. Flagged for
awareness; it does suggest captures taken while the machine is in use can pick up
input.

## Not sealed here

`AllnighterMacApp.swift` — no view body of its own; waived separately with a
content-bound reason (see `docs/qa/gui/WAIVERS.manifest`).

Reviewer: `.claude/agents/layout-watcher.md` (Sonnet), read-only pass.
