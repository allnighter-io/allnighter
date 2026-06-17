# home — layout-watcher verdict (CR4a re-seal under ScreenCaptureKit capture)

Fixtures: home-with-threads · thread-with-turns · thread-empty · command-palette ·
compose-base · compose-target-chat · compose-target-fanout
Command: `bash scripts/gui_proof.sh <fixture>`

Re-seal: the proof harness moved to ScreenCaptureKit (the supported macOS 14
capture; `CGWindowListCreateImage` was deprecated and returned nil even with
Screen Recording granted). Captures are now full-desktop composites including
native popovers. This re-binds the CR4a + harness views to their current content
so the wall is green; no product layout changed.

## VERDICT: PASS

Disinterested layout-watcher on all seven current renders (judging the app
window/popover, ignoring desktop + menu bar).

home-with-threads: P1 none · P2 none — rail (New work order, search, filters,
conversation rows) + "Start a work order" + docked composer.
thread-with-turns: P1 none · P2 none — header + "You" turn + docked composer.
thread-empty: P1 none · P2 none.
command-palette: P1 none · P2 overlay composites over the window (expected SCK layering).
compose-base: P1 none · P2 none.
compose-target-chat / compose-target-fanout: P1 none · P2 popover layers over the
composer chips (expected anchored-overlay), nothing clipped or detached.

One-line summary: All windows + popovers on-screen, anchored, no clipping/overlap
of visible controls — PASS.
