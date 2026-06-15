# iOS Floor Manager — Allnighter (parked roadmap)

A high-fidelity recreation of the **iPhone floor manager** from the full
Allnighter roadmap (`uploads/README.md` — Milestone C/D, post-MVP). *"The iPhone
creates the habit; the Mac creates the power."* This is a **roadmap surface**,
not the MVP — built on the same tokens and components so it's ready when the
team gets here.

## Screens (tap the tab bar)
1. **Home** — the **Morning Pull** digest (agent-hours · drafts · landed),
   "Needs you" pending picks, what landed overnight (green-tier), and the global
   **Stop all workers** kill switch.
2. **Lanes** — **Active lanes**: each task's lane with worker, `StatusPill`, a
   progress bar, and a one-tap **Land · green tier** when it's ready. ("Lane" is
   the user-facing word; the worktree is hidden.)
3. **Race** — the wedge: one prompt → **three directions** as swipeable draft
   cards (preview · worker · summary). Tap **Pick this** → the **picker-as-prompt**
   sheet: your selection becomes the work order; add a note to steer it ("but
   make the header sticky") and tap **Implement this**. No copy-paste, no
   re-explaining.

## Files
- `index.html` — mounts `FloorApp` inside the iOS device frame.
- `screens.jsx` — `FloorApp` (tab shell) + Home / Lanes / Race + the pick sheet, and a blinking `LiveMarkMini`.
- `ios-frame.jsx` — the device bezel/status bar (starter component).

## Notes
- Composes the design-system components via `components/_preview.jsx`
  (`StatusPill`, `Badge`, `Icon`, `BrandIcon`). Mobile uses larger type and ≥44px
  touch targets — denser macOS sizes are not reused verbatim.
- All content is **representative sample data**. Model glyphs via Simple Icons
  (ChatGPT falls back to a Lucide mark).
