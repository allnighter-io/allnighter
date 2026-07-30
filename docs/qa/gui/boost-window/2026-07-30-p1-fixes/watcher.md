# boost-window — layout-watcher verdict (two P1 fixes)

Fixture: `studio-boost-window`
Command: `bash scripts/gui_proof.sh studio-boost-window`

Watcher was a separate agent that did not write the code. **Three passes were
required.** This surface was built after the visual-proof baseline and had never
been visually verified — the defects below shipped invisibly past build and tests.

## VERDICT: PASS — P1: none, P2: none

## Pass 1 — FAIL (two P1s on a never-verified surface)

> **P1:** the "reset 1p · too late" status pill (top-right of the "Same 5 hours"
> timeline card) is sliced by the card's own right/corner edge — the word "late"
> is cut off mid-letter.
>
> **P1:** overlapping/illegible text on the drag slider — the "seed · 5:30 AM"
> label renders directly on top of the "When do you go hardest? — drag to set"
> header. Both strings become unreadable where they intersect.

## Pass 2 — FAIL (the first fix was wrong)

> P1 #1 (reset chip clipped): **RESOLVED.**
> P1 #2 (seed label overlapping header): **STILL PRESENT** — "seed" overlaps the
> "g" of "drag" and "5:30 AM" overlaps "to set".

Cause of the failed fix: enlarging the container does not recentre the content —
**`GeometryReader` top-aligns its child**, so the ZStack kept its natural 28pt
height at the origin and a negative offset still escaped upward into the header.

## Pass 3 — PASS

Label moved **below** the track instead of above it.

> Known issue #1 (reset pill clipped): **RESOLVED** — pill sits fully inside the
> card with visible margin on all sides.
>
> Known issue #2 (seed label overlapping header): **RESOLVED** — label now sits
> below the slider track with a clean gap from the header above and from the
> caption box below; no new collision introduced.
>
> **VERDICT: PASS** — P1: none. P2: none.

## Note

Moving a label out of one collision into another is not a fix, so pass 3
explicitly re-checked the space *below* the label as well as above. Both defects
confirmed gone with no regression.
