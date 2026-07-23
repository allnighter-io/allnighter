# Buzz and the Judgment Layer — a thought experiment

Status: **EXPLORATORY MEMO — a first-principles exercise, not a plan and not
a decision.** For this document only, all Allnighter laws (pricing,
no-API-keys, closed source, everything) are deliberately suspended so the
full option space is visible. Nothing here changes any law; only a founder
ruling can do that. Implementing agents: this memo authorizes no work except
the spike in `docs/phases/Buzz_Harness_Spike.md`.
Audience: founder + outside mentors. Written to stand alone.
Updated: 2026-07-23 (drafted)

## The prompt

On 2026-07-22, Block released **buzz** (buzz.xyz, github.com/block/buzz): an
Apache-2.0 workspace that puts people, agents, conversations, and code on one
level behind one cryptographic identity system. Everything — messages,
patches, CI results, reviews, approvals — is a signed event on a nostr relay
you host yourself. Agents join as equal members with their own keys and audit
trails, via harnesses for goose, codex, and claude code. Block says they will
run more and more of the company on it, and names as future work: agent
scoping, a hosted option, a workflow/agent ecosystem on the open spec,
web-of-trust reputation across relays, and "agents that can transact."

The question this memo answers: **if nothing about Allnighter were sacred —
no laws, no pricing, even open-sourcing on the table — what is the most
disruptive and lucrative playbook that buzz (or the direction it represents)
opens up?** And is the founder's instinct right that the alln CLI, not the
macOS app, is where nearly all the value sits?

## What Allnighter is (for outside readers)

Allnighter ("alln") is a CLI-first orchestrator that runs *teams* of
heterogeneous coding agents — Claude Code, Codex, Cursor, Grok, and others —
using the user's existing CLI subscriptions rather than API keys. Its hero
loop is **multi-model spec review**: several frontier models independently
pressure-test a spec or plan, findings are adversarially verified, and the
run produces a structured verdict plus an *impact ledger* of what changed and
why. Design commitments that matter for this memo:

- **Contract-first, agent-first.** Every CLI surface returns fully
  structured, schema-backed output designed for LLM callers. There is no
  "cheaper" text mode.
- **Alln never rates itself** (an inviolable rule internally called D5). The
  orchestrator produces judgments about *work*, never about its own
  performance.
- **Alln never touches git.** It sends orders; the repo and the vendor CLIs
  own all git operations.
- **The macOS app is a projection.** By internal doctrine the GUI renders
  state the CLI owns; the CLI is the product.
- Current business framing: a prosumer tool at roughly $20/month riding the
  user's own model subscriptions — meaning **near-zero marginal compute cost
  to us by construction**.

## What buzz actually is — and deliberately isn't

Strip the announcement to mechanics and buzz is a **substrate**: identity
(keypairs), memory (one signed, searchable event log), transport (relay),
and audit. Its agent story is one agent = one member; each harness wraps a
single agent, and the agent tool surface (`buzz-cli`) is explicitly "JSON in,
JSON out, designed for LLM tool calls" — the same design philosophy alln
arrived at independently.

What buzz deliberately does not do is **orchestration quality**. Nothing in
it answers: how do five heterogeneous models deliberate, check each other,
and emit a verdict a team can trust? Block's own roadmap punts exactly this
layer to the ecosystem — "workflows and agents on the open spec" and
"web-of-trust reputation" are listed as future work, in their words strong
opinions pending code. That is not a competitor shipping our category. That
is a substrate publicly requesting that our category exist on top of it.

## The structural argument

**1. Substrates commoditize the workspace app.** Buzz's desktop client is
free, open, and Block-backed. If signed-event workspaces win, every
proprietary chat GUI — including ours — is competing with free
infrastructure. Our own doctrine already concedes the point: the app is a
projection. In a buzz-shaped world the GUI is *someone else's*, and that's
fine, because it was never the asset.

**2. Everything defensible about alln lives in the CLI.** The cross-vendor
conductor running on subscriptions; the panel/pilot/relay run grammar; the
verdict and adversarial-verify machinery; the impact ledger; the
never-rates-itself rule; process ownership of every spawned agent tree. None
of it is in the app. The founder's instinct is right, and the gap is not
incremental — the app is replaceable in a quarter by any competent team; the
CLI's machinery is years of hard-won contract design.

**3. Alln is the only plural harness.** Every harness on buzz's list wraps
one agent: one member, one mind. Alln joining such a network is one signed
member that is secretly a *firm* — summon it in a channel and a multi-model
panel convenes, deliberates, and returns a judgment. The employee versus the
firm. Nobody else is positioned to be the firm, because nobody else built a
conductor over heterogeneous vendor CLIs.

**4. Signed substrates upgrade alln's weakest story.** Today a verdict's
credibility rests on trusting our process description. On a substrate where
every seat, finding, and verdict is a signed, permanent, attributable event
in the same thread as the conversation that shaped the work, credibility
becomes *inspectable*. Buzz made code review "a conversation with a
permanent record"; alln makes **spec review** one — with five models instead
of one.

**5. Open source cannot cannibalize our unit economics, because we have
none.** No-API-keys means users bring their own compute. We were never going
to sell tokens. The business was always going to be coordination and trust —
and those are network businesses, which open source accelerates rather than
undercuts.

## The playbook (everything on the table)

