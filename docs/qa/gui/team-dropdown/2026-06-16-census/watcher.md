# Team dropdown — census + explicit-probe footer

Surface: Team dropdown ("Your bench" popover), footer actions
Fixture: `team-open-mixed` (6 models, mixed health, dropdown deep-linked open)
Command: `bash scripts/gui_proof.sh team-open-mixed`
Render: `native.png`

Change under review:
- H5 (Launch Authority): honest pill status dot + reachable primary
  **"Check tools"** probe trigger in the dropdown footer.
- C4 (census): a secondary **"Find the rest with <agent>"** discovery trigger,
  shown only once ≥1 tool is ready, with progress label + a result summary line.

## VERDICT: PASS

Disinterested layout-watcher run (separate agent, protocol from
`.claude/agents/layout-watcher.md`) on `native.png`.

P1 — broken (blocks): none

P2 — advisory:
- Last list row ("ChatGPT 5.5") is partially clipped at the bottom of the scroll
  area — contained within the panel, the expected scroll affordance, non-blocking.
- Slight crowding between the "Probe failed" badge / "Repair" link and the row
  text on the Gemini row — no overlap. (Same family as the pilot's truncation P2;
  follow-up polish, non-blocking.)

Missing captures: none

One-line summary: The "Your bench" popover renders cleanly — header, mixed-status
model list, and all three footer buttons (Check tools, Find the rest with
ChatGPT 5.5, Manage team) are visible, aligned, and on-screen.
