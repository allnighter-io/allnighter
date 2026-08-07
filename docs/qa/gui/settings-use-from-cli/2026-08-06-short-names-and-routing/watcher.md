# Layout-watcher verdict — settings-use-from-cli · short-names-and-routing

Date: 2026-08-06
Fixture: `settings-use-from-cli`
Render: `native.png`
Watcher: `.claude/agents/layout-watcher.md` (separate agent)

## VERDICT: PASS

**P1 — broken (blocks): none**

**P2 — advisory:**

- Card 1 ends at ~y970 of the 1496px capture rather than the ~y900 the brief
  guessed; card 2 ends ~y1347. Both fully visible — the 900px figure in the
  brief undershot the measured layout, not a defect.
- "You already pay for most of this bench." at the very bottom has its
  descenders clipped by the window edge. Expected: that heading is meant to be
  peeking at the fold as scroll affordance.
- Chip "Claude" vs host row "Claude Code" are separated by the whole card-1
  header, so the shorthand-vs-precise difference reads as fine on screen rather
  than as an inconsistency.

**Missing captures:** none.

## Summary

All 9 CLI chips sit on one line with even spacing. Both cards and their contents
are fully visible with no clipping or overlap. "Teach all CLIs" remains the sole
amber primary.

## Resolves the P2 carried since 2026-08-06-one-page-rebuild

The chip row wrapped because the render used the driver registry's long
`displayName`s. That was carried forward twice as a named follow-up rather than
fixed in the view, because the honest fix required a new field on the driver
manifest — the AgentOS SSOT — not the view stripping suffixes off vendor names.

`DriverManifest.shortDisplayName` (AgentOS `f249ff3`) now supplies it, with
`shortName` falling back to `displayName` on any manifest that lacks one. The
chip row is a single line and both cards moved up accordingly.
