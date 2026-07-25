# team-run-receipt — layout-watcher verdict

Fixtures: floor-reader thread-live-artifact studio-boost-window studio-default-model team-open-mixed
Command: `bash scripts/gui_proof.sh floor-reader` (and siblings above)

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- **studio-boost-window:** Slider label area shows slight text overlap ("drag to set" vs "started — drag to set") in the peak-hours control; readable but cramped.
- **floor-reader:** Long team-seat one-liners truncate with ellipsis in the left rail — expected at this width, not clipped off-screen.

## Per-fixture notes

### floor-reader
Factory Floor reader fully on-screen. Left team seat rail, center markdown synthesis, bottom "Ask Another Team" CTA all visible and aligned. No scrim/z-order issues. "Open artifact" affordance present in header.

### thread-live-artifact
Live `TEAM ARTIFACT · LIVE` panel renders inside the team-board turn: header, question, three seat rows with glyphs, duration badges, running pulse dots, and one-liner text. Card border and raised background intact; no collapse or overlap with composer.

### studio-boost-window
Boost settings sheet: hero timeline, toggle, tier cards, and footer "Applies to" row all on-screen. Layout holds at 1100×720 capture size.

### studio-default-model
Default model tiers (Flagship / Balanced / Fast) render as three columns with model rows, DEFAULT badges, and substitution toggle. No clipped headers or collapsed columns.

### team-open-mixed
Team dropdown hangs below title bar, fully on-screen. Mixed-health rows show ready dots and issue badges; "Your bench" header and "Manage team" footer present. Covers app shell title-bar Team control.
