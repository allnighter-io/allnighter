# Layout-watcher verdict — settings-use-from-cli · ladder-green-ready

Date: 2026-08-06
Fixture: `settings-use-from-cli`
Render: `native.png`
Watcher: `.claude/agents/layout-watcher.md` (separate agent)

## VERDICT: PASS

**P1 — broken (blocks): none**

**P2 — advisory:**

- The amber "needs attention" chip state is not exercised by any of the 9 chips
  in this capture (all green-ready or grey-absent), so that third colour's
  layout is unverified. Low risk — amber renders correctly elsewhere on the pane
  (the "Out of date" pill, the "Teach all CLIs" button).
- Card 1's "Teach all CLIs" and card 2's "Copy the block" are a similar pixel
  size; their weight differentiation rests entirely on fill (solid amber vs dark
  bordered) rather than any size cue. Reads fine at normal viewing size; worth a
  glance if amber is ever desaturated for accessibility.

**Missing captures:** no state showing an amber "needs attention" CLI chip.

## Summary

Host rows are clean single-line with the pills aligned in one column — "Ready"
replaces the old two-line "Taught · up to date" wrap as intended. The two cards
read as a clear one-click vs paste hierarchy. Nothing is clipped, overlapping,
or off-screen. "Teach all CLIs" remains the only solid amber primary and stays
above the fold.

## Note on the previous packet's green finding — WITHDRAWN

`2026-08-06-one-page-rebuild` recorded a P2 claiming a green status dot in the
global top bar violated a three-colour law. **That finding was wrong and is
withdrawn.** The "three colours only, neutral/amber/red, no green" rule is
written on `CapacityStripView` and scoped to the capacity strip, where green
would imply healthy *quota*. It is not an app-wide ban: `ALColor.statusDone`
(green500) is the design system's token for "done / healthy" and the CLIs panel
already uses it for ready drivers.

The error originated in the implementation brief, which over-generalised the
strip's law into "no green anywhere" — so the pane shipped amber-or-grey chips
and a grey "up to date" pill that read as disabled. This revision restores green
for ready state on both the chips and the host pill, matching the CLIs panel.

Two surfaces describing the same driver must not disagree about its colour.

## Prior P2s resolved by this revision

- Pill column had no clean vertical edge / uneven row rhythm — both were caused
  by "Taught · up to date" wrapping to two lines. "Ready" is one word; resolved.
- "3 hosts found on this Mac" under a 9-CLI chip row read as "we support 3 of
  your 9" — replaced by the explicit ladder line and a second card covering the
  other 7.

## Carried forward

The chip row still wraps to two lines because the render uses the driver
registry's long `displayName`s ("Codex / ChatGPT", "Grok Build CLI"). Fixing it
honestly needs a short display name on the driver manifest (Core SSOT) rather
than the view stripping suffixes. Still open, still not this slice's job.
