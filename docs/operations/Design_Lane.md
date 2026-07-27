# Design Lane

Standing law for Design team runs. **Not a phase packet.**

**Code SSOT:** `DesignBoardCapture`, CatalogRunCoordinator board stage,
`SkillCatalog` design / `design_board_writer` skills, `BuiltInTeams`
(`design_design` / Min / Max / Polish).
**Closed build record:** `docs/archive/phases/Design_Lane.md`.
**Sibling (verify-before-fixed):** `docs/gui/Visual_Proof_Gate.md`.
**Artifact hero tiles:** `docs/gui/surfaces/team-artifact/brief.md`.

---

## Law

1. **Receipt = screenshot of a built surface** — not diffusion, not prose-only
   “design.”
2. **Seat picks the cheapest honest build path** from the prompt + repo. Host
   provides a boring universal camera.
3. **Product default camera:** bounded HTML/SVG → WebKit capture (arbitrary
   repos).
4. **Allnighter Mac app special case:** when the design target is **this** app,
   use SwiftUI / GUI-proof render path — do **not** rebuild the app in HTML.
5. **No silent diffusion.** `imageGen` / Midjourney only on an explicit concept-
   art ask. Never the default for “Design team.”
6. **Path declaration (v1):** each design seat names `native | html | concept`
   plus the artifact path (board meta or Evidence).
7. **Board contract:** one desktop screenshot per design seat on
   `options[].imagePath`. Capture failure → seat failed (no fake fallback).
8. **Capability for UI design seats** = reason + build UI, **not** `imageGen`.

## Same camera, two jobs

| | Visual Proof Gate | Design lane |
| --- | --- | --- |
| Spine | Render → screenshot → eyes | Same |
| Job | **Verify** before “fixed” | **Propose** options for judgment |

## v1 scope

In: thin capture pipeline; bounded single-screen artifact; board stage as the
image contract; tiny seat brief + Evidence notes.

Out: forcing HTML for Allnighter SwiftUI; Figma sync; bundlers; SPA; silent
HTML→Midjourney fallback; revived `DesignCoordinator` / `DesignImageRunner` as
Design default.
