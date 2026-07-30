# loop — layout-watcher verdict (ATL-S03, Mac Loop entry)

Fixtures: `compose-loop`, `relay-launch-kickoff`
Command: `bash scripts/gui_proof.sh <fixture>`

Watcher was a separate agent that did not write the code. **Two passes were
required — the first FAILED.**

## VERDICT: PASS — P1: none

## Pass 1 — FAIL (recorded, not hidden)

`compose-loop` rendered the route picker **collapsed to a lone "Loop ⌄" pill**.
Model, Team and Loop were never simultaneously visible, so the slice's core claim
was unproven by its own fixture.

> P1: "The route picker does not show three tabs… not clipped mid-glyph, not
> overflowing the container, simply absent. This capture does not demonstrate the
> thing the slice is supposed to prove."

`relay-launch-kickoff` PASSED in that same run: Kickoff label, subtitle "Brief
the PM once — not a chat" and field fully visible with clean spacing before the
SPEC DOC section; primary button reads exactly **"Start loop"**, fully on-screen,
high contrast; the sheet dims its background correctly.

Cause: `GUIFixture.composeTargetOpen` only fired for `compose-target-*` ids, so
`compose-loop` captured a closed picker. Fixed in a follow-up commit.

## Pass 2 — PASS

`compose-loop`, re-rendered with the picker seeded open:

> All three tabs are fully visible, legible, and unclipped, with adequate
> right-side margin inside the popover border. Loop is clearly selected (filled
> pill, bold label). Popover fully within window bounds, not touching any window
> edge. Caret correctly anchors to the "Loop" trigger pill below.
>
> **VERDICT: PASS** — P1: none.

## P1 — broken (blocks)

none

## P2 — advisory (named, not blocking)

- Popover overlays composer placeholder text with no dimming scrim. Matches the
  pre-existing app-wide baseline confirmed independently on `team-open-mixed`;
  not new damage.
- Launch sheet PM SEAT list: 4th row partially cut by the scroll container edge —
  reads as a standard "more below" affordance.
- Launch sheet DEV SEAT list: sticky footer overlaps the last visible row.
  Intentional sticky-footer-over-scroll pattern; slightly abrupt. Polish
  candidate, tracked here rather than fixed in this slice.

## Note

The first FAIL is the gate working as designed. The app built clean and the
fixture looked plausible; only a rendered pixel check caught that the proof did
not actually show the thing being proved.