**Move 1 — Become the fourth harness, and the only plural one.** Ship a buzz
harness where an alln team joins as one signed member. `@alln panel this
spec` in a feature-branch channel; seats, impact ledger, and verdict land as
signed events in the thread. Cheap (the CLI is already portable and already
speaks structured JSON), demoable, and the kind of thing Block themselves
would amplify. The spike doc specs the weekend-scale version.

**Move 2 — Open the contract before (or instead of) the engine.** Alln's
schemas, run grammar, and verdict format are already spec-shaped. Publishing
the *contract* as an open spec is a bid to make alln's output the de facto
standard for "what a multi-model verdict looks like" on these networks —
while deferring the decision about the engine. If the engine is ever opened
(Apache 2.0, matching the ecosystem), it must be to win the standard, not as
a gesture: an open engine without the network play just donates the hero
loop to Cursor and goose.

**Move 3 — Monetize the layer that can't be self-hosted: judgment with a
track record.** This is the lucrative part. Block's stated next frontier is
*agents that can transact* — and Block is a payments company. The missing
piece in any agent-commerce loop is the **completion oracle**: was the work
actually done, and done well? An alln verdict — structured, multi-model,
adversarially verified, produced by a party that constitutionally never
rates itself — is precisely the artifact an escrow release wants to key on.
Endgame revenue is not $20/month tooling; it is attestation and take-rate on
verified agent work: reputation-bearing team cards with signed track
records, verified runs, cross-org panels convened between parties who don't
trust each other but trust the record. The prosumer motion survives as the
free on-ramp that seeds the network with track records.

One line for the whole thesis: **buzz gives every agent a name; alln gives a
group of agents a judgment. Names are becoming free. Judgment with a
permanent track record is the business.**

## What we would refuse to do even with no laws

- **Marry buzz.** It is a week old. It is the first *instance* of a pattern
  (agents as signed equal members on an open event log), not the pattern
  itself. Anything we build should sit behind a thin "signed-event context
  plane" adapter — buzz first because it's real and Block-backed, but the
  bet is on the pattern. If buzz stalls, Slack and GitHub will grow a worse
  version of the same shape, and we adapt to that instead.
- **Port the macOS app onto any of this.** Every hour there competes with a
  free Block product instead of owning the layer above it. Let the app
  become a debug viewer.
- **Open the trust layer.** Engine open, contract open — maybe. But the
  reputation registry and attestation service is the moat, and it only works
  run by a neutral party. That stays ours.

## The laws test (why this isn't a pivot)

Run the suspend-everything exercise and notice which laws actually break:
pricing, and arguably no-API-keys (a hosted-seats offering becomes
imaginable for teams without subscriptions). Nearly everything else —
contract-first, agent-first schemas, alln-is-called-by-agents (menu not
router), never-rates-itself, CLI decoupling, no-git-management (buzz owns
git; alln sends orders) — turns out to be exactly the property set a
network-native judgment engine needs. We have been building for this world
without naming it. That convergence is the strongest internal evidence the
thesis is real, and it means the downside case is mild: even if buzz and
this whole direction evaporate, none of the preparation is wasted, because
the preparation is just alln's existing roadmap.

## Honest counterarguments

- **Block builds it themselves.** Goose recipes could grow into
  orchestration; "workflow ecosystem" is on their roadmap. Mitigation is
  speed and specificity: multi-model deliberation over *vendor subscription
  CLIs* is a strange, hard-won niche that a company standardizing on goose
  has little reason to replicate. But the window is real and it is now.
- **Buzz doesn't matter.** Week-old repo, nostr niche, self-hosting is a
  big ask. Plausible. This is why Move 1 is a spike, not a bet — and why the
  thesis is written against the pattern, not the product.
- **Open-sourcing donates the hero loop.** True if done as a gesture. The
  playbook only opens the engine in exchange for standard-setting, and never
  opens the trust layer. The contract-first intermediate step exists
  precisely to test the water without giving away the machinery.
- **Attestation revenue is far away and depends on agent commerce
  materializing.** Also true. The near-term business remains the prosumer
  motion; the network play is where it compounds, not where rent is due
  next quarter.
- **We're small.** Standard-setting fights are usually won by distribution,
  which Block has and we don't. Counter: standards for *judgment formats*
  are won by whoever has the best artifact early. Nobody has one. The
  window argument again.

## Questions for mentors

1. Does the "completion oracle" framing hold up against how you've seen
   trust/escrow markets actually form? What did the analogous layer look
   like in payments, and who captured it?
2. Contract-open vs. engine-open vs. both-closed: given the size asymmetry
   with Block, which sequencing has historically worked for a small team
   trying to set a standard adjacent to a big player's platform?
3. Is "the firm as a member" legible to buyers, or does it collapse in
   people's heads into "another bot"? (The spike is designed to test
   exactly this — recording will accompany this memo.)
4. If you were Block, what would make you adopt an outside judgment layer
   rather than grow your own — and what would make you acquire it?
5. What would falsify this thesis fastest?

## Cheapest next step

The spike in `docs/phases/Buzz_Harness_Spike.md`: a local buzz relay, an
alln member with its own keys, one summoned panel, one signed verdict in a
thread, one recording. Weekend-scale, throwaway-permitted, changes nothing
in core. It converts the most speculative claim in this memo — that the
moment *lands* — into something we can watch instead of argue about.
