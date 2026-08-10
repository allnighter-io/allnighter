# First CLI Detection & Setup — CODE RED

Status: **CODE RED — OPEN — v1 (founder dogfood 2026-08-10)**
Owner: AllnighterMac (`RootView`, `BenchHealthBadge`, `ReadinessView` / CLI setup) +
AllnighterEngine (`CLIDetector`, `AppModel` probe paths, `SetupStore`) +
AllnighterCore (`DriverManifest` setup / bins, `ToolProbeRecord`, `BenchReadiness`)
Created: 2026-08-10
Revised: 2026-08-10 (v1 — intake)
Origin: First launch of the Mac app on a new host shows amber **`0/9 ready`**,
grey dots on every bench glyph, and Cursor IDE seats in the hero while **zero**
CLI probes have run. The product promise dies before the first message.

Related (read before coding — do not relitigate closed TCC law):
- Live setup intent: `docs/phases/setup/00_First_Run_Setup_Experience.md`,
  `docs/phases/setup/01_CLI_Detection_Auth_And_Bench.md`, `docs/phases/setup/README.md`
- Launch Authority (process-quiet cold launch): archived
  `docs/archive/phases/Launch_Authority_TCC_Hotfix.md`
- Same-day TCC resurface: `docs/operations/debugger/2026-08-10-first-launch-tcc-popups-PACKET.md`
- Cursor Agent CLI (built): archived
  `docs/archive/phases/setup/Cursor_Agent_CLI_Support.md`
- Product vocabulary: `docs/workflows/Product_Vocabulary.md` (source / model / worker)

Phases are ephemeral. At closeout: promote chrome + first-scan law into setup
docs + AGENTS routing; code remains SSOT; archive this packet.

---

## 0. Code-red claim (one sentence)

**Opening Allnighter must either find the CLIs the user already paid for, or put
them one honest button away from each installed seat — never strand them on Home
with a fake-empty bench graded against the whole catalog.**

`0/9 ready` is not humility. It is a broken first proof of the product thesis.

---

## 1. What the founder saw (2026-08-10)

Verified against code + dogfood screenshot:

1. Title-bar `BenchHealthBadge` paints **`0/9 ready`** (amber / warning).
2. Home hero still offers **Auto / Composer 2.5 / Cursor Grok 4.5** labeled
   `cursor-agent`, while the glyph strip shows **grey** readiness dots.
3. Composer is live; empty-state / chrome imply a working team that is not seated.
4. User is **inside Cursor IDE** while coding — natural expectation: “at least
   Cursor should be ready.” That expectation is **false under today’s contract**
   (IDE ≠ `cursor_agent` CLI) and we do nothing to teach or fix it on first open.

### Truth owners for the bad number

| Symbol | Code | Meaning today |
| --- | --- | --- |
| **Y = 9** | `AppModel.totalToolCount` | Every bundled `headlessCLI` in the catalog (not parked) |
| **X = 0** | `AppModel.readyToolCount` | Drivers with **smoke-passed** probe records only |

The nine: Antigravity, Claude Code, Codex, Cursor Agent, Grok, Kimi, Muse,
OpenCode, Qwen. Cold launch calls `loadCachedSetupState()` only (process-quiet).
Empty `SetupStore` ⇒ X stays 0. Setup does **not** auto-open (founder: never
land in setup). Badge formula: `ready != total` ⇒ `"\(ready)/\(total) ready"`.

So the chrome grades the machine against **support catalog size**, using a
**never-scanned** numerator. That is the lie-prone layer.

---

## 2. Product law that already exists (and is being violated in UX)

From `00_First_Run_Setup_Experience.md` (still the experience SSOT for setup):

- Anti-spec: cold open with a **`0/N healthy` badge and no path forward**.
- Bar: launch → recognition of what I already have → one scan → working team.
- Header tally: **we support N, found M** (not “0 of catalog ready”).
- Honesty: ready only when smoke passed; never fake green.
- Non-trapping: user may leave setup with 0 ready; badge must stay honest and
  returnable.

From Launch Authority / 2026-08-10 TCC packet:

- Ordinary cold launch stays **process-quiet** (no silent full-bench spawn under
  Dock TCC identity).
- Explicit Setup / Re-check / Run / Enable may probe; one intentional TCC moment
  is acceptable.

