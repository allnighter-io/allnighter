# floor — team-reply-reader — layout-watcher verdict

Fixture: floor-reader
Command: bash scripts/gui_proof.sh floor-reader

## VERDICT: PASS

The G-T3 Factory Floor reader — the screen a user lands on after a Send-to-team
run completes. Left cast rail (Lead + 5 workers, brand glyphs, clean one-line
previews) + reading-first right column: collapsible prompt bar, reader header
(role + SYNTHESIS tag + Rendered/Raw toggle + copy), the Lead's reply rendered
through AllnighterMarkdown (headings, bold, italic, bullets, blockquote), and the
Lead-only "TAKE THE NEXT MOVE" block (amber primary "Save to Pending" + secondary
"Send to another team"). Markdown is IDE/Cursor-grade — no raw `**`/`##` markers in
the body.

P1 — broken (blocks): none

P2 — advisory (both addressed before seal):
- Cast-rail previews previously leaked raw `##`/`*` markdown → now stripped via
  `previewLine()` (plain first-content line, max 60 chars). Confirmed clean in the
  re-render ("12 public posts, 48 hours, still clim…", "The line writes itself", …).
- Blockquote ("Confidence: …") previously had no visible accent stripe → theme
  blockquote bar bumped to a 3px `ALColor.accent` rounded bar. Confirmed visible.

Remaining advisory (not blocking, future polish):
- Worker-selected state (non-Lead, no NextMove block) and Raw-toggle-active state
  are not captured by this fixture — single-state proof. Add sibling fixtures if a
  regression is suspected.
