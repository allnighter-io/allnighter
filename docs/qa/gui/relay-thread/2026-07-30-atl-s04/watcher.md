# relay-thread — layout-watcher verdict (ATL-S04, Status + Stop chrome)

Fixtures: `relay-thread-status`, `relay-thread-stop-confirm`, `relay-thread-stopped`
Command: `bash scripts/gui_proof.sh <fixture>`

Watcher was a separate agent that did not write the code. **Three passes were
required.** The first pass exposed a production bug, the second a capture-path bug.

## VERDICT: PASS — P1: none

## Pass 1 — FAIL (all three states) → a PRODUCTION bug

> None of the three captures show the Status pill, Stop button, or Stop
> confirmation dialog this slice is supposed to prove — the three PNGs are
> effectively the same generic thread view.

This was **not** a bad fixture. The state file was on disk and
`alln pair relay-status --relay fixture-relay-running --json` returned a full
envelope, so data and load path were both correct.

Root cause: `RelayThreadChrome.body` was a `Group` that rendered nothing while
`relayJSON` was nil — and the only thing that ever *populates* `relayJSON` is the
`.task` / `.onAppear` attached to that empty view. The chrome could not escape its
own initial state, so **Status and Stop would never have rendered for a real user
either.** Fixed by always rendering a non-empty container.

Build, 2544 passing tests, and code review were all clean while the feature was
simply absent on screen.

## Pass 2 — PASS ×2, FAIL ×1 → a CAPTURE-PATH bug

> Running state: **PASS** — blue "● Running" pill and a "Stop" button on one row
> in the thread header, legible, fully inside the window, no overlap.
>
> Stopped state: **PASS** — red "● Stopped" pill; no "Answer & resume" control of
> any kind, which is correct for a founder-stopped loop.
>
> Stop confirm: **FAIL** — still pixel-identical to the running view, no dialog.

Root cause of the remaining failure: `.confirmationDialog` presents as a **child
window**, which the in-process snapshot of the main window's content view
physically cannot see. Routed that fixture to the window-list composite capture
path used by the compose fixtures.

## Pass 3 — PASS

> YES — the Stop confirmation dialog is now actually visible, centered over the
> thread content ("Stop this loop?", body text, Cancel / Stop loop buttons).
>
> Body text legible: "This loop will not resume. Work in flight is abandoned."
> Buttons both fully visible, equal-sized, clear gap, no clipping.
> Z-order correct: dialog above content, background uniformly dimmed, no
> bleed-through.
>
> **VERDICT: PASS** — P1: none.

## P1 — broken (blocks)

none

## P2 — advisory (named, not blocking)

- A stray window sliver from an unrelated app appears above the macOS menu bar in
  the composite capture, outside the app window and not touching any app content.
  An artifact of the window-list capture path, not an app layout defect. Worth a
  sanity check on the capture script if it recurs.
- `relay-thread-stopped` shows leftover text in the sidebar search field from
  fixture setup. Stray state, not a layout defect.

## Note

Two of the three failures across these passes were things that build success,
a green test wall, and code inspection all missed — one of them a real user-facing
bug where the feature never rendered at all. This is the gate earning its keep.
