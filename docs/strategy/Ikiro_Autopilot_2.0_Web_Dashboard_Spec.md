# Ikiro Autopilot 2.0 — Web Dashboard Spec

**Status:** Implementation-ready spec (web dashboard only)
**Owner:** Ikiro
**Scope:** The owner-facing **web dashboard** for Ikiro Autopilot. Native mobile,
public `websitemd.org` proof site, and the underlying experiment/runtime engine
are referenced for context but are **out of scope** here.
**Audience:** product, design, front-end, and the agent runtime team building the
control + proof surface.
**Reconcile with (Ikiro repo):**
`Docs/strategy/ikiro-vision-gtm/Ikiro_Autopilot_Growth_Hacker_Strategy.md`,
`Docs/product/Conversion_Autonomy_Research_Loop_Contract.md`,
`Docs/product/Block_Based_Experimentation_Contract.md`,
`Docs/product/Site_Analytics_Tracking_Contract.md`,
`Docs/phases/10_Conversion_Testing_And_Pixels.md`. Where this spec and a runtime
contract disagree on a product *fact* (entitlements, event shapes), the contract
wins; where they disagree on *dashboard behavior*, this spec wins.

---

## 0. One-Page Brief

Ikiro Autopilot is **the first website builder with a built-in growth hacker**.
The dashboard is where the owner *meets* that growth hacker: sees what it found,
reviews what it wants to try, watches tests run, reads honest results, and decides
how much rope to give it.

The dashboard is not an analytics product and not an A/B-testing console. It is a
**relationship surface** between a small-business owner and an autonomous teammate
they are learning to trust. Every screen exists to do one of four jobs:

1. **Show the work** — what the growth hacker did, is doing, and plans next.
2. **Earn the decision** — make approving (or rejecting) a change a 10-second,
   confident act.
3. **Prove honesty** — never claim a winner the evidence doesn't support.
4. **Earn more autonomy** — convert proof into trust into a turned-up dial.

The structural moat behind all of it (state it in onboarding, never bury it):

> Other tools change your page *after* it loads with a third-party script —
> flicker, risk, and a winner you still implement by hand. Ikiro owns your
> **source, hosting, routing, and analytics**, so it improves the page **at the
> source before the visitor arrives**, measures it first-party, and applies the
> winner for you. Nothing else can do that.

### Brand-truth invariant (overrides every screen)

> **It will not lie about winners.** The dashboard may never display a "winner,"
> "lift," or "+X%" claim that the evidence state does not support. When evidence
> is insufficient, the UI says so plainly and pivots to deterministic advice.
> This is not a caveat; it is the reason the owner can eventually let the dial go
> to full auto.

---

## 1. Personas as entry points (not silos)

These are **entry points on one autonomy dial**, not separate products. The
dashboard's job is to move a user *up* the dial as proof accumulates.

| Persona | Enters at | Wants from the dashboard | Graduation goal |
| --- | --- | --- | --- |
| **Hesitant SMB owner** ("I know my business") | Propose & Approve | Proof of work, before/after with honest stats, control over every change | Auto-launch once they trust the reads |
| **"I'll decide what to test" operator** | Owner-Directed input | To request specific tests (headlines, signup forms) and get a smart second opinion | Let the agent propose too |
| **Vibe coder / agent-native** | Full Autopilot | Hands-off operation, results, an API, a log | Stay hands-off; check the log weekly |
| **Agency** (later) | Per-client dial | One workspace, per-client autonomy, shareable Growth Diffs | Standardize a default dial across clients |

Design principle: **the cautious path is the default and the celebrated path.**
Confident users can turn the dial up immediately; nobody is forced to.

---

## 2. Core vocabulary (reuse Ikiro's; do not invent synonyms)

