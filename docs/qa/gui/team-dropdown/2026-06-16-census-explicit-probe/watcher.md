# Team dropdown — census + explicit-probe footer (sealed)

Surface: Team dropdown ("Your bench" popover) + footer actions
Fixture: `team-open-mixed` (6 models, mixed health, dropdown deep-linked open)
Command: `bash scripts/gui_proof.sh team-open-mixed`
Render: `native.png`
Bound views: AllnighterTokens.swift, RootView.swift, TeamControlView.swift (see proof.manifest)

Change under review:
- H5: honest pill status dot + reachable primary "Check tools" probe trigger.
- C4: secondary "Find the rest with <agent>" census trigger (shown once an agent
  is ready) with progress label + result summary line.

## VERDICT: PASS

Disinterested layout-watcher (separate agent, protocol from
`.claude/agents/layout-watcher.md`) on the current `native.png`.

P1 — broken (blocks): none

P2 — advisory:
- The bottom "ChatGPT 5.5" row is partially cut at the popover's lower edge —
  reads as intended scroll-overflow, not broken layout. Non-blocking.

Missing captures:
- Scrolled state of the model list (the list scrolls; only the top is shown).

One-line summary: The "Your bench" popover is correctly attached below the title
bar with header, mixed-status rows (green dots, "Not signed in"/"Probe failed" +
Repair), and all three footer buttons (Check tools, Find the rest, Manage team)
fully visible and aligned.
