# Judgment Workflow — Allnighter (iOS) · the floor manager

The judgment workflow on iPhone — **glance and decide**, not full editing. The
phone creates the habit; the Mac (`ui_kits/judgment/`) creates the power. Same
RB specs (`uploads/RB0–RB5`), same tokens and components.

`index.html` mounts `JIOSApp` inside the iOS device frame. Tab bar: **Inbox** ·
**Compose**. Tapping a run opens its detail (currently the Review board).

## Views (complete · 10)
Inbox · Compose + Call Plan · Live run · Judge Analysis · Review Board ·
Final Spec + Implement · Dispatch · Return Review + Outcome · Routing · Scorecards.
See them all at once in `gallery.html`.
- **Inbox / "Needs you"** — runs awaiting a decision (final spec ready,
  blocker on the board, a return to judge) + what's running, with a progress bar.
- **Compose + Call Plan** — one prompt, a workflow preset (synthesis / light /
  full), and the live **Call Plan** (fresh-call estimate, reuse, "$0 marginal").
- **Review Board** — run detail with a stage pip-strip, blocker/concerns count,
  and lens cards (verdict chip + top concerns). Advisory; never overwrites the plan.

Next iOS batches: Final Spec + Implement · Dispatch status · Return Review +
Outcome · Routing · Live run · Judge Analysis · Scorecards.

## Files
- `index.html` — mounts `JIOSApp`.
- `screens.jsx` — `InboxScreen`, `ComposeScreen`, `ReviewScreen` (+ tab shell, exported to window).
- `screens2.jsx` — Final spec, Dispatch (with live transcript), Return review + outcome; the extended `JIOSApp` (run-detail flow review → final → dispatch → return).
- `screens3.jsx` — Routing, Live run, Judge analysis, Scorecards; the final `JIOSApp` (full detail flow incl. routing/analysis/scorecards/liverun).
- `gallery.html` — all 10 screens at a glance, no tapping.

All run content is representative sample data.
