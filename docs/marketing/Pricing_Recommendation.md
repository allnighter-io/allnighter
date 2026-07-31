# Pricing Recommendation

Status: **v3 — recommended offer** (supersedes v2 free-single-worker, and v1 "3 free Team runs / $9.95")  
Owner: Founder  
Created: 2026-06-15  
Updated: 2026-07-31 (daily free allowance · plain 14-day trial · $12/$120)

Change process: `docs/phases/Pricing_Change_Process.md`. Do not edit numbers in
this doc without running it.

## The Offer

```text
Free forever: see your whole bench + any 3 runs every day
14 days of unlimited, starting at your first run
$12/month or $120/year after that
Founding Builder: $199 once, first 100 only
Mac app + iPhone app included
Bring your own AI subscriptions
No per-run fee, no model markup
```

| Tier | Price | What you get |
| --- | --- | --- |
| **Free** | $0, forever | Capacity view (CLI + Mac app) · doctor / setup / readiness · menu, bootstrap, help · run history + Markdown export · **3 runs per day** — a run is any dispatch: one worker or six, single-shot or a multi-round loop. Nothing is feature-locked |
| **Trial** | $0, **14 days** | Unlimited dispatch. Starts at your first run, not at install |
| **Builder** | **$12/mo** or **$120/yr** | Unlimited dispatch within your own provider limits · Mac command center · iPhone floor manager · team presets · synthesis presets |
| **Founding Builder** | **$199 once** | Everything in Builder, for life. **First 100 buyers only**, then retired permanently |

Later, after iOS ships and the surface deepens: $19–24/month for **new**
customers. Everyone earlier is grandfathered.

## The Line: Not How Much — How Often

The free tier is **not a crippled version**. It is the whole product, three times
a day.

A free user gets full fan-out, full synthesis, full loops — everything a paying
user gets — capped at three runs per day. Nothing is feature-locked.

**A run is any dispatch.** One worker or six, one round or a loop, from the CLI
or the Mac app — it counts as one. Sitting in Claude Code and sending a single
job to Grok through `alln` is one of your three. There is no free single-worker
lane and no "team run" threshold; the unit is the dispatch, full stop.

This is the axis that resolves the real tension:

- **Unlimited single-worker free is too much.** With a hub like OpenCode, a free
  single-worker lane is a fully working multi-model router with capacity
  awareness and history. That is not a teaser for the product — it *is* the
  product, and giving it away builds a free competitor to the paid tier.
- **Zero free dispatch is too little.** A tool that cannot run anything gets
  uninstalled, and the installed binary on PATH is the entire distribution asset.

Three a day is neither. It cannot carry a working day — anyone doing real work
hits it before lunch and knows exactly why — but it is never nothing.

Why a **daily** allowance and not a lifetime one:

1. **It kills the worst support question in freemium.** "Did that failed run
   count?" A daily counter resets tomorrow, so a bad run costs a wait, not a
   ticket, and never an argument.
2. **It is the habit machine.** Claude.ai's own free tier proves the shape works:
   taste it daily, build the habit. Ours is strictly better — full power on every
   free run, and it never brick-walls you into a dead product.
3. **It is a safe ratchet.** 3 → 5 later is a gift. Unlimited → 3 is a betrayal.
4. **It self-selects the buyer.** Someone doing three runs a day was never going
   to pay, and is exactly the person who tells other people. Someone doing twenty
   is the customer.

Also free forever, and never metered: **capacity, doctor, setup, discovery, run
history, and export.** Capacity is a read-only mirror of the user's own quota —
charging for a mirror is indefensible commercially (a weekend clone) and morally.
It is also the daily reason to open the tool, and the upgrade prompt writes
itself: "Codex 4%, Claude 80% headroom" → *so run it on Claude* → that is the
paid action.

### Rejected alternatives

| Idea | Why not |
| --- | --- |
| Unlimited free single-worker lane | It is a working router; that's the product, not a demo (v2's error) |
| Limit the number of connected CLIs | Most users have two, so it gates nothing — and it punishes multi-vendor use, which is the entire product |
| N free runs total, then dark | Reintroduces "did that count?", and ends in a brick |
| Per-run pricing | See §Why Not Usage-Based |

## Degrade, Never Brick

