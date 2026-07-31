# Pricing Change Process

Status: **OPEN — standing process** (promote to `docs/operations/` at closeout)  
Owner: Founder (pricing is a founder decision, never an agent decision)  
Created: 2026-07-31

How to change a price, a tier boundary, a trial length, or the free core —
without breaking a paying user, contradicting live copy, or shipping a number
that exists in four places and agrees in two.

SSOT for the current offer: [`docs/marketing/Pricing_Recommendation.md`](../marketing/Pricing_Recommendation.md).  
Enforcement mechanics: [`One_Paste_Cold_Start.md`](One_Paste_Cold_Start.md) §Trial.  
Legal surfaces: [`docs/legal/Terms_of_Service.md`](../legal/Terms_of_Service.md), [`docs/legal/EULA.md`](../legal/EULA.md).

---

## Law 0 — Pricing is a founder ruling

An implementing agent never changes a price, a tier boundary, a trial length, or
what is in the free core. It may *propose* one with evidence. This is the one
place where "founder input is intent, not final authority" inverts: on pricing,
the founder **is** the authority.

An agent that finds a number in code disagreeing with the pricing doc fixes the
**code to match the doc**, and says so. It never resolves the conflict the other
way.

---

## Law 1 — One number, one owner, N projections

A price string must have exactly one definition. Everything else projects it.

| Fact | Owner |
| --- | --- |
| The offer (tiers, prices, trial length, free core) | `docs/marketing/Pricing_Recommendation.md` |
| What is gated | One admission check at `RunService` dispatch |
| Entitlement state / plan / expiry | The server ledger + signed token |
| Displayed price string | Checkout provider (Stripe), fetched or pinned once |

Never hardcode a price in Swift, in help text, in `TeachingSnippet`, in a
schema, or in an error message. Error copy says *"your trial ended"* and gives a
URL — it does not say *"$12/month"*. Prices change; binaries in the field do not.

**Grep gate:** a test asserts no currency literal (`$\d`, `USD`, `/mo`) exists in
`Packages/` or `Apps/` outside test fixtures. This is the mechanical version of
this law and it is cheaper than remembering.

---

## Law 2 — Never break the deal a paying user already accepted

- **Grandfather always.** A price increase applies to **new** customers. Existing
  subscribers keep their rate for as long as they stay subscribed. This is a
  standing promise, not a case-by-case kindness.
- **Founding Builder is permanent.** Lifetime means lifetime. It is capped at
  100 and retired, never reopened, never revoked, never converted to a
  subscription.
- **Never move something out of the free core.** Free-core scope is a ratchet: it
  can grow, it can never shrink. Taking away a free feature is the single fastest
  way to lose the word-of-mouth that is the entire GTM.
- A tier boundary may move **up** (more free) without process. Moving it **down**
  requires the full process below plus a founder ruling recorded in the decision
  log.

---

## Law 3 — Degrade, never brick

Any change must preserve: when entitlement lapses for any reason — expiry,
payment failure, a false positive in the machine-hash ledger, being offline past
grace — the product falls back to the **free core** and keeps all user data
readable and exportable. Never a brick, never withheld history.

A proposed change that produces a dead binary in any state is rejected on sight.

---

## Law 4 — Pricing copy is a compliance surface

Every pricing surface is also a claim about what we do and do not provide. Before
publishing, the copy passes the ban list in
`Pricing_Recommendation.md` §Claim Discipline:

- no "quota harvesting" / "stretch your limits" / anything implying circumvention
- no "unlimited <vendor>" — we grant no model access
- always: "Bring your own AI subscriptions. Allnighter does not include model access."

If a price change touches what is *provided* (not just what it costs), the legal
docs change in the same commit.

---

## The Process

### 1. Write the proposal (one page, in this packet's decision log)

```text
Change:      what moves, from → to
Who it hits: new customers only / existing / free tier
Why now:     the observation that triggered it (not a projection)
Evidence:    conversion, churn, support load, competitor move — actual numbers
Reversible?: if this is wrong, what does undoing it cost?
```

**No-estimates law applies** (same as the parked Cost Advisor): argue from
observed facts, never from projected revenue. "12 of the last 30 trials converted"
is evidence. "This should double MRR" is not.

### 2. Founder ruling

Recorded in the decision log below with a date. No ruling, no change.

### 3. Sweep every surface in one commit

A price change is not done until every one of these agrees. Grep for the old
number before claiming completion.

- [ ] `docs/marketing/Pricing_Recommendation.md` (SSOT — update the superseded table)
- [ ] `docs/marketing/Launch_Positioning_And_Copy.md`
- [ ] `docs/marketing/Growth_Playbook.md` if it quotes the offer
- [ ] Checkout provider (Stripe product + price object)
- [ ] Website / price page
- [ ] `docs/legal/Terms_of_Service.md` §Fees if the *structure* changed
- [ ] Trial length in `One_Paste_Cold_Start.md` §Trial and in the entitlement service
- [ ] Free-core scope in the `RunService` admission check
- [ ] Help topics and `TeachingSnippet` if they mention the offer at all
- [ ] Any onboarding / setup copy in the Mac app

### 4. Migrate existing customers correctly

- [ ] Existing subscribers stay on the old price object (Stripe: do **not**
      migrate them; create a new price, leave old subscriptions attached)
- [ ] Trial-in-progress users finish on the **old** terms
- [ ] Founding Builders untouched, forever
- [ ] If the free core grew, existing free users get it immediately with no action

### 5. Announce before it takes effect

- Existing customers: told before, not after, even when grandfathered — "your
  price is not changing" is a retention message worth sending.
- Free users: only if the free core changed.
- Never a silent price change. Never a price change discovered at renewal.

### 6. Record it

Append to the decision log. A price with no logged ruling is a bug.

---

## Decision log

| Date | Change | Ruling |
| --- | --- | --- |
| 2026-06-15 | v1 offer: 3 free Team runs → $9.95/mo | Founder (superseded) |
| 2026-07-31 | v2: free core forever · 14-day trial from first team run · $12/mo, $120/yr · Founding Builder $199 capped at 100 · degrade-don't-brick | Founder |
| 2026-07-31 | v3: free tier is **3 full-power dispatches per day**, not an unlimited single-worker lane (a free single-worker lane is a working multi-model router — the product, not a demo). Trial is a plain **14 calendar days** from first run. Connected-CLI limits rejected. | Founder |

---

## Open triggers (revisit pricing when one of these is observed)

Not a schedule — a list of observations that justify reopening. Do not
re-litigate pricing without one.

- Founding Builder cohort sells out (retire the tier, confirm no reopen).
- Trial → paid conversion observed over ≥ 30 trials, in either direction.
- iOS floor manager ships (the trigger for the $19–24 tier, **new customers only**).
- A vendor changes its terms in a way that touches what we may provide.
- Support load makes a tier unsustainable at its price.
- Churn concentrates in a single, identified cause (fix the cause first — price
  is almost never the real answer to churn in this product).

---

## Closeout

When this process has survived two real price changes, promote it to
`docs/operations/Pricing_Changes.md` and archive this packet. Laws 0–4 are the
part that must survive; the checklist is the part that will need editing.
