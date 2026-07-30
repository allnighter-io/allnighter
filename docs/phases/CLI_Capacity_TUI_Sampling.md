# Capacity Strip — cross-CLI headroom acquisition + launch surface

> Filename kept (`CLI_Capacity_TUI_Sampling.md`) so existing links survive.
> The packet is no longer "TUI sampling" — TUI probing is now **one tier** of an
> acquisition ladder, not the architecture. See §Acquisition ladder.

Status: **OPEN — intake FINAL 2026-07-29. Ready for slice scoping. Start at
CAP-S00 (spike). Product-law amendment below is explicit and binding on the
slices.**
Owner: AllnighterCore (ledger + contract) + AllnighterEngine (acquisition,
admission, Boost routing) + Mac app (launch surface); AgentOS may own per-driver
PTY/spawn helpers if tier-3 probes live next to workers
Created: 2026-07-29 · Intake finalized: 2026-07-29 (three founder passes:
ladder + launch screen; waste ledger + notifications; CLI strip + harvest
posture + utilization tab). Founder rulings recorded inline — do not
re-litigate scratched items without a standing instruction.

---

## Demand evidence (why this is not speculative)

Founder, 2026-07-29:

> "I check usage across 6 CLIs 5 times per day."

That is **~30 manual interactive TUI checks per day** — open a CLI, type
`/status` or `/usage`, read a bar, close it, repeat, and hold six numbers and
six reset clocks in your head. Then do it again in four hours because half the
windows are 5-hour windows.

This packet's real job description: **collapse 30 manual checks/day into one
glance at launch.** Everything else (Boost routing, harvest, admission) is
downstream of owning the numbers.

Founder ruling: the capacity strip is the **main screen on app launch**, with a
manual refresh control. See §Launch surface.

Related (not SSOT; reconcile before build):

| Doc | Relation |
| --- | --- |
| [`parked/Utilization_Admission_Control.md`](parked/Utilization_Admission_Control.md) | Parked admission control; sketched PTY probes as Utilization2, banned quota dashboard / fake %. **This packet amends:** vendor-printed remaining is observation, not theater; Boost utilization is in scope. Guessed % stays banned. |
| [`Observed_Usage_On_Receipts_And_Live_Status.md`](Observed_Usage_On_Receipts_And_Live_Status.md) | Per-run **token/duration** on receipts — orthogonal. Tokens ≠ account quota windows. |
| [`threads/04_Observed_Usage.md`](threads/04_Observed_Usage.md) | Historical observed-usage law (fail closed, no estimates). Waste ledger (§) is compatible: it reports the past, it does not predict. |
| `docs/gui/GUI_Workflow.md` | Launch-surface change needs a surface brief + Visual Proof Gate. |
| Code today | Reactive only: `CapacityClassifier` → `CapacityObservation` → `SourceCapacityLedger` / `VendorBackoffPolicy` park-wake; `alln capacity` projects **cooldowns after failure**, not pre-flight headroom. |

Phases are ephemeral. At closeout: promote product law into standing ops /
vocabulary / help; code remains SSOT for fields; archive this packet.

---

## Founder intake (SSOT_Founder_Input_Workflow) — amended

