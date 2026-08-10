# First-Launch CLI Strip (Home Marketing Chips)

Status: **OPEN — ready for implementation**
Owner: AllnighterMac (`HomeMarketingEmptyState`) + shared setup truth
  (`AppSetupModel` / `CLISetupGrouping` / `openCLISetup`)
Created: 2026-08-10
Origin: Founder report — first open of the Mac app showed an “infinite” row of
CLI-looking pills (repeated vendor glyphs). Desired: only recognized CLIs;
green = ready, yellow = action needed; tap opens that CLI’s setup fix.

Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`

Related (do not conflate):
- **First CLI Detection CODE RED:** [`First_CLI_Detection_And_Setup_Code_Red.md`](First_CLI_Detection_And_Setup_Code_Red.md)
  — shared bench tally / detect / never `0/catalog` unscanned. This packet is
  the **home empty-state chip row only**.
- Setup surfaces: `docs/phases/setup/README.md`, `SetupViews.swift`,
  `ReadinessView.swift`, `UseFromCLIView.swift` (correct CLI grain already)
- Vocabulary: `docs/workflows/Product_Vocabulary.md` (Source / Bench — not
  Capacity)
- **Not this packet:** capacity strip, `CapacityStripView`, quota meters,
  ProbeFreshness gating of capacity — readiness color here is **setup/probe
  status**, never capacity headroom

Phases are ephemeral. Closeout: promote any keepable GUI law into
`docs/gui/` or setup docs if needed; code stays SSOT; archive this packet.

---

## Founder intake

```text
Founder intent:
  First-launch Mac empty state shows a wall of CLI-looking pills. It should
  ONLY show recognized CLIs. Dot color: green if ready, yellow if action is
  needed. Clicking a chip should one-click open that CLI’s setup page to fix
  it. This has nothing to do with capacity.

Product value:
  Cold open proves “you already pay for the team” as a short, honest CLI bench
  — not a model roster — with a direct path to fix anything amber.

Trusted workflow slice:
  open Mac app (no threads) → see one pill per recognized headless CLI →
  green/amber/gray matches setup truth → tap amber/gray → CLI setup focused
  on that source → fix → return; pill updates.

Current state:
  HomeMarketingEmptyState.benchChips renders appModel.composeBench — one pill
  per enabled *model* (~28 defaultOn). Same DriverBrandGlyph repeats; feels
  infinite. Dot is binary green/gray from isSmokeReady only. No tap → setup.
```

Non-goals:

- Capacity strip, quota %, warm pool, serve refresh
- Changing `composeBench` semantics for the RoutingComposer model picker
- Inventing a third readiness taxonomy (reuse setup’s ready / attention / absent)
- Showing every catalog model or “ghost” seats as the default row
- iOS companion UI

---

## Bug (grain)

| Layer | Wrong today | Right |
| --- | --- | --- |
| Data | `composeBench` = enabled **models** | Registry **headless CLIs** (one per `driverId` / source) |
| Paint | Capsule with model name + driver slug | CLI label + brand glyph (match Use-from-CLI / setup grain) |
| Color | green vs gray only | green ready / amber needs attention / gray absent or unchecked |
| Action | none | tap → `openCLISetup(focus:)` for that driver |

Likely mechanism (not a spawn leak): `AppModel.composeBench` maps
`models.filter(\.enabled)`; `HomeMarketingEmptyState` treats that list as a
CLI strip. Correct grain already exists in `UseFromCLIView` (filter
`registry` `kind == .headlessCLI`) and `AppSetupModel.setupCards`.

---

## Product bar

1. **Recognized CLIs only** — one chip per headless source the product knows
   (Claude Code, Codex, Cursor Agent, Gemini, OpenCode, …). No model fan-out.
2. **Colors match setup** — same truth as `CLIStatusRow` / Use-from-CLI chips:
   - green → smoke-ready (and not parked / not cooling)
   - amber → installed but needs attention (login, probe fail, rate-limited, …)
   - gray → absent, never checked, parked, or dormant
3. **Click to fix** — amber and gray chips navigate to CLI setup focused on that
   source. Green may open the same focus for detail or stay inert; prefer
   consistent tap → focus so the row is one interaction language.
4. **Not capacity** — do not paint these dots from capacity meters or confuse
   “ready seat” with “has quota left.”

Optional polish (same packet if cheap; else follow-up):

- Cap / single row; do not wrap into a wall
- Sort: needs-action first on virgin launch, else ready-first
- Hide not-installed by default once at least one CLI is ready (founder taste)

---

## Truth owners

| Concern | Owner |
| --- | --- |
| Which sources appear | Driver/registry headless CLI set (same as setup cards) |
| Ready / attention / absent | `ToolProbeRecord` / `AppSetupModel` setup card state — **not** `composeBench.ready` alone |
| Navigation | Existing `RootView.openCLISetup(focus:)` (health popover already uses it) |
| Presentation | `HomeMarketingEmptyState` only for this strip |

Do not invent parallel JSON or a Mac-only readiness enum. Reuse setup grouping.

---

## Implementation sketch (non-binding)

1. Stop feeding marketing chips from `composeBench`.
2. Project chips from setup cards / registry headless CLIs (same path as
   `UseFromCLIView` chip readiness).
3. Map state → `ALPalette.green500` / amber accent / gray (`ink450` / textFaint)
   consistent with `StatusDot` / Use-from-CLI.
4. Wrap chip in `Button` → `openCLISetup(focus: driverId)`.
5. Leave `composeBench` for the composer model lane unchanged.

---

## Slices

| ID | Slice | Works Test |
| --- | --- | --- |
| FLCS-S01 | Chip source = headless CLIs only | Virgin / empty-thread home shows ≤ one pill per registry headless CLI; no repeated vendor wall from defaultOn models |
| FLCS-S02 | Colors = setup triad | Fixture: ready → green; needs login / probe fail → amber; absent/unchecked → gray. Screenshot or ViewInspector assert |
| FLCS-S03 | Tap → setup focus | Click chip opens CLI setup with that driver focused (same as health popover path) |

CLI surface: none new — this is Mac presentation of existing setup/detect truth.
Teaching: no new `alln` command; FCS packet owns detect/bootstrap teaching.

---

## Out of scope / landmines

- **Do not** “fix” duplicates by deduping models in `composeBench` for the
  composer — wrong owner; marketing strip must change grain.
- **Do not** wire capacity colors (neutral/amber/red) into these dots.
- **Do not** block on Probe Freshness redesign — use current setup card state;
  unscanned host stays gray / Find-my-team CTA (FCS), not fake green.

---

## Closeout

When FLCS-S01…S03 land:

1. Confirm `HomeMarketingEmptyState` no longer iterates `composeBench` for CLI
   appearance.
2. Archive this packet under `docs/archive/phases/`.
3. Leave capacity and FCS packets untouched unless a shared helper was extracted
   (name it in closeout).