**This packet does not repeal Launch Authority.** It resolves the collision:
process-quiet returning launches vs a **first-proof** that currently never runs.

---

## 3. Ideal outcome (what “10× better” means)

Within ~60s of first open on a Mac that already has ≥1 agent CLI installed and
signed in:

1. User understands **what we found** vs **what we support** (no catalog-as-grade).
2. Installed + signed-in seats flip to **ready** with real versions.
3. Missing agent CLIs (especially Cursor IDE without `agent` / `cursor-agent`)
   get a **one-screen install/login** — not a scavenger hunt.
4. Home only claims seats that are actually smoke-ready (or Auto that can resolve
   to one). Grey-dot theater over empty probe cache is forbidden.
5. Returning launches with a warm cache stay quiet; no TCC storm.

---

## 4. Two acceptable product shapes (founder may pick A, B, or A→B)

### Shape A — Zero-click first scan (ideal)

On **first open with empty / never-completed setup**, Allnighter runs one
**user-owned first scan** that feels automatic:

- Trigger is first-session intent, not every cold launch: empty `SetupStore`
  records **or** `setupCompletedAt == nil`, gated so it fires **once** until
  completed or explicitly deferred.
- UX: brief full-page or modal **“Finding your team…”** with live per-CLI
  progress (found → version → ready / needs login / not installed). Not a
  cinematic six-scene flow (already cut in setup lean rewrite).
- Probe authority: same as today’s explicit `runFullSetupProbe(userInitiated:
  true)` — interactive login-shell resolve allowed; TCC attributed to this
  moment; never hidden behind Home appear alone without framing.
- When the scan finishes: land on Home **or** stay on the results roster if any
  installed CLI still needs a step. Badge shows calm truth (`N ready` or
  `Scan CLIs`), never `0/9`.

**Hard constraint:** Shape A must still be *user-initiated* under Launch
Authority — the “button” may be “Continue” / first-window primary, or an
auto-presented first-run sheet whose primary action is the scan. Silent
`onAppear` full smoke without that frame is **out of bounds**.

### Shape B — One button per installed CLI (fallback / complement)

If auto-scan is blocked, deferred, or fails closed:

1. First meaningful surface is **CLI setup** (or a first-run sheet that *is*
   setup), not empty Home with marketing copy.
2. For each **found** CLI: one primary control — **Enable / Sign in / Re-check**
   — that completes that seat. No multi-page wizard.
3. For each **supported but not installed**: one install hint + docs link.
4. For **Cursor IDE present, Cursor Agent CLI absent**: a dedicated card —
   install `agent` / `cursor-agent`, `agent login`, then one **Re-check** —
   copy that never claims the IDE is the seat.
5. User can skip; chrome CTA remains **Find my team** until at least one seat is
   ready or setup is marked seen.

**Recommended ship order:** implement Shape B chrome + first-run routing **and**
a Shape A one-shot framed scan as the primary path (A with B as the recovery UI).

---

## 5. Cursor special case (must not be hand-waved)

| Fact | Implication |
| --- | --- |
| Seat id is `cursor_agent` | Bins: `agent`, `cursor-agent` (see manifest) |
| Smoke uses Composer 2.5 label | Ready requires smoke token, not IDE open |
| User often lives in Cursor IDE | First-run copy must say **Cursor Agent CLI** |
| IDE without CLI is common | Card: install + login + one re-check; never green from IDE presence |

Optional later (not v1 required): cheap **presence** disclosure
(`installedNotProbed`) after an explicit/framed resolve — still not “ready.”

---

## 6. Badge & Home honesty (non-negotiable slice)

### Forbidden

- `0/<catalogSize> ready` when probe cache is empty / never scanned.
- Hero model chips that imply runnable `cursor-agent` seats while the driver is
  `notChecked` / not smoke-ready.
- Green or “ready” language for unprobed drivers.

### Required

| State | Chrome pill (approx.) | Home |
| --- | --- | --- |
| Never scanned | **Find my team** / **Scan CLIs** (CTA, not a failing grade) | Do not pretend seats are seated; route to scan/setup |
| Scanned, some ready | **`N ready`** (or `N ready · M need a step`) | Only ready sources power Auto / chips |
| Scanned, none ready | **Set up CLIs** + reason | Setup forward, hopeful install list |
| All ready | **`N ready`** | Normal Home |

