# `docs/gui/` — GUI Engineering Governance

How to **build** Allnighter's UI surfaces. This folder is governance, not visual
design and not build sequencing.

**Folder split (no overlap):**

- **Visual SSOT** → `docs/design-system/` (brand, voice, color, type, tokens,
  components, logo/icon, `production.md`).
- **GUI engineering governance** → here (`docs/gui/`).
- **What to build, and when** → `docs/mvp/` (active) and `docs/phases/` (roadmap).

Start at **[`GUI_Workflow.md`](GUI_Workflow.md)** — it routes UI work by risk
tier and links the rest.

## Contents

- `GUI_Workflow.md` — canonical router: tiers, non-negotiables, testing, briefs.
- `Visual_Proof_Gate.md` — render → layout-watcher → seal (standing GUI law).
- `0.GUI-Tech-Stack.md` — SwiftUI / macOS stack and where tokens enter the app.
- `1.GUI-Invariants.md` — the always-true UI rules.
- `2.GUI-Surface-Architecture.md` — the app's surfaces, mapped to the design-system UI kits.
- `patterns/` — enforced SwiftUI building blocks with ONE blessed implementation
  (e.g. anchored popups → `alPopover`). Re-solving these inline is rejected.
- `surfaces/` — per-surface briefs and field-ownership ledgers (template in `surfaces/README.md`).