```text
Founder intent:
  I check usage across 6 CLIs 5x/day by hand. Put the whole bench in one glance
  on the launch screen with a refresh button. Vendors show capacity to humans in
  interactive surfaces; most do NOT expose it headless. Read it wherever it is
  cheapest to read, remember it, and spend what I already bought instead of
  discovering limits when a run dies.

Product value:
  Three things, in order of felt value:
    1. No dropped runs — a long mutating relay never starts on a seat about to
       die, so no half-written repo at minute 35.
    2. Less waste — quota does not roll over; expiring headroom is use-it-or-
       lose-it. Spend the seat that is about to reset.
    3. Utilize what you have — one glance replaces 30 manual TUI checks/day.
  Strategic: no vendor will ever show you your BENCH, only themselves. A neutral
  cross-vendor headroom ledger is knowledge no single CLI can hold. It is the
  first alln feature that is not "orchestration I could have scripted."

Trusted workflow slice:
  Install CLIs on the Mac → alln acquires headroom per driver at the cheapest
  available tier (on-disk log > structured stream > TUI probe > failure
  classification) → parsers emit CapacityWindow rows (scope, used/left, resetAt,
  source tier, raw snippet) → ledger + alln capacity JSON → launch screen strip
  ordered by reset clock → pre-dispatch guard + Boost harvest read the ledger →
  retrospective waste ledger reports headroom that expired unused.

Current state:
  Strong: post-failure capacity classification, vendorBackoff park/wake,
  SourceCapacityLedger cooldowns, authorized substitution policy, alln capacity
  for cooling sources.
  Missing: proactive acquisition; pool-scoped remaining + reset clocks before
  dispatch; launch strip; harvest order; same-tier routing from remaining (not
  only from 429); any record of headroom wasted at reset.

Truth owner (target):
  Acquisition runners + driver grammars: Engine / AgentOS driver layer.
  Ledger + CapacityWindow model: AllnighterCore.
  Public contract: extend alln capacity (one JSON for CLI/GUI/iOS).
  Admission / Boost policy: Engine; never invent % when sample missing.
  GUI: renders ledger only; no parallel SwiftUI capacity store.

CLI surface (target — refine at implementation):
  - alln capacity              — the strip: every seat, windows, resets,
                                 cooling, unknown+reason. Neatly formatted,
                                 readable inside ANY other CLI session.
  - alln capacity --refresh    — force re-acquire (tier-aware; rate-limited)
  - alln capacity --history    — this week / last N weeks utilization
  - alln capacity waste        — retrospective headroom expired unused
  - alln capacity --json       — agent contract
  Exit: missing sample = unknown, not error; parse fail = unknown + stale flag.
  Unknown NEVER blocks dispatch (see §Fail-closed means proceed).
  Grammar note: founder sketched `alln cli -usage` / `-refresh`. Canonical form
  is `alln capacity [--refresh]` — one command, existing `--flag` grammar,
  extends the command that already exists. Register "usage" as a help-search
  alias, do not create a second command (see §The CLI strip).
  **Parked CLIs** (`SetupStore.parkedDriverIds` / `alln drivers`): list **last**
  with status `parked` and do not sample them. Reuse `DriverListProjector` order
  (active A→Z, then parked A→Z). See `docs/phases/CLI_Park.md`.

GUI surface (target):
  Tab 1 — Capacity strip: the launch screen (founder ruling 2026-07-29) plus a
  persistent band. Manual refresh control.
  Tab 2 — Utilization: this week, then last N weeks as data accrues.
  Both render the ledger; the GUI owns no truth.

Help surface:
  Teach: capacity is vendor-printed when acquired; unknown means the vendor
  exposes no surface, or we have not read one recently, or a parser failed;
  tokens on receipts are a different system.
  Search: capacity, quota, usage, weekly limit, 5 hour, reset, waste, boost,
  substitute, headroom.
  Update HelpTopicRegistry in the same slice as the contract.

Proof scenario (dogfood):
  At launch, the strip shows all six seats without the founder opening a single
  CLI. Codex weekly matches `/status` exactly (it is the same number — see
  §Acquisition ladder tier 1). Claude session + week match the Usage pane after
  a probe. Long relay refuses/warns on a near-floor seat and names a fatter
  same-tier alternate. After a vendor UI rename, that seat degrades to
  `unknown — parser failed`, the rest of the strip stays live, and dispatch
  still works via the reactive park path.

Resolved decisions (were blocking):
  1. Probe host → PTY one-shot. Never Terminal.app as system of record.
  2. Auto same-tier substitute → OFFER-first in v1. Auto only when the seat is
     already hard-blocked (existing reactive path). Rationale: auto-routing on a
     possibly-stale scraped number produces "why did it silently use Sonnet".
  3. Cadence → opportunistic, not scheduled. Tier 1 is free and per-turn; tier 3
     samples at launch, on refresh press, and pre-long-dispatch if >30m stale.
     No idle background PTY storms.
  4. Local burn projection → KILLED. Replaced by anchored decrement (a strict
     upper bound, §) + retrospective waste ledger (§). No predictions ship.
  5. v1 driver set → prioritise by PAIN, not by parse ease. Evidence says the
     seats that actually run out are Claude and agy/Gemini (5h windows).
     Codex is free (tier 1) so it ships anyway. Target v1: Codex + Claude + agy.
  6. Email weekly report → SCRATCHED (founder, 2026-07-29). It is the only idea
     in this packet that needs a server, an account, a sender domain, and your
     usage data leaving the machine. Notification + in-app digest is the same
     value at ~1% of the cost. Do not re-litigate without a standing reason.
  7. Pricing → the capacity surface is FREE, forever, no account. See §Free tier.
  8. "Never advise" scope → corrected by founder. Do not advise on SPEND
     ("cancel this subscription"). DO offer WORK ("spend it on a Tech Audit").
     See §Harvest posture.

Next slice:
  CAP-S00 — acquisition audit + probe-starts-the-window spike
  CAP-S01 — CapacityWindow + buckets + anchored decrement + RETENTION (no probes)
  CAP-S02 — `alln capacity` CLI strip from tier-1 + failure data
  CAP-S03 — launch screen tab 1 (renders the same contract)
  CAP-S04 — pre-dispatch relay guard (posture-differentiated) + 429 baseline
  CAP-S05 — tier-3 probes (Claude, agy) + --refresh
  CAP-S06 — waste ledger + tier-1 history backfill
  CAP-S07 — utilization tab / --history (progressive weeks)
  CAP-S08 — weekly-rollover notification (whole bench, one alert, actionable)
  CAP-S09 — burn-to-reset harvest ordering + offer-substitute
  CAP-S10 — harvest posture (read-only exploratory teams for expiring headroom)
```

---

## Problem

Paid multi-CLI benches have multi-window limits (session / ~5h, weekly, plan
class). Vendors put the useful numbers where **humans** can see them, and most
do not expose them headless. Alln today learns capacity mostly when work
**fails**. That is survival, not harvest:

- long pilot/relay dies mid-flight near a floor, leaving a dirty tree
- the wrong seat burns first
- Boost recovers after the fact instead of steering utilization
- headroom expires unused and nobody ever sees it happen

---

## Acquisition ladder (replaces "sample the TUI")

The original packet assumed the interactive TUI is the only source. **That is
false for at least one driver, and verifying it per driver is the single
cheapest thing in this packet.** The TUI is a *render* of data the CLI already
has; sometimes that data is already on your disk.

Per driver, acquire from the highest tier available:

| Tier | Source | Cost | Freshness |
| --- | --- | --- | --- |
| **1** | On-disk session/rollout log | free (file read) | per turn |
| **2** | Structured stream on a run you were making anyway | free (piggyback) | per run |
| **3** | Interactive TUI via PTY one-shot | seconds + spawn + risk | per probe |
| **4** | Failure classification (exists today) | free | on 429 only |

Same ledger, same contract, same strip. The tier is recorded on every row.

### Tier-1 evidence: Codex (verified on this machine, 2026-07-29)

`~/.codex/sessions/<yyyy>/<mm>/<dd>/rollout-*.jsonl`, every turn,
`type: event_msg` → `payload.type: token_count`:

```json
"rate_limits": {
  "limit_id": "codex",
  "plan_type": "plus",
  "primary":   { "used_percent": 52.0, "window_minutes": 10080, "resets_at": 1785904336 },
  "secondary": null,
  "credits":   { "has_credits": false, "unlimited": false, "balance": "0" },
  "individual_limit": null,
  "spend_control_reached": null,
  "rate_limit_reached_type": null
}
```

Observed moving 47.0 → 52.0 across two sessions the same evening.
`window_minutes: 10080` = the weekly window; `secondary` is the slot for a
shorter window; `resets_at` is a unix epoch. This is **richer than `/status`
renders**, because `/status` is a view of this record.

Consequence: Codex needs **no probe, no parser corpus, no PTY, no churn tax** —
and is fresh per turn rather than per hour.

### Tier-3 evidence: Claude (verified absent, 2026-07-29)

`~/.claude/projects/**/*.jsonl` carries per-message `message.usage`
(input/output/cache tokens, service tier) but **no account-window percentage**.
Checked `~/.claude/cache`, `~/.claude/telemetry`, `~/.claude/sessions`,
`~/.claude/daemon` — nothing. Claude is a genuine tier-3 case: the Usage pane is
the only surface.

### CAP-S00 results — driver matrix (spikes run 2026-07-29)

Extractors are **pure, fail-closed, unwired**. None touch `CapacityWindow` /
`CapacityObservation` / `SourceCapacityLedger` — that is CAP-S01.

