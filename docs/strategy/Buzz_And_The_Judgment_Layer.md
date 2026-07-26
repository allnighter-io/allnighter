# Buzz and the Judgment Layer — a thought experiment

Status: **EXPLORATORY MEMO — revised 2026-07-25.** Still not a plan and not a
decision for marrying Buzz. For the original suspend-laws exercise only,
Allnighter laws were deliberately opened so the option space was visible;
nothing here changes any law. Implementing agents: this memo authorizes **no
core work**. Near-term product path is `docs/archive/phases/Team_Run_Receipt.md`.
Buzz remains an optional attended surface — see
`docs/phases/Buzz_Harness_Spike.md` (reframed).
Audience: founder + outside mentors. Written to stand alone.
Updated: 2026-07-25 (founder correction after first Growth Min run inside Buzz)

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

## 2026-07-25 correction (read this first)

Live Buzz UI + a real Growth Min run inside Buzz forced three corrections:

1. **There is no ALLN agent / "firm member" / plural seat type.** Buzz has
   humans and single-model agents (Opus, Fabel, Sonnet, …). Agent teams in
   Buzz are groups of those agents. `alln` is a **tool any agent or human can
   call**, not a peer identity that must appear in the Agents grid.
2. **Drop "firm as a member" / "only plural harness on the rails" language
   entirely.** Plural judgment is the *capability* alln provides when called;
   one accountable voice / one receipt is the *mechanic*. Story ≠ membership.
3. **The durable product wedge is not Buzz integration.** It is a
   **gorgeous, private-by-default, deliberately shareable Team Run Receipt**
   — signed alln attestation of what each seat said — openable from CLI and
   Mac, reusable for every team. Spec: `docs/archive/phases/Team_Run_Receipt.md`.
   Signing ≠ public. Public Nostr / hosted links are never default.

What Buzz still uniquely offers (optional, later): an **attended room** where
humans + agents already talk, someone calls alln, and the same receipt lands
**in the thread**. That legibility test survives; the membership mythology
does not.

Growth Min (run B64742…, Fabel lead) also sharpened the share framing: the
interesting Buzz-adjacent object is a **permalinkable / signed receipt**, not
plumbing. Same object must exist terminal-only so Buzz is distribution for the
receipt, never its home.

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
is a substrate that can **host** a call into our category.

## The structural argument (revised)

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

**3. Alln is the multi-vendor judgment tool agents invoke.** Buzz (and Slack,
and other agent chat surfaces) will fill with single-model agents. When those
agents — or humans — need a plural second opinion, they call `alln`. Vendor
labs are structurally unlikely to ship "judge our model against rivals using
the user's other subscriptions"; that remains our niche. This is a **call
site**, not a **membership category** on someone else's roster.

**4. Signed, shareable receipts upgrade alln's weakest story.** Today a
verdict's credibility often dies in terminal scrollback or a Mac-only Factory
Floor the CLI user never opens. A Team Run Receipt — local, private by
default, alln-signed attestation of seats + outputs + verdict, deliberate
share as file or (later) link — makes the judgment **keepable and showable**.
Buzz/Nostr can be one publisher of that object; they are not required for
signing, and public relays must never be the default (privacy).

**5. Open source cannot cannibalize our unit economics, because we have
none.** No-API-keys means users bring their own compute. We were never going
to sell tokens. The business was always going to be coordination and trust —
and those are network businesses, which open source accelerates rather than
undercuts.

## The playbook (revised sequencing)

**Move 0 — Ship the Team Run Receipt (authorized product path).** Gorgeous
private-by-default report from existing `TeamRun` / `TeamRunJSON`; CLI open;
deliberate signed file export; Mac Factory Floor stays the in-app reader of
the same truth. No Buzz dependency. Spec:
`docs/archive/phases/Team_Run_Receipt.md`.

**Move 1 — Optional: drop that receipt into attended rooms.** After Move 0,
test whether the **same object** feels magic in a Buzz thread (and later
Slack agents calling `alln`). Spike:
`docs/phases/Buzz_Harness_Spike.md`. Success = in-thread legibility, not
"alln appears as a Buzz agent."

