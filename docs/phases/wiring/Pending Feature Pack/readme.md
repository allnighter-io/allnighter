# Allnighter — Pending feature design pack

Native **macOS app** (dark-mode only — "amber phosphor on midnight"). Open either HTML file in a browser to view the mockups; they share the Allnighter design system in `styles.css` / `tokens/`.

## Contents

| File | What it shows |
|---|---|
| `Pending Queue - Redesign.html` | The new **Pending** screen — committed work per project, shown as a line. Frame 1 = chat-list draft treatment · Frame 2 = the full Pending screen (grouped by project, drag-to-reorder) · Frame 3 = the un-arm-on-edit behavior. |
| `Composer - Redesign.html` | The redesigned **shared composer** — read-only scope above, clean box, model+effort (or team · workers) target, and the conditional pending strip below. |

## Decisions baked in
- **Pending is a condition, not a destination.** The `pending` chip (top-right, by `5 ready`) appears only when count > 0; clicking it opens the full screen.
- **A queue only exists behind a running item** — every project group is headed by the one item currently running, with pending items chained beneath.
- **Color is earned.** Model = the live simple pill; the selected **effort** rides beside it as neutral level bars. Teams read `name · workers`. Amber appears only on the pending chip and the primary action.
- **Editing a pending order un-arms it** (Pending → Draft); re-submit re-arms it.
- **Reviewing an order reuses the composer** (open it in a modal that grows to a max height, then scrolls) — no bespoke review drawer.

## Open / build notes
- Keep the two HTML files alongside `styles.css` and the `tokens/` folder so styles resolve.
- Mac window chrome (traffic lights, top bar) is mocked in-page; in the real app it's native.
