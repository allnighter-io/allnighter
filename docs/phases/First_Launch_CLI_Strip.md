# First-Launch CLI Strip (Home Marketing Chips)

Status: **OPEN — ready for implementation**
Owner: AllnighterMac (`HomeMarketingEmptyState`) + `AppSetupModel.setupCards`
Created: 2026-08-10
Updated: 2026-08-10 (Sonnet review — one slice, one readiness owner, never-scanned suppress)
Origin: Founder report — first open showed an “infinite” row of CLI-looking
pills (repeated vendor glyphs). Desired: only recognized CLIs; green = ready,
yellow = action needed; tap opens that CLI’s setup. **Not capacity.**

Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`

Related (do not conflate):
- **First CLI Detection CODE RED:** [`First_CLI_Detection_And_Setup_Code_Red.md`](First_CLI_Detection_And_Setup_Code_Red.md)
  — tally / detect / Find-my-team. This packet is the **chip row under that CTA only**.
- Setup paint reference (label/glyph only): `UseFromCLIView` shortName chips
- Vocabulary: `docs/workflows/Product_Vocabulary.md` (Source / Bench — not Capacity)
- **Not this packet:** capacity strip, quota meters, ProbeFreshness redesign

Phases are ephemeral. Closeout: archive under `docs/archive/phases/`; code SSOT.

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

Current state:
  HomeMarketingEmptyState.benchChips renders appModel.composeBench — one pill
  per enabled *model* (~28 defaultOn). Same DriverBrandGlyph repeats; feels
  infinite. Dot is binary green/gray from isSmokeReady only. No tap → setup.
  Find-my-team (`showsFindTeamFrame`) already sits above the chips; chips still
  render underneath on virgin hosts.
```

Non-goals:

- Capacity strip, quota %, warm pool, serve refresh
- Changing `composeBench` for the RoutingComposer model picker
- A third readiness taxonomy or new Mac-only enum
- iOS companion UI
- Sort-order experiments; new shared abstraction beyond reusing `setupCards` + `StatusDot`

---

## Bug (grain)

| Layer | Wrong today | Right |
| --- | --- | --- |
| Data | `composeBench` = enabled **models** | `AppSetupModel.setupCards` — one card per headless CLI |
| Paint | Model name + driver slug | CLI `shortName` / setup card name + `DriverBrandGlyph` |
| Color | green vs gray only | `StatusDot` via the fold table below |
| Action | none | every chip → `openCLISetup(focus:)` |
| Never-scanned | chips always show | **suppress chips** while `showsFindTeamFrame` |

Mechanism: `composeBench` maps enabled models; marketing empty state treats that
as a CLI strip. Not a spawn leak.

---

## Product bar

1. **Recognized CLIs only** — one chip per setup card (headless), never per model.
2. **No gray wall under Find-my-team** — when `showsFindTeamFrame` is true, hide
   the chip row. The CTA is the honest never-scanned statement.
3. **Colors from setup cards** — fold `SetupCardState` → green / amber / gray
   (table below). Call `StatusDot`; do not hand-roll a fourth palette.
4. **Every chip taps** — including green → `openCLISetup(focus: driverId)`.
5. **Short row** — single `HStack`, no wrap. Once ≥1 card is `.ready`, omit
   `.notInstalled` so the row stays a bench, not an install catalog.
6. **Not capacity** — never paint these dots from capacity meters.

Follow-up only (not this packet): sort order (needs-action first vs ready-first).

---

## Truth owner + color fold

| Concern | Owner |
| --- | --- |
| Which sources | `AppSetupModel.setupCards(...)` |
| Ready / attention / muted | `SetupCardModel.state` (`SetupCardState`) |
| Dot paint | Existing `StatusDot(color:halo:)` |
| Navigation | Existing `RootView.openCLISetup(focus:)` |
| Presentation | `HomeMarketingEmptyState` only |

**Do not** use `UseFromCLIView.chipState` for readiness — it ignores `.parked`
(would paint parked as amber). Use it only as a paint/layout reference for
shortName + glyph.

### `SetupCardState` → chip dot

| Dot | States |
| --- | --- |
| Green (`StatusDot` ready) | `.ready` |
| Amber (`StatusDot` attention) | `.needsLogin`, `.needsPath`, `.probeFailed`, `.rateLimited`, `.installedNotProbed`, `.detecting`, `.reprobing`, `.queued`, `.waiting` |
| Gray (`StatusDot` dormant) | `.notInstalled`, `.notChecked`, `.parked` |

---

## Implementation sketch (non-binding)

1. Stop feeding marketing chips from `composeBench`.
2. Source chips from `setupCards` (headless). Leave `composeBench` for the composer.
3. If `showsFindTeamFrame` { omit chip row }.
4. If any card `.ready` { omit `.notInstalled` from the row }.
5. Map state with the fold table → `StatusDot`. Single row, no wrap.
6. `Button` / tap → `openCLISetup(focus: driverId)` for every chip.

---

## Slice

| ID | Slice | Works Test |
| --- | --- | --- |
| FLCS-S01 | Replace marketing chip row | **Grain:** empty-thread home shows ≤ one chip per headless setup card; no model fan-out / repeated vendor wall. **Never-scanned:** when Find-my-team shows, chip row is absent. **Color:** fixture covers green / amber / gray per fold table (include `.parked` → gray, `.needsLogin` → amber). **Tap:** any chip opens CLI setup focused on that driver. **Layout:** single row, no wrap; with ≥1 ready, `.notInstalled` omitted. |

CLI surface: none new. Teaching: FCS owns detect/bootstrap.

---

## Landmines

- Do not “fix” duplicates by deduping models inside `composeBench` — wrong owner.
- Do not wire capacity colors (neutral/amber/red) into these dots.
- Do not block on Probe Freshness or FCS redesign — use current `setupCards`.
- Do not copy `UseFromCLIView.chipState` for parked/rate-limit truth.
- Do not leave a full notChecked wall under Find-my-team after the grain fix.

---

## Closeout

When FLCS-S01 lands:

1. Confirm `HomeMarketingEmptyState` does not iterate `composeBench` for CLI chips.
2. Archive this packet under `docs/archive/phases/`.
3. Leave capacity and FCS packets untouched unless a tiny shared helper was
   extracted (name it in closeout).
