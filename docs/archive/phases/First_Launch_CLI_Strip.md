# First-Launch CLI Strip (Home Marketing Chips)

Status: **CLOSED — FLCS-S01 shipped 2026-08-10**
Owner: AllnighterMac (`HomeMarketingEmptyState`, `HomeMarketingCLIStrip`) +
  `AppSetupModel.setupCards`
Created: 2026-08-10
Updated: 2026-08-10 (implemented + archived)
Origin: Founder report — first open showed an “infinite” row of CLI-looking
pills (repeated vendor glyphs). Desired: only recognized CLIs; green = ready,
yellow = action needed; tap opens that CLI’s setup. **Not capacity.**

Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`

Related (do not conflate):
- **First CLI Detection CODE RED:** [`../phases/First_CLI_Detection_And_Setup_Code_Red.md`](../phases/First_CLI_Detection_And_Setup_Code_Red.md)
  — tally / detect / Find-my-team. This packet was the **chip row under that CTA only**.
- Setup paint reference (label/glyph only): `UseFromCLIView` shortName chips
- Vocabulary: `docs/workflows/Product_Vocabulary.md` (Source / Bench — not Capacity)
- **Not this packet:** capacity strip, quota meters, ProbeFreshness redesign

**Successor / code SSOT:** `HomeMarketingCLIStrip.swift`,
`HomeMarketingEmptyState` in `HomeView.swift`, `RootView.openCLISetup(focus:)`,
`AppSetupModel.setupCards`. Proof: `AllnighterMacTests/HomeMarketingCLIStripTests`
(5/5).

---

## Founder intake

```text
Founder intent:
  First-launch Mac empty state shows a wall of CLI-looking pills. It should
  ONLY show recognized CLIs. Dot color: green if ready, yellow if action is
  needed. Clicking a chip should one-click open that CLI’s setup page to fix
  it. This has nothing to do with capacity. Keep it simple and reliable.

Product value:
  Cold open proves “you already pay for the team” as a short, honest CLI bench
  — not a model roster — with a direct path to fix anything amber.

Trusted workflow slice:
  open Mac app (no threads) → if never scanned, Find-my-team CTA only (no gray
  chip wall) → after scan, one pill per recognized headless CLI → green/amber/
  gray from setup cards → any tap → CLI setup focused on that source → fix →
  return; pill updates.

Shipped state:
  HomeMarketingEmptyState no longer iterates composeBench. Chips come from
  setupCards via HomeMarketingCLIStrip.visibleCards; suppressed under
  showsFindTeamFrame; StatusDot fold; tap → openCLISetup.
```

Non-goals (held):

- Capacity strip, quota %, warm pool, serve refresh
- Changing `composeBench` for the RoutingComposer model picker
- A third readiness taxonomy or new Mac-only enum
- iOS companion UI
- Sort-order experiments

---

## Bug (grain) — fixed

| Layer | Was | Now |
| --- | --- | --- |
| Data | `composeBench` = enabled **models** | `AppSetupModel.setupCards` — one card per headless CLI |
| Paint | Model name + driver slug | CLI `shortName` + `DriverBrandGlyph` |
| Color | green vs gray only | `StatusDot` via fold table |
| Action | none | every chip → `openCLISetup(focus:)` |
| Never-scanned | chips always show | **suppress chips** while `showsFindTeamFrame` |

---

## Product bar (shipped)

1. Recognized CLIs only — one chip per setup card.
2. No gray wall under Find-my-team — row hidden when `showsFindTeamFrame`.
3. Colors from setup cards — fold below; `StatusDot`.
4. Every chip taps → `openCLISetup(focus:)`.
5. Short row — single `HStack`, no wrap; omit `.notInstalled` once ≥1 `.ready`.
6. Not capacity.

Follow-up only: sort order (needs-action first vs ready-first).

---

## `SetupCardState` → chip dot

| Dot | States |
| --- | --- |
| Green | `.ready` |
| Amber | `.needsLogin`, `.needsPath`, `.probeFailed`, `.rateLimited`, `.installedNotProbed`, `.detecting`, `.reprobing`, `.queued`, `.waiting` |
| Gray | `.notInstalled`, `.notChecked`, `.parked` |

---

## Slice

| ID | Status | Works Test |
| --- | --- | --- |
| FLCS-S01 | **Shipped** | `HomeMarketingCLIStripTests` — never-scanned suppress; omit notInstalled when ready; fold table; grain bounded by cards not models. Tap wired via `HomeView.onOpenCLISetup` → `RootView.openCLISetup`. |

---

## Closeout checklist

1. ~~Confirm `HomeMarketingEmptyState` does not iterate `composeBench` for CLI chips.~~
2. ~~Archive this packet under `docs/archive/phases/`.~~
3. Capacity and FCS packets untouched; helper is `HomeMarketingCLIStrip` only.