Catalog size (“we support 9”) lives on the **setup page**, not as the title-bar
denominator.

Truth owner for the three numbers: support count / found count / ready count —
one projector consumed by badge, setup header, and empty states.

---

## 7. Out of scope

- Capacity strip acquire / serve fork-bomb / remote relay (separate 2026-08-10
  packets). Do not re-open silent capacity waves to “fix” setup.
- New vendor drivers, pricing, iOS companion.
- Rebuilding the cut cinematic 6-scene onboarding.
- Inferring ready from vendor dashboards, Keychain, or IDE process lists.
- Repealing process-quiet for **returning** launches with a warm cache.

---

## 8. Slices (execution order)

| ID | Goal | Works Test (owner-visible) | Proof |
| --- | --- | --- | --- |
| **FCS-S00** | Packet + board routing; name badge SSOT + first-scan trigger | Doc + AGENTS/phases pointer | Doc review |
| **FCS-S01** | Badge / empty-state: never `0/catalog` on unscanned; CTA copy | Fixture: empty cache → pill ≠ `0/9 ready` | Mac unit + GUI fixture if chrome changes |
| **FCS-S02** | First-run framed scan (Shape A primary): one intentional probe wave | Empty cache first open → framed scan → real found/ready partition | AppModel + detector tests; founder TCC once |
| **FCS-S03** | Setup as recovery UI (Shape B): one primary action per found CLI; Cursor-without-CLI card | Found `claude` needs login → one Sign in; Cursor IDE w/o agent → install card | ReadinessView / setup tests + layout proof if GUI |
| **FCS-S04** | Home hero / compose bench: no ready-looking seats without smoke | Unprobed → no green runnable Cursor chips | ComposeBench / Home tests |
| **FCS-S05** | Teaching: help/bootstrap one-liner for first scan + Cursor Agent ≠ IDE | `alln help` / bootstrap mention | Teaching gate / help test |
| **FCS-S06** | Closeout: promote law into setup README + `00`/`01`; archive packet | Founder first-open dogfood PASS | check filter + founder note |

Do not start S02 silent `onAppear` smoke. S01 can ship alone and already removes
the worst lie.

---

## 9. Truth owner / lie-prone layer / missing proof

```text
Tier: T2 SSOT (readiness chrome + first-run routing) — T3 if probe authority regresses
Symptom: first open → 0/9 ready + grey bench; Cursor IDE not seated
Bug fingerprint: BenchHealthBadge totalToolCount catalog denom + empty SetupStore
  + process-quiet loadCachedSetupState + Home hero offering unprobed cursor-agent
Truth owner: SetupStore probe records + CLIDetector smoke; badge projector TBD
Lie-prone layer: BenchHealthBadge label; Home hero chips; “ready” without smoke
Missing proof: empty-cache chrome fixture; first-scan once-gate; Cursor-without-CLI card
Fix boundary: first-proof UX + honest counts; do not silent-spawn full bench on every launch
```

---

## 10. Founder decisions (ask if ambiguous mid-slice)

1. **Shape A trigger:** auto-present first-run sheet with primary **Find my
   team**, vs land on CLI setup page until first scan completes?
2. **Minimum to enter Home:** allow skip at 0 ready (current non-trapping law)
   vs soft-gate until ≥1 ready?
3. **Cursor without CLI:** in-app install instructions only, or also deep-link
   Cursor docs / `curl` install if Cursor publishes one?

Default if unanswered: **(1) framed sheet with one primary scan**, **(2) keep
non-trapping**, **(3) instructions + docs URL from manifest**.

---

## 11. Done when

- [ ] Unscanned first open never shows `0/<catalog> ready`.
- [ ] One framed first scan (or explicit setup landing) finds installed CLIs and
      partitions ready / needs step / not installed.
- [ ] Cursor-without-Agent path is one obvious card.
- [ ] Home does not advertise unprobed seats as ready.
- [ ] Returning warm-cache launch stays process-quiet (Launch Authority holds).
- [ ] Focused tests for badge projector + first-scan gate; GUI proof if chrome
      layout changes; founder dogfood on a clean TCC reset host.

---

## 12. Version history

| Ver | Date | Author | Change |
| --- | --- | --- | --- |
| v1 | 2026-08-10 | Intake (dogfood code red) | Claim, RCA, Shape A/B, slices FCS-S00…S06 |