| Term | Meaning in the dashboard |
| --- | --- |
| **Growth Program** | A standing optimization loop attached to one page/goal (e.g. "more booking calls on the homepage"). Contains a running experiment + a queue of next ideas. |
| **Experiment** | One source-safe test: control vs. one or more variants, a goal, a denominator, an evidence state. |
| **Variant** | A source-safe change to the Website.md page. Rendered before the visitor arrives (no flicker). |
| **Advisor finding** | A deterministic, traffic-independent conversion risk + recommended fix. Works on day one with zero traffic. |
| **Proposal** | The growth hacker's pending request — to launch an experiment or to apply a winner. The unit the owner approves/rejects. |
| **Evidence state** | The honest status of an experiment's result (see §6). Governs what claims the UI may show. |
| **Autopilot Log** | The append-only, owner-readable history of everything tried, measured, applied, rejected, and queued. |
| **Growth Diff** | A shareable before/after-with-result card produced from a meaningful experiment. The viral artifact. |
| **Guardrails** | Always-on constraints (protected pages, brand/claims rules, budget, traffic floor, auto-rollback). Independent of the autonomy dial. |
| **The dial** | The autonomy setting (§3): how much the growth hacker may do without asking. |

---

## 3. The Autonomy Dial — the central mechanic

Autonomy is defined by **two gates**. The dial just decides which gates are
automatic.

- **Launch gate** — does *starting* an experiment require the owner's tap?
- **Apply gate** — does *merging a winner into the live source* require the
  owner's tap?

```
Rung 0  Advisor only      no experiments at all — deterministic advice + manual apply
Rung 1  Propose & Approve  launch = manual, apply = manual          (DEFAULT)
Rung 2  Auto-launch        launch = auto,   apply = manual           (trust building)
Rung 3  Full Autopilot     launch = auto,   apply = auto             (graduation)
```

- **Owner-Directed is orthogonal** — it is an *input channel*, not a rung. At any
  rung, the owner can add their own hypotheses ("test these 3 headlines"). The
  agent always responds as a teammate (see §5.4). You can be on Rung 3 and still
  drop in your own ideas.
- **Default = Rung 1.** New programs start cautious. The dashboard *invites*
  promotion when proof justifies it; it never auto-promotes.
- **Per-program override.** The dial has an account default, but each Growth
  Program can sit on its own rung (homepage on Rung 3, checkout on Rung 1).
- **Guardrails apply at every rung** (§7). Full Autopilot is *bounded* autonomy,
  never unbounded.

### Earned promotion (the trust → autonomy → tier loop)

The dial is the product's expansion engine. After the owner manually approves a
few honest reads, the dashboard surfaces a **promotion nudge**:

> "You've approved 4 of my reads and reverted none. Want me to launch the next
> safe test without asking? You'll still approve before anything goes live to
> visitors." → **[Turn on Auto-launch]** / [Not yet]

Rung 2→3 nudge requires a higher bar (e.g. ≥3 applied winners, 0 owner reverts,
auto-rollback never triggered). Promotion is always one tap, always reversible,
always logged. **Tier gating:** Rung 2+ and Growth Programs are the Autopilot
($19/mo) entitlement; Advisor + single approved experiments are Pro. (Confirm
exact gating against the entitlement contract.)

---

## 4. Information Architecture

Single left-rail dashboard. Five primary destinations; everything else is a
detail view or a modal.

```
┌ Ikiro Autopilot ───────────────────────────────────────────────┐
│ ◉ Today            ← the glance: what your growth hacker is doing │
│ ◇ Programs         ← list of Growth Programs + create new         │
│ ◇ Proposals  (2)   ← pending decisions (badge = needs you)        │
│ ◇ Log              ← Autopilot Log: full proof of work            │
│ ◇ Advisor          ← deterministic findings (the day-one hero)    │
│ ───────────────                                                   │
│ ◇ Growth Diffs     ← shareable before/after results               │
│ ◇ Settings         ← dial, guardrails, goals, budget, sites       │
└──────────────────────────────────────────────────────────────────┘
```

- **The Proposals badge is the heartbeat.** It is the one number that says "your
  teammate needs you." It also drives the weekly email digest (out of scope, but
  the dashboard owns the count).
- **Multi-site / agency:** a site switcher sits at the top of the rail. v2.0
  scope = single site polished; design the switcher so multi-site is additive.

---

## 5. Screen specs

For each screen: purpose, layout, the states it must handle, and the one thing it
must get right.

