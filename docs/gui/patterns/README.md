# SwiftUI Patterns — enforced building blocks

**Status:** Canonical / Always True
**Scope:** SwiftUI building blocks that have ONE blessed implementation in this
app. When a pattern lives here, you use the named helper. You do not re-solve it
inline, and you do not hand-roll a variant "just this once." Re-solving these is
exactly how the same GUI bug comes back three times.

These exist because we kept re-breaking the same things. Each page names the
**bug it kills**, the **one right way**, and the **banned ways**.

## Pages

- [`Anchored_Popups.md`](Anchored_Popups.md) — menus / pickers / dropdowns that
  attach to a button. Use `alPopover`. Never hand-position.

## How a pattern earns a page

A surface bug repeats → we find the idiomatic SwiftUI/AppKit primitive that the
OS already gets right → we wrap it in one named helper → we write the page →
reviewers reject any code that re-implements it by hand.

## The honesty rule (applies to all of these)

A screenshot the agent cannot actually see is **not** verification. A text
paraphrase of a PNG can say "popover is anchored above the button" while the
real pixels show it floating in the corner. So:

- The agent may **render** and **describe** proof captures. It may **not** sign
  off visual correctness (placement, spacing, color) it did not truly see.
- Visual sign-off on anchoring / spacing / color is the **human's** call.
- The agent's job is to remove the failure mode at the source — use the blessed
  primitive — so "did I position it right?" stops being a question that needs an
  eyeball at all.
