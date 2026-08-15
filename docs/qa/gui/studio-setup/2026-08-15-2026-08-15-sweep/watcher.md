# layout-watcher verdict — Setup / Studio / Settings sweep

Reviewed 2026-08-15 against **17 captures rendered fresh in this session** at
current HEAD. Stale PNGs on disk were explicitly excluded: two "confirmed P1s"
were withdrawn earlier today because the evidence was a June screenshot of code
fixed in July.

## VERDICT: PASS — zero P1 across all 17 fixtures

| Fixture | Verdict | Views exercised |
| --- | --- | --- |
| doctor-open-mixed | PASS | SetupViews (`BenchHealthPopover`) |
| readiness-cold / -mixed / -cursor-ready / -cursor-trust / -cursor-keychain / -cursor-not-checked / -muse-needs-login | PASS ×7 | ReadinessView |
| studio-clis | PASS (P2) | TeamStudioView shell + ReadinessView embedded |
| settings-use-from-cli | PASS | TeamStudioView shell + UseFromCLIView |
| studio-default-model | PASS (P2) | TeamStudioView shell + DefaultModelView |
| team-open-ready / team-open-mixed | PASS ×2 | TeamControlView (`BenchDropdownPanel`) |
| studio-teams-code / studio-team-editor / studio-worker-editor / settings-plan | PASS ×4, **shell only** | TeamStudioView shell |

## The state that mattered most

`BenchDropdownPanel` is the component that previously shipped a P1 by clipping
and detaching from its anchor. Fresh render: flush-attached below its title-bar
anchor with no gap, fully on-screen, right edge inside the window with margin,
header / row-list / footer all present and unclipped. At 20 available models the
row list caps its height and scrolls internally — coded behavior, not overflow.
**The historical failure mode does not reproduce.** Independently re-verified by
the PM against the same capture.

## Visually-inert change confirmed, not assumed

`UseFromCLIView.swift` was edited today (a `private` `FlowLayout` widened to
internal so `HomeView` could reuse it rather than grow a second wrapping
implementation). Both CLI chip rows wrap cleanly, no clipping or overlap, dot
indicators aligned. The edit is confirmed inert rather than presumed so.

## P2 — advisory, non-blocking

- `studio-clis`: embedded Ready-row chips truncate to "Opus 4…", "Sonnet…",
  "Gemini…" at the narrower Studio-shell width. Ellipsis present; not a hard clip.
- `studio-default-model`: "Opus 4.6 (Antigravity)" wraps mid-word
  ("Antigravit" / "y)") in the Balanced/Economy tier columns. Ugly; nothing lost.

## Scope of this attestation

`TeamStudioView` is proven for **the shell only** — nav rail and team-list
column. The detail panes inside `studio-teams-code`, `studio-team-editor`,
`studio-worker-editor` and `settings-plan` belong to `TeamEditorView.swift` and
`PlanSettingsView.swift`. Those files are **not** bound by this seal and remain
unproven. A shell PASS must never be read as proof of the pane inside it.

## Out of scope — content, not layout

`readiness-cursor-ready` and `readiness-cursor-trust` render pixel-identical
panels despite being distinct named states. Layout is clean in both; whether the
fixtures actually select different states is a data question for the content
owner, not this gate.

Reviewer: `.claude/agents/layout-watcher.md` (Sonnet), read-only pass.
