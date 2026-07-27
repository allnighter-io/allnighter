# Team Artifact — Brief

Standing surface brief for the private HTML team-run reading finish.
**Not a phase packet.** Layout and interaction law lives here; code is SSOT.

**Tier:** C (reading surface; does not start/kill runs)
**Visual authority:** `docs/design-system/production.md` + design tokens
**Behavioral / code SSOT:** `ArtifactProjector` · `ArtifactWriter` · `ArtifactCLI`
**Closed build record:** `docs/archive/phases/Team_Run_Receipt.md`
**Design seat / board capture:** `docs/operations/Design_Lane.md` +
`DesignBoardCapture` · `SkillCatalog.design_board_writer`

Dogfood / mockup references (non-authoritative): `mockups/`, `dogfood/`.

---

## What it is

Private-by-default local HTML after a team run: **CEO memo + evidence**.
CLI noun: `artifact`. Floor remains the Mac deep reader; this is the third
surface for reading finish (not live dispatch).

## Out of scope

Floor SwiftUI, thread cockpit tiles, growth/share scorecard, Buzz, attestation.

---

## Founder lock — Memo + evidence (2026-07-26)

1. **Artifact = CEO memo + evidence**, not memo-only with fake chip expand.
2. **Chips** = elevator `seat.summary` only (no expand). Click → `#seat-…`
   Evidence.
3. **Evidence** = full worker craft, clearly labeled per seat.
4. **Design boards:** mockups are the **hero** under the header (not buried in
   Evidence). Grid: mobile stack; desktop 1 / 2 / 3 cols; 4 → 2×2; 5+ → 3/row.
   **Click image → full-size lightbox** (not Evidence). Seat chips / caption
   “Evidence” → `#seat-…`.
5. Kill legacy first-line scrape; missing `seat` fence → blank chip line.
6. Show all Lead recommendations (no hide-to-3 density lie).

## Founder lock — K3 memo-page chrome (2026-07-26)

Dogfood run `99FEB349` (Visual System Designer / K3). Implemented in
`ArtifactProjector` (no extra Design round required for the artifact itself):

1. Sticky top bar — crescent + Allnighter · Team artifact left; Ready/Partial
   right.
2. Full-bleed void; content page ~1280 max (not a floating 680 card in empty
   space).
3. Width rule — Design board + The team = full content width; title / Asked /
   what-changed / call prose = ~680 reading measure.
4. Decision as H1 under the bar; fewer section titles (Design board,
   Recommendations, Next, The team, Evidence).
5. Team chips — role-first, Lead tag, one-liner, model + status **word** +
   duration; Lead listed first in one “The team” section.
6. Full Evidence retained below (not dropped).
7. Footer — crescent + honesty left; reproduce + run id quiet right.
8. Design Lead skill = Spec-style closeout: verify files on disk, name tiles by
   visible labels (never Option A/B theater), emit an **incorporate list** —
   owned by `SkillCatalog.design_board_writer`, not by this brief’s chrome.
9. Favicon — always emit a self-contained brand mark (`data:image/svg+xml;base64`,
   `docs/design-system/assets/allnighter-icon.svg`). Never a repo-relative
   `href` (that only works for in-tree mockups).
