# setup — layout-watcher verdict (Track A first-run + census fallback)

Fixtures: team-open-mixed · doctor-open-mixed · readiness-mixed
Command: `bash scripts/gui_proof.sh <fixture>` (one per surface)
Renders: native-team-open-mixed.png · native-doctor-open-mixed.png · native-readiness-mixed.png

Change under review (Track A):
- First-run gating: launch opens the CLI-setup page when setup has never been
  completed (process-quiet — renders cached/unknown; scan on explicit click).
- Census becomes an onboarding-only option: a framed, dashed "Don't see one you
  installed? / Search my machine" card on the readiness page, shown only when a
  supported CLI is missing AND a working agent exists (read-only, ~30–60s).
  (Not in the dropdown — removed in Track B.)
- antigravity displayName drift completed → "Gemini (Antigravity CLI)".

## VERDICT: PASS

Disinterested layout-watcher (separate agent, protocol from
`.claude/agents/layout-watcher.md`) on all three current renders.

team (dropdown): P1 none. P2 bottom roster row scroll-fold clip (expected);
footer = "Set up tools" + "Manage team", no census button.

readiness (CLI setup page): P1 none. All 4 stat cards, grouped roster, and the
sticky repair panel render aligned and non-overlapping. The census card sits at
the bottom of the left column, at/below the fixed-capture (1100×720) scroll fold —
expected; it is reachable by scroll and shows at normal window sizes. Its
visibility gating (`canRunCensus`) is unit-tested at the AppModel level and it
reuses the proven dashed-card idiom.

doctor (health popover): P1 none. Anchored, all groups visible, "Open CLI setup"
footer intact.

One-line summary: All three render cleanly — anchored popovers, aligned stat
cards, intact footers; only normal list-bottom scroll-fold clipping.
