# Pricing Recommendation

Status: **v2 — recommended offer** (supersedes v1 "3 free Team runs / $9.95")  
Owner: Founder  
Created: 2026-06-15  
Updated: 2026-07-31 (free core + degrade-don't-brick + $12/$120 + founding cohort)

Change process: `docs/phases/Pricing_Change_Process.md`. Do not edit numbers in
this doc without running it.

## The Offer

```text
Free forever core
14-day full trial, starts at your first team run
$12/month or $120/year after that
Founding Builder: $199 once, first 100 only
Mac app + iPhone app included
Bring your own AI subscriptions
No per-run fee, no model markup
```

| Tier | Price | What you get |
| --- | --- | --- |
| **Free** | $0, forever | Capacity view (CLI + Mac app) · doctor / setup / readiness · menu, bootstrap, help · run history + Markdown export · **one worker, one round** |
| **Trial** | $0, 14 days | Everything in Builder. Starts at **first team run** (2+ workers), not at install |
| **Builder** | **$12/mo** or **$120/yr** | Unlimited fan-out and multi-round loops within your own provider limits · Mac command center · iPhone floor manager · team presets · synthesis presets |
| **Founding Builder** | **$199 once** | Everything in Builder, for life. **First 100 buyers only**, then retired permanently |

Later, after iOS ships and the surface deepens: $19–24/month for **new**
customers. Everyone earlier is grandfathered.

## The Line: Free = See. Paid = Do.

Free forever is not a crippled demo. It is a working tool that observes.

- **`alln capacity` is free in both CLI and Mac app.** It is a read-only mirror
  of the user's own quota. Charging for a mirror is indefensible — commercially
  (it's a weekend clone) and morally.
- **One worker, one round is free.** A single `claude -p` is something the user
  can already do in their own terminal. Charging for convenience they don't need
  us for is a bad line to defend.
- **Fan-out (2+ workers) and multi-round loops are paid.** These are the things
  that are genuinely hard by hand: parallel judgment across vendors plus
  synthesis, and a lead steering execution seats over rounds. We charge when we
  save real work.

Why this line and not a run counter:

1. **It keeps the binary installed.** A free user with `alln` on PATH is a call
   option. An uninstalled user is a permanently closed door — and the installed
   binary is the entire distribution asset.
2. **It generates the upgrade prompt at the moment of pain.** "Codex 4%, Claude
   80% headroom" is free-tier output; the next thought is "so run it on Claude
   instead," which is the paid action. The free tier *is* the marketing for the
   arbitrage story, better than any copy we can write.
3. **It is enforceable at one call site.** Seat count is already on hand
   (`MenuJSON.Team.seatCount`) and dispatch already funnels through
   `RunService`. One check, one place, few bugs. A run counter needs durable
   counting, retry semantics, and an answer to "did that failed run count?" —
   which is pure support load.
4. **It costs nothing to serve.** Everything free is local.

## Degrade, Never Brick

When the trial ends, the product **falls back to the free core**. It never
becomes a brick, and it never withholds data the user already produced.

This is the most important pricing decision in the doc, ahead of the number:

- A bricked tool gets uninstalled. An uninstall removes the distribution asset
  and closes the door on every future conversion.
- Word of mouth is the whole GTM. People do not recommend software that turned
  itself off on them.
- It de-risks trial anti-abuse: a false positive in the machine-hash ledger
  (`docs/phases/One_Paste_Cold_Start.md` §Trial) drops someone to a working free
  tier instead of bricking a paying-intent user.

Never hold run history or exports hostage. It is cheap to give and enraging to
withhold.

## Why 14 Days, Starting At First Team Run

The buying decision requires the user to hit a real "I need a second opinion on
something that matters" moment. That does not happen daily for everyone.

- **7 days** risks missing it, especially across a weekend.
- **30 days** delays revenue and teaches people to treat the product as free.
- **14 days** covers two working weeks.

Start the clock at the **first team run**, not at install. An agent that installs
`alln` on a Friday must not burn the weekend. Enforcement detail and the
anti-reinstall ledger live in `docs/phases/One_Paste_Cold_Start.md` §Trial.

## Why $12

The anchor is not "what is this worth." It is "is this a rounding error next to
the cheapest thing already in my stack." That thing is $20 (Claude Pro, Cursor,
ChatGPT Plus).

The category is also not "AI product" ($20+ anchor) — it is prosumer Mac dev
utility (Raycast, Warp, CleanShot: $8–20). Pricing at or above $20 forces a
comparison we lose: *"I'd rather add another Claude seat."*

- **Above $10**, because sub-$10 signals "utility that might disappear." We are
  asking users to trust that we will keep working against six moving vendor
  CLIs. $9.95 undersells that commitment.
- **Well under $20**, so it reads as obviously cheaper than one model
  subscription.
- **$12 vs $9.95 costs approximately zero conversion.** Nobody's budget breaks
  at $2, in an audience spending $60–250/month on AI.
- **It leaves headroom.** $12 → $19–24 later is a raise. $9.95 → $19.95 is a 2x
  and reads as a bait-and-switch.

**$120/year** because it is rounder and more marketable than $140, and
"**$10/month, billed annually**" is a strong second line.

## Why A Capped Founding Cohort

100 × $199 ≈ $20k now. The same 100 users at $12/month takes ~17 months to get
there. At zero funding, cash timing beats lifetime value, and early buyers
convert into evangelists.

The risk is real and is why it is capped: lifetime users are perpetual support
with no recurring revenue. **First 100, then retired permanently.** Never a
standing tier, never reopened.

## Why Not Usage-Based

Do not charge per team run.

Per-run pricing fights the behavior we want. The promise is: use the capacity you
already paid for, ask the team more often, stop rationing review. A meter makes
users think twice right before the magic moment.

Usage pricing also confuses responsibility:

```text
Is this Allnighter cost?
Is this Claude cost?
Did I just spend tokens twice?
```

Flat pricing keeps the story clean:

```text
You pay vendors for model access.
You pay Allnighter for orchestration.
```

## Pricing Principle

**Charge for coordination, not intelligence.** The customer already bought the
intelligence. Allnighter sells the missing operating layer: fan-out, synthesis,
comparison, dispatch, history, and mobile control.

Free core extends it: **observation is free, coordination is paid.**

## Claim Discipline (pricing surfaces)

Pricing copy is a compliance surface, not just marketing
(`docs/legal/Terms_of_Service.md`, `docs/legal/EULA.md`).

**Never say:**

- "quota harvesting" / "harvest your limits" — reads as circumvention
- "unlimited Claude/Grok/Codex" — we grant no model access
- "get more out of your limits" / "stretch your quota"
- anything implying Allnighter provides, pools, resells, or extends model access

**Say instead:**

- "Runs the CLIs you already installed, with your own login."
- "Unlimited Allnighter orchestration, within your own provider limits."
- "Allnighter never sees your provider credentials."
- "Bring your own AI subscriptions. Allnighter does not include model access."

The credential posture is both the trust claim and the compliance position: we
spawn the vendor's own CLI, which authenticates itself. We never read, store,
proxy, or transmit provider tokens.

## The Claude Credit Offer

Strongest paid-plan conversion angle for Claude Max users.

```text
On Claude Max 5x? Anthropic currently offers a $100/month Agent SDK credit for
eligible subscribers after opt-in. Allnighter helps you route real work through
your own local `claude -p` setup, then combines it with Grok and other workers.
```

Framing:

```text
Allnighter does not sell you Claude. It helps you use the Claude capacity you may
already have.
```

Do not imply: that Allnighter grants the credit, pools credits, can access
credits without the user's own Claude Code login, or that the credit applies to
every Claude interaction. Verify the offer is still live before publishing —
third-party program terms change.

## The Grok Offer

In the value stack, never as a hard unlimited claim.

```text
Add Grok as another worker in the team. If your Grok plan gives you generous
limits, Allnighter helps turn that capacity into useful second opinions and
synthesis inputs.
```

Internal note: if Grok stays effectively high-limit in practice it becomes one of
the best default workers. Track observed rate-limit failures and surface them
honestly in doctor and run history.

## Price Page Copy

```text
Free
$0 forever
See your whole bench.

- Live capacity across every connected CLI
- Doctor checks and setup
- Run history and Markdown export
- One worker, one round

Builder
$12/month — or $120/year
Make your AI team show up.

- Unlimited fan-out and multi-round loops, within your own provider limits
- Mac command center
- iPhone floor manager
- Claude Code, Grok, Codex, Gemini, Aider, and local workers
- Team presets and synthesis presets
- No model markup

14-day free trial, starting at your first team run.
When it ends, you keep the free core — and all your history.

Founding Builder
$199 once — first 100 only
Everything in Builder, for life.

Bring your own AI subscriptions. Allnighter does not include model access.
```

## Superseded (v1, 2026-06-15)

| v1 | v2 | Why |
| --- | --- | --- |
| 3 free Team runs, then dark | Free core forever + 14-day full trial | A brick gets uninstalled; the installed binary is the distribution asset |
| $9.95/month | $12/month | Sub-$10 signals disposable; $2 costs no conversion; headroom to $19–24 |
| $95/year | $120/year | Rounder; "$10/month billed annually" |
| No lifetime option | $199 capped at 100 | Cash timing beats LTV at zero funding |
| "quota harvester" as a feature name | Retired from all public copy | Reads as circumvention |
