# Layout-watcher verdict — capacity-strip · aligned-pool-lines

Date: 2026-08-06
Fixtures: `capacity-strip`, `capacity-strip-refreshing`
Renders: `native-capacity-strip.png`, `native-capacity-strip-refreshing.png`
Watcher: `.claude/agents/layout-watcher.md` (separate agent — did not write the change)

## VERDICT: PASS

**P1 — broken (blocks): none**

**P2 — advisory:**
- None of visual note; the merged line shape renders with pixel-consistent
  columns — bar left edge, bar right edge, percent right-alignment, and
  reset-clock left-alignment all share the same x across Codex, Cursor, Grok,
  Kimi, and both Antigravity pool lines (verified via guide-line overlay, not
  eyeballing).
- Antigravity's two stacked pool lines (Gemini / Claude·GPT) sit tighter
  together than the inter-row gap between distinct CLI rows — expected for two
  lines inside one row unit, not a defect, just noting the rhythm difference.

**Missing captures: none** — both requested states (idle, refreshing) were
provided and reviewed.

## Summary

The bench table's four-column line shape (label / bar / percent / reset) is
cleanly aligned row to row, including Antigravity's two-line pool stack; the
refreshing state only swaps the "Nm ago ↻" text for a spinner in place, no
layout shift.
