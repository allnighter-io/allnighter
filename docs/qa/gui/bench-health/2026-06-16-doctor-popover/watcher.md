# Bench health popover — layout-watcher verdict

Surface: Bench health Doctor popover (Screen #3)
Fixture: `doctor-open-mixed` (1 ready, 2 need a step, 1 to add; popover deep-linked open)
Command: `bash scripts/gui_proof.sh doctor-open-mixed`
Render: `native.png`

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- "Gemini (Antigravity CLI)" title / via text wraps mid-word in the partially
  visible card at the scroll fold — cosmetic, not clipped.
- No scroll-overflow fade above the sticky footer when content continues below
  the fold (Antigravity + Grok sections). Scroll indicator is visible; follow-up
  polish only.

Missing captures:
- Scrolled-down state showing "Available to add" Grok card fully (content exists
  below fold per fixture seed; not required for layout PASS).

One-line summary: Popover hangs flush under the title bar, right-aligned with
13px inset; header, grouped roster, and footer stack correctly with scroll for
overflow.
