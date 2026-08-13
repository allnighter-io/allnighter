# CLI setup — row hit target — layout-watcher verdict

Surface: CLI setup list rows (`CLIStatusRow`)
Fixture: `readiness-muse-needs-login`
Command: `bash scripts/gui_proof.sh readiness-muse-needs-login`
Render: `native.png`

## VERDICT: PASS

P1 — broken (blocks): none

P2 — advisory:
- The last visible left-column row ("Grok Build CLI") is cropped at the bottom edge of the panel — expected scroll-truncation, not a layout defect.
- The Muse Code detail panel's On bench / Parked control has heavier visual weight than row chips. Minor proportion drift; not broken.

Missing captures:
- Scrolled-down state of the left-column list
- Hover/focus states on the detail-panel action buttons
- Deselected / no-selection state of the list

One-line summary: All visible CLI setup list rows render correctly — glyph, name, chips/status copy, and status dot intact; Muse Code amber ring and detail panel are properly layered; no clipping, overlap, or collapse found.