When the trial ends, the product **falls back to the free tier** — still three
full runs a day, still the whole bench in view, still every past run readable and
exportable. It never becomes a brick and it never withholds data the user made.

Ahead of the number in importance:

- A bricked tool gets uninstalled. An uninstall closes the door on every future
  conversion and removes the distribution asset.
- Word of mouth is the whole GTM. People do not recommend software that turned
  itself off on them.
- It de-risks trial anti-abuse: a false positive in the machine-hash ledger
  (`docs/phases/One_Paste_Cold_Start.md` §Trial) drops someone to a working free
  tier instead of bricking a paying-intent user.

## Why 14 Days, Plain

Fourteen calendar days from the first run. One timestamp, one end date, the same
mechanic every other product in the category uses. Nothing to explain.

- **7 is too short** — the buying trigger is "I need a second opinion on
  something that matters," which does not arrive on a schedule.
- **30 is too long.** It delays revenue, hardens the "this is free" mental model,
  and by day 30 the user has forgotten they were on a trial, so the end reads as
  a bait-and-switch. Worst of all it **halves the learning rate** — at zero
  users, finding out whether anyone pays is scarcer than the revenue itself.
- **The habit worry behind "30 days" is real, but trial length is the wrong
  lever.** Habit comes from the free tier having a daily reason to open —
  capacity plus three runs. That is what keeps the tool installed forever, paying
  or not.

The clock starts at the **first run**, never at install — an agent that installs
`alln` on a Friday must not burn the weekend. That single rule handles the
"trial ran while I wasn't looking" worry, and it is the only special case.

**Rejected: counting only days the user was active.** Briefly considered, then
cut. No subscription software does it (the closest analogues are game playtime
trials and API credits), and unfamiliar metering reads as a trick even when it is
generous. It also creates state only we can compute — "6 active days left" is not
something a user can verify, and unverifiable state is what disputes are made of.
Above all it was redundant: **the 3-runs-a-day free tier is already the safety
net.** A trial ending early now costs unlimited runs, not the product.

Enforcement detail and the anti-reinstall ledger:
`docs/phases/One_Paste_Cold_Start.md` §Trial.

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

Do not charge per run.

Per-run pricing fights the behavior we want. The promise is: use the capacity you
already paid for, ask the team more often, stop rationing review. A meter makes
users think twice right before the magic moment.

The free tier's daily allowance is **not** a pricing meter — nobody is billed by
it. It is a throttle on a free tier, and it resets every day.

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

Free extends it: **seeing your bench is free, and so are the first three moves
each day. Working all day is paid.**

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
Any 3 runs, every day.

- 3 runs per day — one worker or six, single-shot or a loop, all the same
- Nothing crippled: full fan-out, full synthesis, full loops
- Live capacity across every connected CLI
- Doctor checks and setup
- Run history and Markdown export

Builder
$12/month — or $120/year
Make your AI team show up all day.

- Unlimited dispatch, within your own provider limits
- Mac command center
- iPhone floor manager
- Claude Code, Grok, Codex, Gemini, Aider, and local workers
- Team presets and synthesis presets
- No model markup

14 days of unlimited runs, free, starting at your first run.
When it ends you keep the free tier, your three runs a day, and all your history.

Founding Builder
$199 once — first 100 only
Everything in Builder, for life.

Bring your own AI subscriptions. Allnighter does not include model access.
```

## Superseded

| Was | Now | Why |
| --- | --- | --- |
| v1: 3 free Team runs, then dark | Free tier forever, 3 runs/day | A brick gets uninstalled; the installed binary is the distribution asset |
| v2: unlimited free single-worker lane | 3 full-power dispatches/day | Free single-worker is a working multi-model router — the product, not a demo |
| Briefly: 14 **active** days | Plain **14 calendar days** | Nobody in software does activity-based trials; opaque state the user can't verify reads as a trick — and the 3/day free floor already solves what it was for |
| Limit connected CLIs | Rejected | Most users have two; it gates nothing and punishes multi-vendor use |
| v1: $9.95/month | $12/month | Sub-$10 signals disposable; $2 costs no conversion; headroom to $19–24 |
| v1: $95/year | $120/year | Rounder; "$10/month billed annually" |
| v1: no lifetime option | $199 capped at 100 | Cash timing beats LTV at zero funding |
| "quota harvester" as a feature name | Retired from all public copy | Reads as circumvention |
