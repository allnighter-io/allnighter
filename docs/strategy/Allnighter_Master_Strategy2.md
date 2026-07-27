# Allnighter Master Strategy 2

Mentor-style strategy notes (cleaned). Supplements `Allnighter_Master_Strategy.md`.
Updated: 2026-07-27 — hero loop is all-day Spec Review / pilot / relay; overnight is a mode, not the mission.

## What this actually is

You're not building "another AI coding tool." You're building the neutral cockpit for the agentic-CLI era. The category is real and just forming: everyone with serious AI usage now holds 2–4 subscriptions (Claude Max, ChatGPT/Codex, Cursor, Grok), and every vendor is building lock-in — none of them will ever ship "fan your task out to our competitors and synthesize." That's structurally yours. Switzerland is the moat.

Three things compound into the actual product:

1. **Multi-CLI orchestration on your own repo, safely** (lanes, one mutating worker, proof/verify) — the "it won't wreck my repo" story matters as much as the intelligence story.
2. **Team = ensemble intelligence.** Different models genuinely catch different bugs and propose different designs. You get frontier-plus quality from subscriptions people already pay for. Zero marginal token cost to you or them.
3. **All-day floor + optional remote.** Spec Review, pilot, and relay are the daily habit (10-hour dogfood, not sleep). iOS / detach is optional steer when away from the desk. The name Allnighter is brand and domain only — do not let it redefine the product as overnight automation.

**One-sentence pitch:**

> You pay ~$400/month for AI coding subscriptions. Allnighter is the ~$10–20 that makes them work as one team — Spec Review before you build, pilot/relay while you ship, proof when something claims "done."

## Pricing: subscription, and the honest why

Your instinct might say flat fee since you have no token costs. But you do have a real recurring cost: the CLIs break constantly. Warm dialects, ACP, app-server flags, sandbox handoff — what you're actually selling on a recurring basis is **compatibility maintenance** — like a driver-update service for a fast-moving ecosystem. That's a legitimate, honest subscription. A flat-fee app that stops working when Codex changes is a refund machine.

Structure:

- **Free tier** that's genuinely useful: single CLI, Spec Review once or a few team runs. This is distribution — it must be good enough to recommend.
- **Pro, ~$10–20/mo** (or annual discount): Teams (ensemble judgment), pilot/relay, Mac + iPhone when ready. Price it as a rounding error on their existing AI spend — anchoring against $200 Claude Max makes $20 feel trivial.
- **Founder lifetime, ~$249–299**, limited early Mac app buyers — CleanShot/Raycast lineage loves lifetime deals; it funds you and seeds evangelists.

Skip per-seat/enterprise for now. This is a prosumer product; enterprise procurement would kill velocity.

## ICP: the multi-subscription power dev

Self-identifying tell: someone who has opinions about which model wins the same task.

- Senior/staff engineers and solo founders already on multiple AI subscriptions
- Indie hackers shipping products all day (and sometimes at night — the *product* is the all-day loop)
- Small agency owners / fractional CTOs running several CLI tools

This is maybe 100–500k people today — small, but high willingness-to-pay. Every new CLI (Gemini, Amp, OpenCode, Qwen…) makes a neutral cockpit more valuable, not less. Fragmentation is your tailwind.

What they'd love, ranked:

1. Full value from subscriptions they already guiltily underuse
2. **Adversarial Spec Review** before burning a week building the wrong thing
3. Model second opinions and pilot/relay without becoming the copy-paste traffic cop
4. Safe rails that let them trust multi-CLI work (and optional detach when needed)

## Marketing: the product generates its own content

Underrated asset: you are the only app that can honestly show "same hard task, four frontier models, head-to-head on a real repo" — inherently viral, evergreen, and impossible for vendors to make honestly.

- **Hero demo:** Spec Review on a real plan — three models catch different holes; synthesis shows what changed and who caught what. Second demo: pilot/relay multi-round fix with receipts.
- **Weekly model-vs-model reports on X:** "Claude vs Codex vs Grok reviewed the same spec — here's who won." People follow for the benchmarks and discover the app.
- **Build in public:** dogfood Allnighter on Allnighter; publish run logs and receipts. "This release was pressure-tested by Spec Review + pilot" is the story — not "written overnight."
- **Channels:** X is home base; Show HN when Spec Review + pilot is repeatable by a stranger in under 10 minutes; r/ClaudeAI, r/ChatGPTCoding; AI-coding YouTubers for comparison content.

Don't chase vendor partnerships — their incentive is lock-in; neutrality is the brand; lean into it.

## Risks to stare at honestly

- **Platform/ToS risk** is the big one. Keep the posture of "we drive the user's own tools on the user's own machine" — never proxy, never share accounts, never hold their keys (no-API-keys is legal armor too).
- Vendors ship native multi-agent (Claude Code already has subagents/teams). Your answer must stay **cross-vendor + your machine + optional phone** — things no single vendor will ship.
- Mac-only limits TAM but matches ICP. Don't port until Pro conversion proves out.
- **Name trap:** agents and marketers re-pitch "while you sleep." Kill that framing. Hero use is all-day attended judgment and multi-round loops.

## If it were mine

1. Cut scope to one hero loop and make it flawless: **prompt → Spec Review / team judgment → clear synthesis → optional pilot/relay → proof**. Everything else supports that sentence.
2. Gate iOS + full Teams behind Pro; free single-CLI / limited team runs; optional founder lifetime licenses.
3. Launch with Spec Review screencast + Show HN — not an overnight time-lapse as the only story.
4. **North-star metric:** Spec Review / pilot / multi-seat judgment sessions per user per week. Detach and while-away runs are a secondary capability metric, not retention proof. If people only do shallow daytime chat, fix the product — don't rebrand as sleep automation.
5. Accept what it is: most likely a fantastic $20–80k MRR indie business with a shot at becoming the neutral orchestration layer if agent fragmentation keeps accelerating. Don't raise VC yet — platform risk plus prosumer ICP means staying small and fast has option value.

**Internalize:** your moat isn't features (those get copied), it's neutrality plus the compatibility grind nobody else wants to do. Charge monthly for exactly that.

## The strategic shape this leaves

Own the bookends, concede the middle. Before execution: the Spec Forge (cross-vendor adversarial planning). After execution: behavioral proof. In between: executor-agnostic on purpose — "bring whichever CLI you love this month" becomes a feature, and vendor execution improvements make your product better instead of threatening it. You're the general contractor who writes airtight blueprints and runs the inspection, and happily subs out construction to whoever's best this quarter.

**Pitch, revised:** "Your agents fail because your specs are mediocre. Allnighter puts every frontier model in a room to tear your plan apart until it's airtight — then any one of them can build it in one pass, and shows you it working."

One honest caveat: the Spec Forge's payoff must be visible in the product — the synthesized spec needs to show what changed and which model caught what, pass over pass. If the fanout returns six walls of text the user still has to read, you've rebuilt six terminal tabs with nicer chrome. The synthesis step is the product. Spend design effort there before anything else.