| Driver | Tier | Evidence | Extractor | Proof |
| --- | --- | --- | --- | --- |
| **Codex** | **1 — on disk** | `rate_limits` per turn in `~/.codex/sessions/**/rollout-*.jsonl`; 572 records over 6 weeks | not yet built | verified by inspection |
| **Grok** | **1 — on disk** | `~/.grok/logs/unified.jsonl`, `msg == "billing: fetched credits config"`; 88 records over 2 weeks | `GrokCapacityLog.swift` (`5eab2ca6`) | 5/5 tests + real-file probe: 42.0%, reset `2026-07-31T18:11:40Z`, 4.96 MB parsed in 271 ms |
| **agy** (Antigravity) | **3 — TUI only** | nothing on disk anywhere (`log/`, `cache/`, `brain/`, `implicit/`, `builtin/`, `conversations/`). The one `/usage` render found in `log/` was the founder's own paste echoed by `HandleUserInput` — **not** agy logging its pane | `AgyCapacityLog.swift` (`d5e17c8`) | 7/7 tests |
| **Kimi Code** | **3 — TUI only** | `wire.jsonl` has per-turn tokens but no account window or reset; `kimi-code.log` has 403 strings without structured metrics; no usage flag | `KimiCapacityLog.swift` (`d387cf8`) | 8/8 tests |
| **Claude Code** | **3 — TUI only** | `projects/**/*.jsonl` has `message.usage` tokens but no account window; `cache/`, `telemetry/`, `sessions/`, `daemon/` all empty of it | not built — no real fixture captured | audit only |
| **Cursor Agent** | **3 — TUI only** | nothing under `~/.cursor`, `~/.cursor-agent`, `~/.config/cursor*`, `~/Library/Application Support/Cursor*`, `~/Library/Caches/*cursor*`; no JSON surface on `cursor-agent status` | `CursorCapacityLog.swift` (`ba14add`) | 7/7 tests |

**27 tests green across all four extractors together** (`swift test --filter
CapacityLogTests`), verified independently of the authoring agents.

**Standing rule proven by the agy case: a vendor surface found inside a log is
not automatically an acquisition source.** Check whether the CLI wrote it or
whether a human pasted it. One grep for the input-handler prefix decides it, and
getting this wrong would have promoted a fixture to a data source.

### Dialect divergence is larger than expected

Four drivers, four incompatible shapes. Any shared `CapacityWindow` must absorb
all of these:

| Axis | Observed values |
| --- | --- |
| Polarity | codex/grok/kimi/cursor `% used`; **agy `% remaining`** |
| Reset encoding | codex epoch; grok ISO8601 with `+00:00` offset; **agy/kimi relative durations** (`164h 50m`, `1d 18h 3m`); **cursor bare month+day, no year, no time** (`Resets Aug 25`) |
| Window scopes | weekly, 5-hour, **monthly** (cursor), plan-class |
| Grouping | flat per-account (codex/grok/kimi); **pools sharing a limit** (agy: Gemini vs Claude+GPT); **nested parent/child** (cursor: Included → Auto, API) |
| Paid spend | grok `onDemandCap/Used/prepaidBalance` as `{"val": N}`; codex `credits.balance`; **cursor as raw dollars** (`$0 / $1`) |

