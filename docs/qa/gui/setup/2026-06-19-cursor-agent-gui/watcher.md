# setup — layout-watcher verdict (CUR-S03 Cursor Agent GUI)

Fixtures: readiness-cursor-ready · readiness-cursor-keychain · readiness-cursor-trust ·
readiness-cursor-not-checked
Command: `bash scripts/gui_proof.sh <fixture>`
Renders: native-readiness-cursor-*.png

Slice: CUR-S03 — Mac GUI presentation for Cursor Agent (brand asset, setup cards,
`headlessTrust` disclosure, bench roster from Core truth).

## VERDICT: PASS

Disinterested layout-watcher on all four fixture renders.

- **readiness-cursor-ready:** P1 none — Cursor cube glyph, Composer 2.5 on-bench ON,
  Fast OFF, amber `--trust` callout readable, repair panel aligned.
- **readiness-cursor-keychain:** P1 none — needs sign-in state + trust disclosure visible.
  P2 repair subtitle truncated at bottom fold (scroll overflow).
- **readiness-cursor-trust:** P1 none — trust callout prominent on ready Cursor card.
- **readiness-cursor-not-checked:** P1 none — Cursor in "Not checked yet" group with
  trust disclosure. P2 "Last proof" section at bottom fold.

One-line summary: Cursor Agent is visible, branded, and honestly disclosed across setup
fixtures with no P1 layout defects.

## GUI-launched live smoke (Works Test)

- Launched `Allnighter.app` via `open` (Launch Services, no fixture seeding).
- Opened CLI setup and triggered **Re-check all** via accessibility automation.
- Persisted `cli_setup.json` shows `cursor_agent` **ready** (`2026.06.16-20-30-07-a07d3ac`);
  no `SecItemCopyMatching` / Keychain auth failure in the record.
- Capture: `native-cursor-live-gui-smoke.png`

**Live GUI smoke: PASS** (not waived).
