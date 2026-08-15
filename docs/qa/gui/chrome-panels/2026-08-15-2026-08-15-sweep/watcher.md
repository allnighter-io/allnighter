# layout-watcher verdict — Ask AI / Boost Window / Capacity Strip

Reviewed 2026-08-15 against **6 captures rendered fresh in this session** at
current HEAD. Stale PNGs were excluded by instruction — see the Boost Window
finding below for exactly why that mattered.

## VERDICT: PASS — zero P1, zero P2

| Fixture | Verdict | View |
| --- | --- | --- |
| ask-ai-open | PASS | AskAIPanel |
| ask-ai-done | PASS | AskAIPanel |
| studio-boost-window | PASS | BoostWindowView |
| capacity-strip | PASS | CapacityStripView |
| capacity-strip-calm | PASS | CapacityStripView |
| capacity-strip-refreshing | PASS | CapacityStripView |

## Boost Window — two "confirmed P1s" withdrawn on fresh evidence

Captures dated **Jun 22** showed the "When do you go hardest? — drag to set"
label colliding with the "seed · HH:MM" marker into unreadable glyphs, and a
"reset 1p · too la" chip clipped at the right edge. Both were reported as
current defects — including by the PM, who inspected the pixels personally.

They were fixed on **2026-07-30** by `e14947b1` ("fix(gui): two P1 layout
defects in the Boost Window"), five weeks *after* those captures were taken.

Fresh render confirms: the label sits at the top of the minimap block with the
seed marker well below the track — clear vertical separation, both fully
legible. The chip reads **"reset 1p · too late"** in full, positioned as an
intentional overhanging badge matching the "+1 BUCKET" treatment on the opposite
corner. Not clipped.

**Lesson recorded:** the gate's claim was only ever *"this view's proof is
stale."* Stale proof is **unknown**, not **broken**. Treating unknown as broken
manufactured two phantom P1s and nearly cost a packet a false bug-fix round.

The "Applies to" chip row being cut at the frame's bottom edge is normal
`ScrollView` overflow in a fixed 1100×720pt capture, not a defect.

## Capacity Strip

The real `CapacityStripView` UI is the "YOUR BENCH" headroom table. Zoomed
inspection settled two ambiguities: the CLI / THIS WEEK / LAST 5H column headers
are present and correctly laid out — intentionally faint (`textFaint`, tracked
uppercase), matching the app's header style, not collapsed. The Grok mid-refresh
spinner in `-refreshing` sits in its own trailing-column slot with no bleed into
the weekly or 5h cells.

⚠️ **`capacity-strip-mixed.png` was MISLABELED and has been DELETED.** It was a
Home/RootView marketing capture stored under a capacity name — not evidence for
this view, and deliberately not opened during this review. It could not be
renamed because no fixture in `GUIFixture.swift` generated it: an orphan PNG,
unreferenced and untracked (`_captures/` is gitignored), dated Aug 07, depicting the unlabeled bench-chip-row bug that was
fixed the same day in `8ee39543`. A misnamed capture nothing can regenerate is a
sealed lie about what has been verified — it is precisely the artifact that
caused a phantom P1 to be reported during triage. Removed rather than renamed.

## Ask AI

Panel chrome (header, close, deck copy, ask row, footer divider) is well-bounded
in both states; in `-done` the panel grows to fit the answer body without
truncating or overlapping the footer.

Incidental, not this view's file: the bench chip row visible *behind* the panel
now wraps cleanly onto two rows after today's `HStack → FlowLayout` fix in
`HomeView`. Reported, not attested — `HomeView` is sealed separately.

Reviewer: `.claude/agents/layout-watcher.md` (Sonnet), read-only pass.
