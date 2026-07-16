# relay-launch — layout-watcher verdict

Fixtures: relay-launch
Command: bash scripts/gui_proof.sh relay-launch

## VERDICT: PASS

Fix under review: prior render had the sticky footer (helper text "PM ↔ dev,
unattended…" + orange Start button) landing flush against — and appearing to
cross the border of — the DEV SEAT model-picker list, slicing its last
visible row in half. Root cause: the outer form ScrollView's own fixed
640pt-frame viewport ran out of room and clipped mid-row, with zero visual
gap before the footer. Fixed by moving the footer to `.safeAreaInset(edge:
.bottom)` (guarantees the scroll content can never render underneath it,
structurally, regardless of content length), raising the sheet height
640→680pt (fits comfortably inside the app's real 720pt minHeight / the
1100x720 GUI-proof capture window), tightening section spacing, and trimming
each seat-list box's bounded height (168→152pt) so both PM SEAT and DEV SEAT
render in full on first open.

Sidebar and background pane are properly dimmed by the scrim, nothing broken
there — all expected background elements behind the modal. No overlap,
clipping, or z-order issues outside the modal.

P1 — broken (blocks): none

P2 — advisory:
- Both the PM SEAT and DEV SEAT bounded lists still clip their last row's
  subtitle text (e.g. "OpenCode" under the final "GLM 5.2" entry) at the
  list's bottom edge, but this is now rendered as an intentional
  fade-to-transparent gradient rather than a hard cut — reads clearly as a
  "scroll for more" cue in both lists. Resolved from the prior P2 (which had
  no such cue).
- No scrollbar/indicator beyond the fade is visible in a static screenshot,
  so it's not confirmable from this capture alone that the fade reliably
  communicates scrollability at all list lengths (e.g. a 5th/6th model) —
  worth a quick check with a longer model list, not a defect in what's shown.

One-line summary: the footer fix worked — clear visible gap and divider
between the DEV SEAT box and the sticky footer/Start button, no overlap or
crossing border, and both list fades now read as deliberate scroll cues
instead of ugly clips.
