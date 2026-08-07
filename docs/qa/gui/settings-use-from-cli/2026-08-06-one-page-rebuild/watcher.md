# Layout-watcher verdict — settings-use-from-cli · one-page-rebuild

Date: 2026-08-06
Fixture: `settings-use-from-cli`
Render: `native.png`
Mockup reference: `docs/design-system/explorations/use-from-your-cli/proposal.html`
Watcher: `.claude/agents/layout-watcher.md` (separate agent — did not write the code)

## VERDICT: PASS

**P1 — broken (blocks): none**

## P2 — advisory

1. **Above-the-fold depth.** "Teach all CLIs" (y≈648–706) and the first host row
   (ends y≈870) land comfortably inside the 700–900px fold. But the Cursor row
   (y≈870–995), Codex row (y≈995–1090) and the terminal footer note
   (y≈1090–1160) sit past the 900px guideline; the card's bottom border lands at
   y≈1172. Nothing is clipped and nothing requires scrolling in a 1496px
   capture, but in the mockup the whole card closes at ~50% of the pane rather
   than ~78%.

2. **Root cause of (1).** The CLI chip row wraps to two lines (6 + 3) where the
   mockup had a single row of 9, because the render uses the driver registry's
   long `displayName`s — "Codex / ChatGPT", "Cursor Agent", "Grok Build CLI",
   "Kimi Code CLI" — against the mockup's "Codex", "Cursor", "Grok", "Kimi".
   The extra wrapped row pushes everything below it down ~60–70px.

3. **Host row height rhythm is uneven.** Rows measure ~133px (Claude, one line),
   ~125px (Cursor, whose "Taught · up to date" pill wraps to two lines) and
   ~95px (Codex). The pill wrap expands the row cleanly with no overlap or
   clipping, but the dividers are unevenly spaced so the card does not read as a
   uniform grid.

4. **Pill column is not a fixed-width column.** "Out of date" and "Taught · up
   to date" share left and roughly right edges, but the dashed "Manual" pill
   starts further left and is narrower, so the pill column has no clean vertical
   edge. The name column and trailing actions (Update / Remove / Copy block) ARE
   cleanly aligned.

5. **Green status dot in the global top bar** (RGB ≈138,202,146, right of the
   "Models" label) violates the three-colour law (neutral / amber / red, no
   green). It is global app chrome, pre-existing and outside this rebuild, but
   visible in every capture of this pane. Tracked, not fixed here.

6. **No competing amber primary** — "Teach all CLIs" is the only solid amber
   button; Update / Remove / Copy block are text links and "5/8 ready" is a
   status badge. Noted as a pass.

## Missing captures

- No capture at a shorter laptop window height to confirm whether the Cursor /
  Codex rows and footer note require scrolling in practice.
- No hover/focus state on host rows or chips.

## Disposition

Sealed on PASS. The founder's stated requirement — the "Teach all CLIs" action
reachable without scrolling — is met.

P2 (1)+(2) are carried as a **named follow-up, not a waiver**: shortening the
chip labels is the fix, but doing it honestly means adding a short display name
to the driver manifest (Core SSOT) rather than string-munging suffixes off
vendor names in the view, which would be the view inventing product naming.
That is a Core change and does not belong inside this GUI slice.

P2 (3)+(4) are cosmetic grid tightening on the same card and ride along with any
follow-up.

P2 (5) is a pre-existing violation in global chrome and needs its own fix.
