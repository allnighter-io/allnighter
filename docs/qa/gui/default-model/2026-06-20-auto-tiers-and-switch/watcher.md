# default-model — layout-watcher verdict

Fixtures: studio-default-model home-with-threads
Command: bash scripts/gui_proof.sh studio-default-model
         bash scripts/gui_proof.sh home-with-threads

## studio-default-model — VERDICT: PASS

P1 — broken (blocks): none
P2 — advisory:
- "DEFAULT MODEL PER TIER" continues below the fold (natural scroll, not a clip).
- Left nav lane labels (CODE/DESIGN/COPY/SIGNAL) low-contrast (pre-existing).
- Auto card: gap between the resolved-model pill and the right-aligned "Pick the tier"
  segmented control reads loose — minor spacing.

Structurally sound and faithful to the handoff (Auto card, tier segmented control,
substitutions toggle, three roster columns with multi-tier members, Unassigned shelf).

## home-with-threads (Inbox/Teams switch) — VERDICT: PASS

P1 — broken (blocks): none
P2 — advisory:
- Active "Inbox" reads visibly brighter than inactive "Teams"; both icons+labels
  unclipped, side by side, centered. No box/border/fill/container anywhere (flat, as
  intended; hover box not exercised in a static capture).
- Faint left-lean: moon->Inbox gap slightly wider than Inbox->Teams — nit.

The flat workspace switch is clean — no leftover selected box.
