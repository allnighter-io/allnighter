# CLI Capacity TUI Sampling

Status: **OPEN — founder intake packet. Do not implement until slices are
scoped and product-law amendment is explicit.**
Owner: AllnighterCore (ledger + contract) + AllnighterEngine (probes, admission,
Boost routing); AgentOS may own per-driver PTY/spawn helpers if probes live
next to workers
Created: 2026-07-29
Origin: Founder brainstorm — multi-CLI weekly / 5-hour / session limits are
real; headless CLIs generally do **not** expose remaining capacity as JSON.
They *do* print it in interactive status/usage UIs (`codex` `/status`, Claude
Usage pane, Antigravity-style `/usage`, etc.). Alln is flying blind until a
seat dies. Sample those TUIs on a schedule, own a local ledger, feed dashboard
+ Boost same-tier routing + harvest.

Related (not SSOT; reconcile before build):

| Doc | Relation |
| --- | --- |
| [`parked/Utilization_Admission_Control.md`](parked/Utilization_Admission_Control.md) | Parked admission control; sketched PTY probes as Utilization2, banned quota dashboard / fake %. **This packet amends:** vendor-printed remaining is observation, not theater; Boost utilization is in scope. |
| [`Observed_Usage_On_Receipts_And_Live_Status.md`](Observed_Usage_On_Receipts_And_Live_Status.md) | Per-run **token/duration** on receipts — orthogonal. Tokens ≠ account quota windows. |
| [`threads/04_Observed_Usage.md`](threads/04_Observed_Usage.md) | Historical observed-usage law (fail closed, no estimates). |
| Code today | Reactive only: `CapacityClassifier` → `CapacityObservation` → `SourceCapacityLedger` / `VendorBackoffPolicy` park-wake; `alln capacity` projects **cooldowns after failure**, not pre-flight headroom. |

Phases are ephemeral. At closeout: promote product law into standing ops /
vocabulary / help; code remains SSOT for fields; archive this packet.

---

## Founder intake (SSOT_Founder_Input_Workflow)

```text
Founder intent:
  No CLI will reliably tell you remaining subscription capacity headless.
  Each major CLI already shows capacity in an interactive terminal surface
  (/status, Usage tab, /usage). Learn those shapes, sample on a schedule
  (e.g. hourly) and before heavy dispatch, parse fail-closed, store a local
  ledger. Build a dashboard. Use headroom for same-tier routing and Boost
  utilization so paid seats are harvested instead of discovered only at death.
  Occasional UI churn is an update tax, not a reason to skip the feature.

Product value:
  Quota harvesting is already mission language. Today the loop is try → fail →
  park → wake → substitute. With TUI samples the loop becomes sample → know
  windows → prefer fat same-tier seats → protect thin ones → park only when
  truly empty/unknown. Boost stops being failure recovery only and becomes a
  utilization control room. Multi-CLI 100% draw-down becomes tractable.

Trusted workflow slice:
  Install CLIs on the Mac → alln (or serve) runs per-driver capacity probes
  against interactive usage/status UIs → parsers emit CapacityWindow rows
  (session / weekly / plan class, % used or left, resetAt, raw snippet) →
  ledger + alln capacity JSON → Boost / floor strip → admission and same-tier
  substitute policy read the ledger → optional local burn projection labeled
  as local pace, never vendor truth.

Current state:
  Strong: post-failure capacity classification, vendorBackoff park/wake,
  SourceCapacityLedger cooldowns, authorized substitution policy, alln capacity
  for cooling sources.
  Missing: proactive sampling of vendor status/usage TUIs; pool-scoped remaining
  % and reset clocks before dispatch; Boost headroom strip; harvest order;
  same-tier auto-route from remaining (not only from 429).

Truth owner (target):
  Probe runners + driver grammars: Engine / AgentOS driver layer (TBD at slice).
  Ledger + CapacityWindow model: AllnighterCore.
  Public contract: extend alln capacity (one JSON for CLI/GUI/iOS).
  Admission / Boost policy: Engine; never invent % when sample missing.
  GUI: renders ledger only; no parallel SwiftUI capacity store.

CLI surface (target — refine at implementation):
  - alln capacity          — cooling + known windows + unknown seats
  - alln capacity sample   — force refresh (opt-in; rate-limited)
  - alln capacity --json   — agent/dashboard contract
  Exit: missing sample = unknown, not error; parse fail = unknown + stale flag.

Help surface:
  Teach: capacity is vendor-printed when sampled; unknown means we have not
  read a usage/status UI recently or parse failed; tokens on receipts are a
  different system.
  Search: capacity, quota, usage, weekly limit, 5 hour, boost, substitute.
  Update HelpTopicRegistry in the same slice as the contract.

Proof scenario (dogfood):
  Codex /status shows weekly 52% left; Claude Usage shows session 37% used /
  week 32% used. After sample, alln capacity and Boost strip match those
  numbers with source + observedAt. Long work prefers the fatter same-tier
  seat; near-floor preferred seat offers or auto-routes to authorized
  same-tier substitute with headroom. After a vendor UI rename, parser fails
  closed to unknown (fixture proves); reactive park path still works.

Blocking questions:
  1. Probe host: PTY one-shot vs rare Terminal.app special-case — default PTY.
  2. Auto same-tier substitute on headroom: default-on for Boost, or ask-first?
  3. Sample cadence default (hourly?) and max probes/hour per source.
  4. Whether local burn projection ships in v1 or dashboard+routing only.
  5. Which drivers are v1 (Claude + Codex minimum?) vs later (Gemini, Grok, agy).

Next slice (after founder answers blocking where needed):
  CAP-TUI-S00 — driver matrix + fixture corpus from real /status and Usage pastes
  CAP-TUI-S01 — CapacityWindow model + ledger merge with existing observations
  CAP-TUI-S02 — first two probes (Claude + Codex) + alln capacity fields
  CAP-TUI-S03 — Boost / floor strip + pre-dispatch near-floor gate
  CAP-TUI-S04 — same-tier harvest / substitute from headroom
  CAP-TUI-S05 — optional local burn projection ("at current pace")
```