Two consequences for CAP-S01: reset must be stored as an **absolute Date plus a
precision marker** (cursor's day-only date cannot masquerade as minute-accurate),
and every relative-duration parser must take `observedAt` as a parameter and
never call `Date()` internally, or none of it is testable.

### What CAP-S00 settles

**Tier 3 is the common case, not the exception.** Four of six audited seats are
TUI-only. The original packet's instinct was right for the bench as a whole; the
ladder's value is that it saves the two seats where the data is already free —
and those two (codex, grok) happen to be the ones that also carry **history**,
which is what the utilization tab needs.

**The PTY tier is now unavoidable and must be built well.** Earlier optimism
that probing might collapse to Claude alone is dead: agy, Kimi, Claude, and
Cursor all need it. That raises the priority of the CAP-S00 window-start
question — *does opening the usage pane start the window it reports?* — from a
per-driver detail to a gate on four of six seats.

**Parser risk is real but bounded.** Four dialects were written and proven green
in one session by delegated seats working in parallel. The fixture-plus-fail-
closed pattern held for every one. Ongoing cost is a dialect-maintenance tax on
infrastructure already maintained — the moat argument, now with evidence.

### Unaudited

Aider, and any further seats.

### Why the ladder is what makes the launch screen possible

If every seat were a PTY probe, launch would take ~20 seconds, spawn six
processes, and possibly steal focus. With the ladder, tier-1 seats render
**instantly from disk at launch**; tier-3 seats render last-known plus an age,
and refresh on demand. The ladder is not just a cost saving — it is the
difference between a launch screen and a loading screen.

---

## The three moments (design toward these, not toward a ledger)

**1. The reveal.** First `alln capacity` / first launch. Six seats, one strip,
six reset clocks. Nobody has ever seen their bench in one frame. This is the
screenshot people post.

**2. The save.** `held — codex weekly 4%, resets in 2h11m · starting on grok (61%)`.
One line that visibly prevented a half-written repo. Phrase it as an **action
taken**, not a warning shown.

**3. The waste.** `your gemini 5h window reset with 61% unused — 11 times this week.`
Loss aversion, from arithmetic on two observations. See §Waste ledger.

---

## Product law amendment

Prior parked utilization law banned quota dashboards and "fake percentages."
That stays for **guessed** remaining.

| Allowed | Banned |
| --- | --- |
| Vendor-printed % used/left, acquired at any ladder tier | Invented % when acquisition is missing or parse failed |
| Vendor-printed reset / refresh times | Pretending local accounting is vendor truth |
| Pool/group scopes as the vendor groups them | Silent substitute outside authorized same-tier policy |
| **Anchored decrement** — sample minus our own observed burn, as a strict upper bound | **Projection / "at current pace you will run out at X"** — KILLED |
| **Retrospective waste** — headroom that provably expired unused | Preflight token-cost estimates as hard gates |
| Fail closed → `unknown` + keep reactive park path | Zero-fill remaining to look complete |

**Admission control remains the abstraction** — "can this seat take this
attempt?" Headroom feeds admission and harvest; it does not become a billing
product.

### Projection is dead; two survivors do its job honestly

Projection was banned because it **predicts**. Two mechanisms deliver the same
value while only **reporting**:

**Anchored decrement (forward, conservative).** Hourly sampling is useless for
the only decision that matters — "should I start this 40-minute relay right
now" — because a 5h window at 40% can be at 0% twenty minutes later. You do not
need to re-sample: you own the runs.

```
remainingCeiling  =  sample.remaining − (our own burn since sample.observedAt)
```

Our burn is a subset of total burn (other devices spend the same account), so
this is a strict **upper bound**. It errs only toward caution, which is the
correct direction for admission. It is an observed anchor minus observed spend
— not an estimate. Expose as `remainingCeiling`, distinct from
`remainingObserved` + `observedAt`.

**Waste ledger (backward, factual).** See below.

---

## Buckets, not percentages

Routing needs a **total order over seats** plus **is this seat above the floor
for this posture**. It does not need `52.0`.

Ship three states — `fat` / `thin` / `empty|unknown` — plus the reset clock.
Every decision in this packet is expressible in those terms, and a parser can
be wrong about the number while still right about the ordering. That is far more
survivable across vendor churn.

Keep the raw % in the JSON and on the strip for human reading. **Do not route on
the number.** Exposing a percentage as the routing input invites the dashboard,
invites "how many tasks do I have left", and invites the theater the parked
packet correctly banned.

Corollary: **perceived value scales with fraction of bench covered, not with
parse precision.** Prioritise breadth of acquisition over depth of parsing.

---

## Launch surface — LOCKED 2026-07-29

Settled across a design pass with the founder against mockups v1 and v2
(`docs/phases/capacity/mockups/`). These are decisions, not options. Reopen only
by founder ruling.

### Placement in the app shell

| Decision | Detail |
| --- | --- |
| Capacity **replaces the "Start a run" empty state** in the main pane | Not a new destination, not a floating panel |
| **Composer stays pinned** below it, unchanged | It is already independent chrome with its own repo/branch line. Starting a chat loses zero friction — no floating composer needed |
| **Sidebar unchanged** | Navigation is orthogonal |
| Cut **"6/7 CLIs ready"** from the empty state | Redundant once the strip is above it |
| The existing **`6/7 ready` pill IS the persistent band** the packet asked for | Extend it with a capacity signal (`6/7 ready · 1 expiring`) and make clicking it return to the strip — that is the way back mid-session |
| Height | Hero + 7 rows + composer is near the limit of a laptop window. Accepted: most users run 1–3 CLIs. Strip scrolls under a pinned hero and composer if needed |

### Row model

- **One row per CLI. Never two.** Antigravity carries its two pools as two bars
  inside one row — one CLI, one position, one block.
- **Fixed order, never auto-sorted.** Seeded by developer-market-share default:
  Codex/ChatGPT, Claude, Cursor, Grok, Kimi, Antigravity. Not-ready and parked
  seats last. Sorting destroys the positional memory that makes a 5×/day screen
  feel instant; at seven rows there is nothing to sort *for*.
- **Two columns.** Weekly/monthly headroom (**bars + % + clock**) and the 5h
  window (**numbers only, no bars**). The asymmetry is deliberate: weekly is the
  loud planning column, 5h the quiet one.
- **`—` for seats with no short window.** Not an empty cell — for Grok and
  Cursor it is a genuine advantage worth stating.
- **Plan tier under the CLI name** (Plus, Max, Ultra, X Premium+).
- **Detail is a disclosure triangle**, not click-anywhere-on-row, so the row
  press stays free for a better action later. Four fields only: reset time,
  source path, **what the vendor actually said**, observedAt. Provenance is
  non-negotiable — a number with no origin cannot be checked, and `unknown` has
  no way to explain itself without it.

### Effective availability

The 5h column shows the **tightest ceiling**, not the vendor's isolated meter.
Kimi reads `0%` in both columns because its exhausted weekly makes a fresh 5h
window unreachable. Its own TUI says `5h: 0% used`, which is true and useless.

This is the first case where alln is **more honest than the source**. Guardrail:
the disclosure always shows the raw vendor value, so we derive, never hide.

### Colour — three states, mutually exclusive

| Colour | Meaning |
| --- | --- |
| neutral | room to work |
| **amber** | headroom with a deadline |
| **red** | no headroom |

Nothing is green. **Quiet is good news**; the screen speaks only when it needs
you. The states cannot collide because a seat with 0% has nothing to expire and
a seat that is expiring is by definition not empty.

**No status dot.** v1 had one and it made Grok read green (available) and amber
(expiring) simultaneously. Effective availability already carries the verdict,
so the dot was a second opinion with nothing to add. Deleted, not recoloured.

**Health is expressed as absence of numbers**, never colour: a not-ready or
parked CLI is dimmed with a reason where its numbers would be (`not ready —
probe failed`). Health and capacity can then never compete for the same pixel.

> Standing rule: **if a glance surface needs a legend, the encoding is wrong.**

### Hero zone

Fixed height, always present — the layout must not shift day to day. Content
changes, structure does not.

**Eligibility thresholds** (founder, 2026-07-29):

```text
< 48h left  AND  > 20% headroom   → eligible
< 24h left  AND  > 10% headroom   → eligible
```

These are not arbitrary. If a seat's 5h window is sized so continuous full use
roughly consumes the weekly, the most anyone can physically burn in T hours is
about `T/168` of the week — ~28% at 48h, ~14% at 24h. The thresholds mark the
point where remaining headroom starts to become **physically unusable**.

> A **burn ceiling is a physical constraint, not a forecast.** "You can use at
> most X before this resets" is a fact about vendor limits and is allowed.
> "You will use X" is a projection and stays banned. The 1:1 window-sizing
> assumption is a hypothesis; the utilization history will eventually replace it
> with each seat's observed peak burn rate.

**Selection is two-stage** — gate, then rank. Thresholds decide who is eligible;
**dollars at risk** decides which one is the hero. 25% of a $200 plan and 25% of
a $20 plan are both honest percentages and wildly different value. Capacity has
no common unit across vendors; **money does**.

Ranking input, in order of preference: ordinal plan tier by default (zero setup,
no invented data) → real dollars if the user optionally enters what they pay per
seat. That optional field earns its keep twice, because it is also what gives
the keep/cancel report teeth. **Never ship a built-in price table** — prices
drift and vary by region and grandfathering, and guessing them is the invented
data this packet bans.

Everyone else eligible drops to one quiet "also" line. One thing shouting beats
two things talking.

**Hero CTA sets the seat and focuses the composer** — the model chip becomes
Grok, the cursor lands in the input, the human types the task. It aims the
existing flow rather than inventing one, and it is autonomy rung 2 (suggest),
never rung 4 (auto-spend). Later it can offer harvest chips (Tech Audit, Bug
Hunt) for one-click read-only work.

### Language

**Never "wasting."** It is accusatory and presumptuous — 58% with a day left is
inventory with a deadline, not a failure. Banned everywhere including the
retrospective ledger.

| Use | Not |
| --- | --- |
| "Use it before you lose it" | "You are wasting capacity" |
| "unused at reset" | "wasted" |
| "58% of your week expires in 41h" | any verdict on the user's behaviour |

Show the two numbers; do not compute a judgment. The pace comparison runs
silently to decide who gets named — it never speaks.

### Still open

- Calm-state hero height — does "Everything has room" earn 132px on a normal
  day, or shrink and accept a small shift?
- Whether the hero CTA ships in the same slice as the strip (it is a real
  feature, not decoration).

---

## Unknown taxonomy (this is what makes or breaks perceived value)

Half a strip reading `unknown` reads as **broken**, not honest. Three different
unknowns produce three different feelings — never collapse them:

| State | Copy | Feeling |
| --- | --- | --- |
| Vendor exposes nothing | `unknown — no usage surface exposed by this CLI` | honest; quietly credits alln for the seats it *did* cover |
| Grammar drifted | `unknown — parser failed 2026-07-29, dialect update pending` | a maintenance state, not a defect |
| Never acquired | `unknown — never sampled · alln capacity sample` | a call to action |

Undifferentiated `unknown` is what makes someone close the window.

### Fail-closed means proceed

"Parse fail → fail closed" is ambiguous and a literalist implementer will read
it as *refuse to dispatch* — a vendor UI rename would then brick the whole
bench. State it explicitly in code and docs:

> **Unknown never blocks.** Unknown means proceed, warn, and fall back to the
> existing reactive park path.

---

## Waste ledger (replaces the killed projection slice)

You will have timestamped samples. When a window's `resetAt` passes with
headroom remaining, that headroom is **gone forever** and can be stated as
arithmetic over two observations — no prediction involved.

```text
$ alln capacity waste --since 7d

  Unused at reset, last 7 days
    codex     weekly     1 window   ·  38% left when it wiped
    gemini    5h        11 windows  ·  avg 61% left      ← most waste lives here
    claude    weekly     1 window   ·  12% left
```

Why this is the sleeper feature:

- It puts a **number on the gap between what you pay for and what you use** —
  the most persuasive artifact possible for *"you already pay for the team."*
- Short windows are where nearly all waste lives (eleven 5-hour resets a week =
  eleven chances to waste) and each individual reset is invisible today.
- It costs nothing beyond the ledger you are already keeping.
- It is purely retrospective, so it clears the no-estimates law cleanly.

---

## The CLI strip (`alln capacity`) — the primary wedge

Founder framing: *"a nicely formatted CLI command that prints your capacity by
CLI, in any CLI."*

The point is not that it is a command. The point is **it goes where the work
is**. You are three hours into a Codex session; you or your agent runs
`alln capacity` and the whole bench appears without leaving the terminal, the
session, or the train of thought.

Why this outranks the launch screen as the wedge:

- **No app switch, no install of a GUI.** Consistent with the standing law that
  the CLI is the product and apps are optional.
- **Five-second demo.** A terminal screenshot is pasteable; an app is a
  download. This is the shareable artifact (see §Distribution).
- **Agents can read it.** See below — this is bigger than it looks.

### Format rules

| Audience | Rule |
| --- | --- |
| Human, TTY | Aligned bars, color, **relative** reset clocks (`resets in 2h11m`), sorted by expiry |
| Not a TTY (piped, captured by another agent, in a transcript) | **Plain aligned ASCII. No ANSI color, no box-drawing.** Escape codes in another agent's context window are garbage that costs tokens and readability |
| Agent | `--json`, the same contract the GUI renders |

Default width 80 cols, degrade gracefully. Never emit a number without its
`observedAt` age. Sort by expiry, not by vendor name.

### The agent angle (underrated)

A lead agent steering a relay can run `alln capacity --json` and make its **own**
routing decision — read headroom, pick the seat, dispatch. That means
capacity-aware routing can ship as **information** long before it ships as
**policy**, with zero Engine changes.

This is also exactly consistent with the settled front-door design: there is no
intent router; `alln` **discloses** and the caller LLM **chooses**. Capacity JSON
is disclosure. It slots into `alln menu --json` / `alln bootstrap` as one more
input to selection. No new policy layer is required for v1 — and that is a
feature, not a shortcut.

---

## Harvest posture — the answer to expiring capacity

Founder pushback, accepted: *"Good idea to have teams such as a tech audit ready
to run, or code maintainer, that are exploratory. Better than having things go
to waste."*

This corrects an over-broad rule from the earlier amendment. Two different
things were conflated:

- **Advising on someone's money** ("cancel Grok") — conflict of interest, since
  alln's mission wants a full bench. Still banned; report facts only.
- **Offering work for headroom that is about to vanish** — no conflict, and it
  is the entire point of the product. **Do this.**

### What makes a good harvest task (first principles)

Expiring headroom is the ideal budget for **speculative read-only work**,
because the value bar is near zero (the tokens vanish regardless) and the risk
bar must also be near zero (you are not watching).

| Rule | Why |
| --- | --- |
| **Read-only / non-mutating** | One mutating worker per root is inviolable, and an unattended mutating run is how you get a surprise dirty tree |
| **Interruptible** | Dies at 80% → you lose only tokens that were expiring anyway |
| **Produces findings, never diffs** | Output is a reviewable queue, not a change to your repo |
| **Needs no attention right now** | Capacity is expiring *because* you are not there |
| **Genuinely useful** | Noise gets muted fast, and a muted harvest is the same waste one layer up |

Natural fits: Tech Audit, Code Maintainer, Bug Hunt, dependency/security scan,
doc drift check, test-coverage gaps. They are all exploratory + read-only +
finding-producing. Not a coincidence — that is the shape the constraints force.

**Implementation note:** harvest is a **posture** on the existing one
`team.run` primitive (posture + `mutating: false`), not a new primitive. It must
not become a parallel run path.

### Autonomy ladder — never skip a rung

| Rung | Behavior | Ships |
| --- | --- | --- |
| 1. **Notify** | "38% expiring in 6h" | v1 |
| 2. **Suggest** | "38% expiring — run Tech Audit on Codex?" one click | v1.5 |
| 3. **Queue** | You pre-authorize a harvest team; alln offers when the window closes; you confirm | v2 |
| 4. **Auto** | alln runs it unattended | v3, hard-gated |

Founder's "a PM run that auto-runs before credits run out" is rung 4. Hazards to
gate it with:

- **NEVER auto-spend into paid credits.** "Free" quota is only free inside a
  subscription window that resets. The Codex payload literally carries
  `credits: { has_credits, unlimited, balance }` and `spend_control_reached` —
  read them. Auto-harvest is permitted **only** within a resetting subscription
  window, never against a credit balance or metered overage. This is a
  billing-behavior stop under project law.
- **Contention.** An auto-run holding the write lock when you sit down is
  infuriating — another reason harvest is read-only and takes no lock.
- **Unread-output decay.** Six vendors × weekly = six auto-audits a week. If the
  last N harvest outputs went unread, **stop queueing them.** A system that
  notices you are ignoring it is the difference between a tool and a nag.

---

## Utilization tab — "nobody captures this data"

Founder: second tab on the main screen. This week; then last week; then last 8
weeks as data accrues.

### Why this is the strongest moat in the packet

Time-to-value is **inverted** from every other feature. Most features are best
on day 1 and stay flat. This one is near-worthless on day 1 and **compounds
forever**. Eight weeks of cross-vendor history cannot be copied by shipping a
feature — a competitor would have to have shipped it eight weeks earlier. The
data *is* the moat, and it accrues to whoever installs first.

Two hard consequences:

1. **Start collecting before the tab exists.** Retention is a **CAP-S01 schema
   requirement**, not a later feature. Ship a current-state-only ledger and both
   this tab and the notifications need a migration.
2. **This is the rigorous argument for free.** Free maximizes installs; installs
   start clocks; the moat is proportional to install-base × elapsed time.
   Charging for the strip would literally slow moat accumulation.

### Day-one backfill (verified 2026-07-29)

Tier-1 sources are already historical. On this machine, right now:

```text
~/.codex/sessions/**/rollout-*.jsonl
  623 rollout files · 572 carrying timestamped rate_limits
  2026-06-17  →  2026-07-30   (six weeks, unread)
  earliest:  2.0% used · window_minutes 300   · plan "pro"
  latest:   61.0% used · window_minutes 10080 · plan "plus"
```

The plan change (5-hour/pro → weekly/plus) is *visible in the data*. So the
utilization tab can light up with **six weeks of real history on first launch**,
before alln has observed anything itself. That is the reveal moment for tab 2 —
install alln, immediately see two months of your own utilization you did not
know was being recorded.

Backfill is tier-1-only by nature. Tier-3 seats start at zero and grow.

### Tab design

- **Progressive and honest.** Week 1 shows one week. Never render an empty
  8-week frame implying missing data. Label with weeks actually observed.
- **Per vendor:** avg %, peak %, **times capped**, times wasted at reset.
  "Times you hit the ceiling" is more decision-relevant than the average —
  40% avg with 3 ceiling hits means spiky, and spiky needs headroom.
- **Observation coverage is mandatory.** If alln was closed for three days, an
  average over partial observation *understates* usage and becomes a lie. Show
  `4/7 days observed` per week, and never average across gaps silently.

### What it unlocks: the keep/cancel decision

```text
8 weeks observed
  claude   94% avg   capped 6/8 weeks   ← load-bearing
  codex    34% avg   peak 61%, never capped
  grok      3% avg   2 runs total
```

A $20–200/mo quarterly decision currently made on vibes, because nobody
aggregates across vendors. **Report the numbers; never recommend cancelling.**
And guard the under-use paradox: low utilization may mean "I don't need this" or
"alln never routed there." Show utilization next to *what alln routed to that
seat*, so the user can tell whose behavior produced the number.

This is the same waste-ledger machinery over a longer window — one mechanism,
two products. It is also the honest, retrospective form of the parked Cost
Advisor idea, which was parked for violating the no-estimates law; facts about
the past do not.

---

## Notifications

Approved (founder, 2026-07-29). The strip only helps when you look; waste
happens when you are **not** looking. The alert is what converts a dashboard
into something that saved you while you were doing other work.

Hard rules — **actionable, rare, timed to the last moment action is possible**:

- **Never notify on short windows by default.** 5-hour windows × 6 CLIs is up to
  30 alerts/day. That is an instant mute and a dead feature.
- **Weekly rollovers are the trigger.** Once per vendor per week, unrecoverable,
  enough runway to act.
- **One notification for the whole bench, not one per vendor.**
  `3 weekly windows reset tomorrow — codex 38% unused, claude 51%, gemini 22%`
- **The notification does something.** Not "open your dashboard" —
  `Run Tech Audit on Codex now (38% expiring)`. The alert becomes a dispatch
  surface, which is the honest bridge from free monitoring to the paid product.

Cost is near zero: `alln serve` is already a background scheduler doing
wake/seed/continuation work, and `NotificationScheduler.swift` exists. A
weekly-rollover check is the same shape.

---

## Free tier

**Watching is free. Spending is the product.**

| Free forever, no account | Paid |
| --- | --- |
| Capacity strip (CLI + app) | Teams, relay, pilot |
| Waste ledger | Harvest routing / auto-substitute |
| Utilization history | Orchestration generally |
| Notifications | |

Rationale — this is not a loss leader (those cost money per user). Capacity
monitoring has **zero marginal cost** (local file reads and PTY probes on the
user's own machine; no server, no account) and a **fixed cost shared across all
users** (dialect maintenance). Free is not a sacrifice here, it is correct
pricing for a zero-marginal-cost good.

Strategic function: every other alln feature is **episodic** (I have a task → I
run a team). The strip is **daily** — the founder checks 6 CLIs 5×/day. Whatever
you open five times a day is the window you leave open, and that app gets free
distribution for everything else it does. Alln currently has no reason to be
open when you are not dispatching. This gives it one.

And the free surface is an honest advertisement for the paid one: *"Codex 38%
expiring in 6h"* is literally a pitch for running something on Codex right now.

---

## Distribution

The strip is **shareable** in a way orchestration is not. "Here's my bench" is a
screenshot. "I wasted 61% of my Gemini quota this week" is a hook. A dev with
six CLI subscriptions posting their strip is organic reach into exactly the
target audience.

Ship a copy-as-text / copy-as-image affordance early, **with account
identifiers, org names, and emails redacted by default**.

Vendor risk is low: reading your own usage surface on your own machine is
unremarkable. If a vendor responds by shipping a headless usage endpoint, that
upgrades them to tier 1 and makes the product better.

---

## Make "no dropped runs" countable

You cannot prove the counterfactual for a run the guard held. You **can** count
the thing that should go to zero: **reactive mid-relay 429 parks**.

Instrument that counter **before** the guard ships, so there is a before. If it
trends to near-zero afterwards, that is both the proof and the marketing line,
and it is honest. Ship without the baseline and it can only ever be asserted.

---

## Why this is high leverage

| Layer | Effect |
| --- | --- |
| **0. One glance** | Replaces ~30 manual TUI checks/day. Launch screen. This alone justifies the packet. |
| **1. Pre-flight relay guard** | Protect multi-round mutating pilot/relay (>3 turns) from mid-flight 429. Single-shot prompts stay fast/reactive; long relays check headroom before turn 1 to prevent dirty git state and lost context. |
| **2. Burn-to-reset arbitrage** | Quotas do not roll over. Model A resetting in 15m with 40% left is expiring inventory — spend it. Save Model B whose reset is hours away. Most original idea here; worthless unless you actually saturate, and the evidence says you do (agy two buckets, Gemini exact-5h resets). |
| **3. Role-aware admission** | Unbundle Lead (~2–5k tok/turn) from mutating Worker (~30–100k/turn). A seat at 10% headroom can still steer 20 Lead turns even when blocked from mutating work. Converts "seat is dead" into "seat can still steer" — extends the pilot loop past a limit instead of parking it. Needs almost no precision. |
| **4. Same-tier harvest** | Prefer fat seats; protect thin preferred seats; **offer** an authorized substitute when preferred is thin. |
| **5. Reset clocks** | Queue heavy work after known resets; wake from sample clocks, not only from 429 text. |
| **6. Waste ledger** | Quantifies the cost of not doing 1–5. |

Without acquisition, Boost is **retry when dead**.
With it, Boost is **run the bench at full draw without face-planting.**

---

## Strategy: the moat is defended by tedium

Vendors render capacity for humans on purpose, and a vendor who shipped a quota
API would still only cover **themselves** — which is the useless version. The
only entity that can know your bench's headroom is a neutral tool that reads six
human-facing surfaces and normalizes them.

That work is defended by **tedium**, not cleverness. A competitor copies a
feature demo in a weekend; they do not adopt an ongoing dialect-maintenance
obligation across six vendors. Alln already runs exactly that muscle for CLI
dialects — this is the same tax on infrastructure it already owns.

It is also the first alln feature that is not orchestration-you-could-have-
scripted. It is knowledge no single CLI can possess. **Put it at the top of the
pitch, above teams and relay.**

Framing discipline: stay on **"spend what you bought."** Reading your own usage
screen on your own machine is unambiguously fine. Never build or describe
anything as evasion (no auto-rotation across multiple accounts of one vendor,
no circumvention language). Costs nothing, stays defensible forever.

---

## Architecture (target)

```text
per-driver CapacityAcquirer  (tiered; see §Acquisition ladder)
  tier 1  read vendor session/rollout log on disk        ← Codex today
  tier 2  piggyback structured stream of a real run
  tier 3  PTY one-shot into the vendor usage/status TUI  ← Claude today
  tier 4  failure classification (exists)
  parse with fixtures → CapacityWindow[] | parseFailed
  cadence: launch, refresh press, post-run piggyback, pre-long-dispatch if
           >30m stale. No idle background PTY storms.

→ CapacityObservation / CapacityWindow
  source, sourceTier, confidence, observedAt,
  scope (session|fiveHour|weekly|planClass|pool),
  remainingObserved? | usedPct?, remainingCeiling (anchored decrement),
  bucket (fat|thin|empty|unknown), unknownReason?, resetAt?, rawSnippet (capped)

→ SourceCapacityLedger (extend)
  merge acquired windows with failure-derived cooldowns
  retain expired windows for the waste ledger
  unknown ≠ full; parseFailed → unknown, never a number

→ alln capacity / capacity waste / --json   (one contract)
  CLI + launch strip + future iOS

→ policy
  pre-dispatch floor gate, differentiated by posture (Lead ~5%, Worker ~20%)
  burn-to-reset prioritisation (spend expiring headroom first)
  same-tier order; OFFER substitute (auto only when already hard-blocked)
  park/wake still from real limits when acquisition misses
```

### Not the architecture

- `osascript` + real Terminal.app windows as the system of record (fragile,
  focus-stealing, bad for `alln serve`).
- Browser scraping of vendor billing consoles.
- Parallel GUI-only capacity stores.
- A scheduled hourly background sampler. Opportunistic acquisition + anchored
  decrement beats a cron that is stale exactly when it matters.

### Parser maintenance

Vendor surfaces will change. Expected, and priced in:

- fixture corpus per driver from real captures
- fail closed on mismatch → `unknown — parser failed`, never a number
- ship grammar updates like any other CLI dialect

Partial coverage still wins: two acquired seats beat zero.

---

## Relationship to existing systems

```text
Acquired capacity windows    →  account / pool headroom (this packet)
Failure CapacityObservation  →  reactive park / cooldown (exists)
Receipt token usage          →  per-run cost signal when CLI reports (other packet)
```

Do not collapse these into one "usage" blob. Agents and UI must not confuse
**weekly limit 52% used** with **this run used 12.4k tok**.

---

## Non-goals (v1)

- Perfect multi-vendor dollar optimization
- Estimating task token burn to invent remaining
- **Any forward projection** (killed — see §Product law amendment)
- Replacing write-lock / one-mutating-worker rules
- Mandatory browser login scrapers
- Claiming 100% accurate cross-device usage (vendors already note local-only
  contribution analytics)
- **Email reports** — scratched 2026-07-29; needs a server, an account, a sender
  domain, and usage data leaving the machine. Notification + in-app digest is
  the same value at ~1% of cost
- **Unattended auto-harvest (rung 4)** — v1 ships rungs 1–2 only
- **Subscription cancel/keep recommendations** — report utilization facts; the
  advice is the user's to draw

---

## Slices (ephemeral; reorder at build)

| ID | Intent | Works Test (sketch) |
| --- | --- | --- |
| **CAP-S00** | **Acquisition audit + window-start spike.** Per driver: where does the number actually live (tier 1/2/3/none)? And: **does opening the usage TUI start the window we are measuring, or consume a message?** If probing a 5h window starts that 5h window, tier 3 is self-defeating for that driver and must be launch/refresh-only. | Matrix: driver → tier, path/command, sample capture. Spike answers the window-start question for Claude + agy with evidence. |
| CAP-S01 | `CapacityWindow` + buckets + anchored decrement + ledger merge. **Retention of expired windows is part of the schema.** No probes. | Unit tests: used-vs-left normalization; pool scope; unknown taxonomy; ceiling monotone and never exceeds last observation; expired windows survive in the ledger with observation coverage. |
| CAP-S02 | `alln capacity` CLI strip from tier-1 (Codex) + existing failure data. TTY vs non-TTY formatting; `--json`. | Real Codex weekly + reset printed in a terminal; piped output contains zero ANSI escapes; `--json` validates against the contract. |
| CAP-S03 | Launch screen tab 1 rendering the same contract. Surface brief + Visual Proof Gate. | App launches to the strip; rows sorted by expiry; unknown rows show their reason; no parallel SwiftUI store. |
| CAP-S04 | Pre-dispatch relay guard, posture-differentiated. **Instrument the mid-relay-429 baseline counter here.** | Near-floor seat refuses/warns for long mutating work; Lead posture still allowed. Baseline counter recording. |
| CAP-S05 | Tier-3 probes (Claude, agy) + `alln capacity --refresh`. | Probe output matches the live Usage pane within tolerance; renamed-UI fixture degrades that row to `unknown — parser failed` while the rest of the strip stays live. |
| CAP-S06 | Waste ledger + **tier-1 history backfill** from existing on-disk logs. | `alln capacity waste` counts only real retained observations; backfill reconstructs ≥6 weeks of Codex history from `~/.codex/sessions` on a machine that has never run alln's acquirer. |
| CAP-S07 | Utilization tab / `--history`, progressive weeks. | Week 1 shows one week and says so; per-week observation coverage rendered; no averaging across gaps. |
| CAP-S08 | Weekly-rollover notification via `serve` + `NotificationScheduler`. | One alert for the whole bench, fired only on weekly windows, carrying an action that dispatches. Short windows never fire by default. |
| CAP-S09 | Burn-to-reset harvest ordering + offer-substitute. | Preferred thin + alternate fat → offers alternate; expiring-soon fat seat sorts first. |
| CAP-S10 | Harvest posture: read-only exploratory teams for expiring headroom (rungs 1–2 only). | Suggested harvest run is non-mutating, takes no write lock, produces findings; refuses to run against a credit balance. |

---

## Risks

| Risk | Mitigation |
| --- | --- |
| **Probing starts the window it measures** | CAP-S00 spike gates tier 3 per driver; if true, launch/refresh-only, never automatic |
| TUI layout churn | Fixtures + fail closed + dialect updates; tier 1 where available is immune |
| Undifferentiated `unknown` reads as broken | Unknown taxonomy with reason + action per row |
| Stale cache near floor | Anchored decrement + `observedAt` on every row + pre-long-dispatch refresh |
| Fail-closed misread as refuse-to-dispatch | Stated law: unknown never blocks |
| Shared pools mis-modeled as per-model | Parse group/pool labels; pool scope beats per-marketing-model rows |
| % remaining ≠ N tasks left | Buckets for routing; no task-count claims anywhere |
| Confusing context-window % with account quota | Separate fields (Codex `model_context_window` vs `rate_limits`) |
| Probe cost / ToS optics | Own machine, own account surface, rate limits, "spend what you bought" framing, no multi-account rotation |
| Launch screen competes with chat home | Full strip on launch + persistent compact band thereafter |
| **Auto-harvest spends real money** | Never auto-spend against `credits.balance` / metered overage — resetting subscription windows only. Billing-behavior stop under project law |
| Auto-harvest holds the write lock when the user sits down | Harvest is read-only by rule and takes no lock |
| Harvest output nobody reads = waste one layer up | Stop queueing harvests when the last N outputs went unread |
| Notification fatigue kills the feature | Weekly windows only; one alert for the whole bench; short windows never fire by default |
| Averages over partial observation understate usage | Per-week observation coverage rendered; never average silently across gaps |
| ANSI escapes pollute another agent's context | Non-TTY output is plain ASCII, no color, no box-drawing |
| Shared strip leaks account identifiers | Redact accounts/orgs/emails by default in copy-as-text/image |

---

## Open decisions

Most were resolved in the amended intake. Remaining:

1. **Unpark `Utilization_Admission_Control.md`?** Absorb admission scheduling
   here, or keep parked and ship acquisition + strip + guard first.
   *Recommendation: keep parked; this packet ships the guard, not a scheduler.*
2. **Retention window** — how long to keep expired windows. Note the utilization
   tab wants ≥8 weeks, so 7d/30d is too short.
   *Recommendation: retain indefinitely; the rows are tiny and the history is
   the moat. Cap `rawSnippet` instead.*
3. **Band placement** in the Mac shell — needs the GUI surface brief.
4. **Which harvest teams ship as ready-to-run presets** (Tech Audit, Code
   Maintainer, Bug Hunt, dep scan, doc drift, coverage gaps) and whether they
   are new `TeamPreset` entries or existing ones in a harvest posture.
   *Recommendation: existing presets, harvest posture — no new catalog rows.*

**Resolved: Cost Advisor stays parked** (founder, 2026-07-29). It is a
*routing-advice* product; this is a *measurement* product. Different things, and
the name itself reads as forecasting what a run will cost — which this packet
must never do. Do not absorb it, do not unpark it, and do not add work for it
here.

The boundary that actually matters is **not** the parked status of another doc.
It is the rule already written into §Utilization tab: **report facts, never
recommend.** The keep/cancel numbers sit one inch from advice, and the failure
mode is someone quietly adding a "recommendation" column to the utilization tab
and shipping an advisor inside this packet without noticing. That rule is the
enforcement; treat it as binding.

Note without action: this packet's retained history is the data an advisor of
any kind would need. Keeping retention indefinite (decision 2) leaves that door
open later at zero cost. That is a consequence, not a plan.

---

## User-visible claim (target)

```text
Alln reads the usage screens your CLIs already show you, remembers them, and
puts your whole bench in one glance — so you spend the seats that are about to
reset, and a long run never starts on a seat that is about to die.
```

Never claim capacity we did not acquire. Never blame Alln when a CLI is silent —
show **unknown**, say why, and keep the reactive path.