### 5.1 Today (home)

**Purpose:** In five seconds, answer "what is my growth hacker doing for my
business right now, and does it need me?"

```
┌──────────────────────────────────────────────────────────────────┐
│  Good morning. Here's what I've been working on.                   │
│                                                                    │
│  ┌── Needs you (2) ───────────────────────────────────────────┐   │
│  │  ▸ Proposal: test a shorter hero headline   [Review →]      │   │
│  │  ▸ Winner ready to apply: booking CTA color [Review →]      │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  ┌── Running now ─────────────────────────────────────────────┐   │
│  │  Homepage · "more booking calls"                            │   │
│  │  Hero headline test · ▓▓▓▓▓░░░ collecting · trend forming   │   │
│  │  847 / ~1,500 visits needed for a confident read           │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  ┌── Recently ────────────────────────────────────────────────┐   │
│  │  ✓ Applied: testimonial above CTA · +14% calls (measured)   │   │
│  │  – No difference: shorter nav labels · kept original (honest)│   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  Dial: Propose & Approve   [Tour what I could do on Auto-launch →] │
└──────────────────────────────────────────────────────────────────┘
```

**Must handle:** brand-new account (no programs), low-traffic account (no test
can reach significance — lead with Advisor, see §8), all-quiet ("nothing needs
you; here's what I'm watching"), error/site-unreachable.

**The one thing:** the "Needs you" block must feel like a teammate's standup, not
an inbox. Empty = a win ("All caught up — I'll ping you when I have something
worth your time"), not a void.

### 5.2 Programs (list + detail)

**List:** cards, one per Growth Program. Each shows goal, current experiment +
evidence state, this program's dial rung, and lifetime measured impact (only ever
*measured* numbers). Primary action: **Start a Growth Program** → goal picker
(more leads / more bookings / more sales / more signups / custom) → page picker →
confirm dial rung.

**Detail:** the program's home.
- Header: page thumbnail, goal, denominator, current dial rung (editable inline).
- **Now:** the running experiment (links to 5.4).
- **Queue:** ranked next ideas the agent intends to try, each with a one-line
  rationale ("your CTA repeats your headline — worth testing a benefit-led CTA").
  Owner can reorder, remove, or **add their own** (owner-directed input).
- **History:** every past experiment in this program with its honest outcome.

**The one thing:** the Queue is where "growth hacker as teammate" lives. Each
queued idea must carry a *because* — never a bare test name.

### 5.3 Proposals (the heart of the product)

**Purpose:** make a high-stakes decision feel safe and fast. This screen is why
the hesitant SMB stays. Two proposal types share one layout: **Launch this test?**
and **Apply this winner?**

```
┌── Proposal · Apply this winner? ──────────────────────────────────┐
│  Goal: more booking calls · Homepage                               │
│                                                                    │
│   BEFORE (control)            AFTER (variant B)                    │
│  ┌───────────────┐           ┌───────────────┐                     │
│  │  [rendered     │           │  [rendered     │  ← real source-    │
│  │   page         │    →      │   page         │    safe render,    │
│  │   preview]     │           │   preview]     │    not a mockup    │
│  └───────────────┘           └───────────────┘                     │
│                                                                    │
│  What changed:  Hero headline → "Book a call in 30 seconds"        │
│  Why I tried it: your headline described features, not the action  │
│                                                                    │
│  Result:  MEASURED WINNER ✓                                        │
│    Booking calls: 6.1% → 7.0%  (+14%, measured)                    │
│    Based on 1,612 visits over 9 days · confidence: high           │
│    No drop in any guardrail metric.                                │
│                                                                    │
│  If you apply: I update the source, keep the old version saved,    │
│  and you can revert in one click anytime.                          │
│                                                                    │
│  [Apply winner]   [Keep original]   [See the source diff]          │
└──────────────────────────────────────────────────────────────────┘
```

**Rules this screen enforces (non-negotiable):**
- The result line is rendered **from the evidence state** (§6). If the state is
  not `measured_winner`, the screen *cannot* show "winner" or a "+X%" headline —
  it shows the honest state instead and offers "keep running" or "stop."
- **Before/after are real renders** of the source-safe variants, not stylized
  mockups. (This is the moat made visible.)
- "Why I tried it" is always present — the decision is never naked.
- Reversibility is stated *before* the action, every time.
- Source diff is available (collapsed) for the technical owner; never the
  headline.

**Owner-directed launch proposal** adds a top note: "You asked me to test these
headlines. I added one more I'd bet on, and here's my prediction —" then the same
layout.

**The one thing:** approving must take ~10 seconds and leave the owner feeling
*smarter*, not rushed. Confidence, reversibility, and "why" do that.

### 5.4 Experiment detail (live test)

**Purpose:** an honest, calm window into a running or finished test. No
dark-pattern urgency, no fake precision.

- **Status band** driven by evidence state (§6) with a plain-language sentence
  and a progress-to-confident-read meter (visits collected / estimated needed).
- Control vs. variant(s): rendered previews + the source-safe change described in
  words.
- Goal + denominator stated explicitly ("booking calls ÷ homepage visitors").
- Metric trend over time — but **trend ≠ winner**; label directional data as
  directional until the state earns the claim.
- Guardrail team: the metrics that must *not* drop (e.g. bounce, page speed).
  Auto-rollback threshold shown.
- Actions vary by dial rung: on Rung 1, "Stop test"; results route to a Proposal.
  On Rung 3, "Pause" + "I applied this automatically — here's why."

**The one thing:** the progress meter ("847 / ~1,500 visits for a confident
read") is the antidote to impatience and the honest answer to the traffic-floor
problem. Show the cost of certainty so the owner trusts the wait.

### 5.5 Autopilot Log (proof of work)

**Purpose:** the spine of trust. An append-only, human-readable timeline of
everything the growth hacker did — including non-wins.

- Reverse-chronological entries: proposed, launched, measured (winner / no
  difference / loser), applied, reverted, rejected by owner, queued next.
- Each entry: timestamp, program, plain-language summary, evidence state, and a
  link to the experiment/source diff.
- Filters: program, outcome, "needs nothing from me" vs "I acted."
- **Honesty is the feature:** the log must show inconclusive and losing results
  with equal prominence. A log that only shows wins reads as marketing and breaks
  trust. (Their own strategy doc requires at least one honest non-winner be
  visible.)

**The one thing:** any entry can become a **Growth Diff** (§5.7) in one click.
The log is also the content factory.

### 5.6 Advisor (the day-one hero)

**Purpose:** deliver value with **zero traffic** and serve the (large) majority
of SMB sites that can never reach statistical significance. This screen, not A/B
testing, is the front door for most users.

- Deterministic findings, each: the risk, why it matters, the recommended fix,
  and a one-click **"Draft this change"** (creates a source-safe variant → either
  a direct apply or a Proposal, per dial).
- Severity-ranked ("primary CTA below the fold on mobile" > "hero promise doesn't
  match your ad" > "no trust proof near booking link").
- Honesty rule: Advisor speaks in **risk/recommendation** language only —
  *never* "winner," "lift," or measured claims, because nothing was measured.
- When a site *does* have enough traffic, Advisor findings graduate into testable
  hypotheses and flow into a Growth Program's queue.

**The one thing:** this is what makes the traffic-floor problem a feature instead
of a failure. "Not enough traffic to test? Here's exactly what to fix anyway,
today." Make it feel generous and immediately useful.

### 5.7 Growth Diffs (share / build-in-public)

**Purpose:** turn proof into distribution. The viral artifact.

- Auto-generated shareable card from a meaningful result: before/after thumbnail,
  the change, the **measured** outcome, a timeframe, tasteful Ikiro mark.
- Owner controls: anonymize the brand, toggle exact numbers vs. relative, choose
  card theme.
- Export: PNG for social, link to a public read-only result page, embed.
- The "I turned on Autopilot 60 days ago and didn't touch my landing page — here's
  the log" narrative is assembled here from multiple diffs.

**The one thing:** only `measured_winner` results can render a number on a Growth
Diff. The brand-truth invariant follows the artifact off-platform.

### 5.8 Settings

- **Dial:** account default rung + the promotion ladder state. Plain explanation
  of what each rung lets the agent do.
- **Guardrails (§7):** protected pages/sections, brand & claims rules, max
  concurrent experiments, monthly budget cap, traffic-floor preference,
  auto-rollback sensitivity, quiet pages.
- **Goals:** define and prioritize conversion goals + how each is measured
  (first-party event, lead capture, checkout handoff, pixel where policy allows).
- **Sites / connection:** which Ikiro site(s) Autopilot operates, analytics +
  conversion tracking status, health.
- **Honesty & data:** confidence threshold (with a sane default; warn if loosened),
  data export, delete program memory.

---

## 6. Evidence states (the honesty engine the UI is built on)

Every experiment is always in exactly one state. The state **governs what the UI
may claim.** Front-end must derive all result copy from this enum — never from raw
percentages.

| State | Meaning | UI may show | UI may NOT show |
| --- | --- | --- | --- |
| `collecting` | Not enough data yet | progress meter, "collecting" | any winner/lift |
| `trend_forming` | Directional, not significant | "leaning toward B (not yet confident)" | "winner", "+X%" as fact |
| `measured_winner` | Significant + meets threshold + no guardrail drop | "Measured winner ✓", measured +X% | — |
| `measured_no_difference` | Full window, no real difference | "No measurable difference — kept original" | a winner |
| `measured_loser` | Variant significantly worse | "Original wins — variant hurt the goal" | spin |
| `inconclusive_underpowered` | Can't reach significance given traffic | "Not enough traffic to call this — here's what to fix instead" → Advisor | a winner |
| `rolled_back` | Auto-reverted on guardrail breach | what breached + that it's reverted | — |

**Traffic-floor handling (critical):** before launching, the agent estimates
whether the page can reach a confident read in a reasonable window. If not, it
does **not** start a vanity test — it routes to Advisor and tells the owner why.
This is the single most important honesty behavior in the product.

---

## 7. Guardrails (always on, every rung)

- **Protected pages/sections** — never touched (legal, pricing tables, checkout
  internals unless explicitly allowed).
- **Brand & claims rules** — banned phrases, required disclaimers, tone limits;
  variants that would violate them are never generated.
- **Budget cap** — monthly generation/allocation ceiling; dashboard shows
  spend-to-cap.
- **Concurrency cap** — max simultaneous experiments per site.
- **Traffic floor** — min visits before a test may run (else Advisor).
- **Auto-rollback** — if a live variant drops a primary or guardrail metric past
  a threshold, revert immediately and log it (`rolled_back`), regardless of rung.
- **Quiet hours / freeze** — owner can freeze all autonomous action (campaign
  launch, big sale) with one switch.

Guardrails are visible and editable in Settings and summarized on the dial screen
so the owner always knows the bounds of "full auto."

---

## 8. Key flows (end to end, dashboard side)

1. **First run, low traffic (the common case).** Connect site → Autopilot audits
   → Advisor shows 3 ranked findings → owner clicks "Draft this change" → Proposal
   (or direct apply on higher rung) → applied + logged → Growth Diff offered. Value
   delivered before any test exists.

2. **First measured win (the trust moment).** Program running on Rung 1 → test
   reaches `measured_winner` → Proposals badge → owner reviews before/after +
   honest read → Apply → logged → **promotion nudge to Rung 2**.

3. **Owner-directed test.** Owner adds "test these 3 headlines" to a program queue
   → agent augments with a 4th + prediction → launch Proposal → runs → honest read
   → apply/keep.

4. **Honest non-win.** Test reaches `measured_no_difference` → no Proposal to
   apply; Log entry created; Today shows "kept original (honest)" → reinforces "it
   won't lie." Optionally becomes a Growth Diff about *process*.

5. **Promotion to full auto.** Owner has applied ≥3 winners, 0 reverts → Rung 2→3
   nudge → on Rung 3, agent launches + applies within guardrails; owner reviews
   after the fact in the Log; auto-rollback protects them.

---

## 9. Design system & interaction principles (what makes it *insanely great*)

1. **Teammate, not dashboard.** First person, calm, specific. "Here's what I've
   been working on," not "Experiment #4821 — status: ACTIVE." Never a settings
   team cosplaying as a colleague.
2. **Artifacts over numbers.** Lead with rendered before/after; numbers support,
   never headline alone. The moat is *visible* — show real source-safe renders.
3. **Honesty as aesthetic.** Inconclusive and losing results get first-class,
   un-hidden, even *handsome* treatment. A beautiful "no difference" card is a
   trust flex.
4. **Every decision carries a "why" and a "you can undo this."** No naked
   approvals. Reversibility stated before the action.
5. **Calm, not casino.** No fake urgency, countdown timers, or precision theater
   ("+14.3%" when the interval is ±5). Round honestly; show confidence.
6. **One decision per moment.** Proposals are single, focused, fast. The badge is
   the only nag.
7. **The dial is always legible.** The owner can always answer "what can it do
   without asking me right now?" in one glance.
8. **Empty/low-traffic states are wins, not voids.** Every empty state delivers
   either an Advisor finding, a teaser of what's coming, or genuine reassurance.
9. **Performance is product.** The dashboard renders real page previews; cache
   thumbnails, lazy-load, keep the shell instant. Speed signals trustworthiness.
10. **Accessibility + responsive web.** Full keyboard path for approve/reject;
    legible at tablet width (owners review on iPads); semantic, screen-reader-
    labeled status. Responsive so a phone *browser* works even before a native app
    exists — but design for desktop/tablet first.

### Component inventory (build these once, reuse everywhere)
Proposal card · Before/After render pair · Evidence-state badge + sentence ·
Progress-to-confident-read meter · Program card · Queue item (with rationale) ·
Log entry · Advisor finding · Growth Diff card · Dial control + promotion nudge ·
Guardrail summary · Goal definition row · Site/connection health chip.

---

## 10. Out of scope for v2.0 (web dashboard)

- Native iOS/Android app (later expansion; push + one-tap approve). Responsive web
  must cover phone-browser review in the interim.
- The public `websitemd.org` self-operating proof site (separate surface).
- The experiment runtime, routing, analytics ingestion, and variant generation
  engine (consume their contracts; do not redesign here).
- Multi-site/agency management beyond a switcher stub.
- Billing/checkout UI (link out to existing Ikiro billing).
- Pixels/integrations config beyond the goal-definition surface.

---

## 11. Build sequencing (dashboard milestones)

Ship in this order; each milestone is independently demoable.

- **M1 — Advisor + Log (zero-traffic value).** Connect site, Advisor findings,
  draft-a-change → apply, Autopilot Log. *Proves value with no experiments.*
- **M2 — Programs + Experiment detail + Proposals (Rung 1).** Full propose→approve
  loop with honest evidence states and real before/after renders. *The trust
  loop.*
- **M3 — The dial + earned promotion (Rung 2/3) + guardrails surface.** Auto-launch,
  auto-apply within bounds, promotion nudges. *The expansion engine.*
- **M4 — Owner-directed input + Growth Diffs.** Owner hypotheses with agent
  second-opinion; shareable proof. *Engagement + distribution.*

---

## 12. Success metrics (dashboard-specific)

| Metric | Why it matters |
| --- | --- |
| Time-to-first-value | First Advisor fix applied (should beat first measured test by weeks) |
| Proposal decision rate / time | Is the review surface fast and trusted? |
| Dial promotion rate (R1→R2→R3) | The trust→autonomy→tier engine working |
| Revert rate after apply | Trust integrity; should stay near zero |
| Honest-non-win visibility | % of users who've seen ≥1 inconclusive/losing result (trust proof) |
| Growth Diff shares | Distribution loop firing |
| Autopilot ($19/mo) conversion from Pro | The dial paying off commercially |

---

## 13. The single sentence to keep the team aligned

> Build a calm, honest teammate the owner meets in their browser — one that proves
> its work, makes every decision a confident 10 seconds, and earns the right to do
> more while they sleep.