---

## Problem

Paid multi-CLI benches have multi-window limits (session / ~5h, weekly, plan
class). Vendors put the useful numbers in **interactive** status/usage UIs, not
in stable headless APIs.

Alln today learns capacity mostly when work **fails**. That is survival, not
harvest:

- long pilot/relay dies mid-flight near a floor
- wrong seat burns first
- Boost recovers after the fact instead of steering utilization

### Founder proof (dogfood pastes)

**Codex `/status` (shape):** account, model, context window % left, **weekly
limit** bar with **% left** and **resets** clock; also points at web usage URL.

**Claude Usage (shape):** session bar **% used** + reset; current week (all
models) **% used** + reset; plan/class week (e.g. Fable); optional “what’s
contributing” analytics; usage-credits toggle.

**Antigravity-class `/usage` (shape):** model **groups** sharing weekly +
five-hour limits with **% remaining** and refresh countdowns.

Parsers must accept both “% left” and “% used” and normalize; group/pool scope
beats per-marketing-model rows when the UI says models share a limit.

---

## Product law amendment

Prior parked utilization law banned quota dashboards and “fake percentages.”
That stays for **guessed** remaining.

**Allowed under this packet:**

| Allowed | Banned |
| --- | --- |
| Vendor-printed % used/left from a sampled status/usage UI | Invented % when the sample is missing or parse failed |
| Vendor-printed reset / refresh times | Pretending local projection is vendor truth |
| Pool/group scopes as the UI groups them | Silent substitute outside authorized same-tier policy |
| Optional local burn trajectory labeled “at current pace (local)” | Preflight token-cost estimates as hard gates |
| Fail closed → `unknown` + keep reactive park path | Zero-fill remaining to look complete |

**Admission control remains the abstraction** — “can this seat take this
attempt?” Headroom samples feed admission and harvest; they do not become a
billing product.

---

## Why this is high leverage (especially Boost)

| Layer | Effect |
| --- | --- |
| **1. Edge avoidance** | Don’t start long mutating work when a sample shows near-floor session/week |
| **2. Same-tier harvest** | Prefer fat seats; protect thin preferred seats; authorized substitute when preferred is thin and alternate has room |
| **3. Reset clocks** | Queue heavy work after known resets; wake from sample clocks, not only from 429 text |
| **4. Dashboard** | One strip: every seat available / cooling / unknown + windows |
| **5. Optional projection** | Local pace → “likely empty by X” for human + soft throttle — not silent hard blocks from guesses |

Without samples, Boost is **retry when dead**.  
With samples, Boost is **run the bench at full draw without face-planting.**

---

## Architecture (target)

