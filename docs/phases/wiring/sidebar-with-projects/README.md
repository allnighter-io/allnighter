# Allnighter — Sidebar redesign · handoff

A shareable pack for the design + Swift build. Two files, both **self-contained** — open them in any browser, no internet or build step needed.

---

## 1. `Allnighter — Sidebar redesign (interactive).html`
The **live mockup**. Click around it:

- **Today / Proposed** — flip between the current dense sidebar and the new one (before/after).
- **Unread emphasis** — compare *Dot + text*, *Dot only*, *Text only*.
- **Pin / archive** — hover any row.
- **New chat** — hover a project (or the big amber button). **New project** — the folder-plus in the Projects header.
- Opening a thread clears its unread dot.

## 2. `Allnighter — Sidebar redesign — spec.html`
The **build spec**: the one rule (dot = unread), row anatomy, all states, behaviors, exact color/type/spacing tokens (with SwiftUI `Color(hex:)` values), and a SwiftUI `List` + swipe-actions starting point. Printable to PDF.

---

## The idea in one line
Allnighter runs **per project**, so the sidebar groups threads by project and collapses every row to one line — **status dot · title · time**. The dot now means exactly **one thing: unread**. Colored status (red/green) was theater we couldn’t trust, so it’s gone.

## What was removed from each row
Colored status dots · text status pill · worker avatar + stack · lane badge + filter chips.
**Kept:** title, one unread dot, time.

## Open question for the team
The unread dot is **amber** (the one brand accent — nothing else competes for color now). If it feels loud across many rows, a neutral-bright dot is a one-token swap. Easy to demo either way.