**Move 2 — Open the contract before (or instead of) the engine.** Alln's
schemas, run grammar, and verdict/receipt format are already spec-shaped.
Publishing the *contract* as an open spec is a bid to make alln's output the
de facto standard for "what a multi-model verdict looks like" — while
deferring the decision about the engine. If the engine is ever opened, it
must be to win the standard, not as a gesture.

**Move 3 — Far-out: monetize judgment with a track record.** Block's stated
next frontier is *agents that can transact*. A completion oracle keyed on
multi-model, adversarially verified, never-rates-itself receipts is
imaginable. **Do not build escrow/DocuSign-for-agents now.** File it. Near-
term rent remains the prosumer motion; receipts seed the artifact shape.

One line for the revised thesis: **rooms give agents somewhere to talk; alln
gives them a plural judgment when called; the receipt is how that judgment
travels — private by default, shareable on purpose.**

## What we would refuse to do even with no laws

- **Marry buzz.** It is days/weeks old. It is the first *instance* of a
  pattern (agents as signed equal members on an open event log), not the
  pattern itself. Thin adapter only. If buzz stalls, Slack and GitHub will
  grow a worse version of the same shape — same receipt object, different
  room.
- **Invent an ALLN Buzz agent / firm-member identity as the product.** Wrong
  model of the UI; wrong growth story.
- **Public-by-default Nostr or hosted URLs.** Privacy. Share is deliberate.
- **Private auth relays as v1.** Too much infra; not required for signed
  local receipts or file share.
- **Port the macOS app onto Buzz.** Let the app remain a projection/debug
  viewer; invest in CLI + receipt.
- **Open the trust layer** if we ever open engine/contract. Reputation /
  attestation stay ours if that business appears.

## The laws test (why this isn't a pivot)

Run the suspend-everything exercise and notice which laws actually break:
pricing, and arguably no-API-keys (a hosted-seats offering becomes
imaginable for teams without subscriptions). Nearly everything else —
contract-first, agent-first schemas, alln-is-called-by-agents (menu not
router), never-rates-itself, CLI decoupling, no-git-management (buzz owns
git; alln sends orders) — turns out to be exactly the property set a
room-native judgment **tool** needs. Downside if buzz evaporates: mild —
Move 0 (receipts) is just finishing the product we already built.

## Honest counterarguments

- **Block builds orchestration themselves.** Possible. Mitigation remains
  specificity: multi-model deliberation over *vendor subscription CLIs*.
- **Buzz doesn't matter.** Still plausible. Why Move 0 is the bet and Move 1
  is a spike against the *pattern* (attended agent chat), not the brand.
- **Open-sourcing donates the hero loop.** True if done as a gesture.
- **Attestation / completion-oracle revenue is far away.** True. Do not
  staff it.
- **We're small.** Artifact quality can still set a judgment-format habit
  before distribution wars; receipts are that artifact.

## Questions for mentors

1. Does the "completion oracle" framing hold up against how you've seen
   trust/escrow markets actually form? (Far-out only.)
2. Contract-open vs. engine-open vs. both-closed given size asymmetry with
   Block — sequencing?
3. ~~Is "the firm as a member" legible?~~ **Retired.** Better question: does
   a gorgeous private receipt, then the same object in an attended Buzz/Slack
   thread, make "call alln for a plural judgment" obvious?
4. If you were Block, what would make you adopt an outside judgment **tool**
   (CLI + receipt) rather than grow your own?
5. What would falsify the receipt-first thesis fastest?

## Cheapest next steps (ordered)

1. **Build Team Run Receipt** — `docs/archive/phases/Team_Run_Receipt.md` (CLI WOW +
   private signed export).
2. **Feel it in CLI and Mac** — founder taste pass.
3. **Optional Buzz/Slack legibility** — drop the same receipt into a room;
   spike doc reframed accordingly. Record whether the *room* moment lands.