```text
per-driver CapacityProbe
  spawn interactive-capable session (PTY preferred; not Terminal.app as SSOT)
  invoke vendor usage/status surface (/status, Usage, /usage, …)
  parse with fixtures → CapacityWindow[] | parseFailed
  cache + rate limit; never keepalive storm

→ CapacityObservation / CapacityWindow
  source, confidence, observedAt, scope (session|weekly|planClass|…),
  remainingPct? | usedPct?, resetAt?, rawSnippet (capped)

→ SourceCapacityLedger (extend)
  merge probe windows with failure-derived cooldowns
  unknown ≠ full

→ alln capacity (one contract)
  CLI + Boost strip + future iOS

→ policy
  pre-dispatch near-floor gate
  same-tier order / substitute from headroom
  park/wake still from real limits when probes miss
```

### Not the architecture

- `osascript` + real Terminal.app windows as the system of record (fragile,
  focus-stealing, bad for `alln serve`). PTY/driver one-shot is the same *idea*
  (read the TUI humans already use) with a product-grade host.
- Browser scraping of vendor billing consoles by default.
- Parallel GUI-only capacity stores.

### Parser maintenance

Vendor UIs will change. That is expected:

- fixture corpus per driver from real pastes
- fail closed on mismatch
- ship grammar updates like any other CLI dialect

Partial coverage still wins: two sampled seats beat zero.

---

## Relationship to existing systems

```text
TUI capacity samples     →  account / pool headroom (this packet)
Failure CapacityObservation → reactive park / cooldown (exists)
Receipt token usage      → per-run cost signal when CLI reports (OUR packet)
```

Do not collapse these into one “usage” blob. Agents and UI must not confuse
**weekly limit 52% left** with **this run used 12.4k tok**.

---

## Non-goals (v1)

- Perfect multi-vendor dollar optimization
- Estimating task token burn to invent remaining
- Replacing write-lock / one-mutating-worker rules
- Mandatory browser login scrapers
- Claiming 100% accurate cross-device usage (Claude already notes local-only
  contribution analytics)

---

## Suggested slices (ephemeral; reorder at build)

| ID | Intent | Works Test (sketch) |
| --- | --- | --- |
| CAP-TUI-S00 | Matrix of drivers + paste fixtures (Codex status, Claude Usage, …) | Fixture pack green; matrix lists probe command per source |
| CAP-TUI-S01 | `CapacityWindow` + ledger merge; no live probes yet | Unit tests: used vs left normalization; pool scope; unknown |
| CAP-TUI-S02 | Claude + Codex probes + `alln capacity` fields | Dogfood sample matches live TUI within tolerance; fail closed fixture |
| CAP-TUI-S03 | Boost/floor strip + pre-dispatch near-floor warning/gate | Near-floor seat refused or warned for long work |
| CAP-TUI-S04 | Same-tier harvest / authorized auto-substitute from headroom | Preferred thin + alt fat → routes or offers alt |
| CAP-TUI-S05 | Optional local burn projection | Pace line labeled local; no hard block from projection alone |

---

## Risks

| Risk | Mitigation |
| --- | --- |
| TUI layout churn | Fixtures + fail closed + dialect updates |
| Probe cost / ToS gray area | Own machine, own account UI, rate limits, opt-in aggressive sample |
| Stale cache near floor | Shorter TTL for session windows; sample before long dispatch |
| Shared pools mis-modeled as per-model | Parse group/pool labels from UI |
| % remaining ≠ N tasks left | Coarse routing only; no fake task-count claims |
| Probe confuses context-% with account quota | Separate fields (Codex context window vs weekly limit) |

---

## Open product decisions

1. **Boost auto-route:** default automatic same-tier substitute when preferred
   is below threshold and alternate has headroom, or always confirm?
2. **v1 driver set:** Claude + Codex only vs include Gemini / Grok / agy / Cursor.
3. **Cadence:** hourly background + on Boost open + pre long-dispatch — confirm.
4. **Projection:** v1 or follow-on.
5. **Unpark utilization packet?** Absorb admission scheduling here vs keep
   parked and implement only sampling + Boost strip first.

---

## User-visible claim (target)

```text
Alln reads the same usage/status screens your CLIs already show, remembers
them, and spends the fat seats first — so Boost can harvest your paid bench
instead of learning limits only when a run dies.
```

Never claim capacity we did not sample. Never blame Alln when a CLI is silent —
show **unknown** and keep the reactive path.
`}