# Growth Playbook

Status: Draft v0.1 — brainstorm / starting point  
Owner: Founder  
Created: 2026-07-19

Zero-budget go-to-market, outreach, and traction playbook for Allnighter.
Self-funded; no paid ads. Channels are smart, savvy, and receipt-driven:
Reddit, Product Hunt, X, HN, newsletters, and built-in viral loops.

Related product surfaces: archived `docs/archive/phases/Agent_Intent_Router.md`,
archived `docs/archive/phases/Agent_Onboarding.md` (pilot, relay, agent-facing CLI).

---

## TLDR

Three unfair advantages:

1. Uses subscriptions you already pay for — no API keys.
2. The product generates its own proof-of-work content every night.
3. Agents themselves recommend it via the onboarding snippet.

Playbook sequence: build-in-public receipt series on X → concierge beta from
those threads → Show HN anchored on "it built itself overnight" → Product Hunt
→ newsletters.

Positioning line to beat: **"Your AI subscriptions, working together while you
sleep."**

---

## 1. The narrative wedge (get this right before any channel)

The killer insight isn't "multi-agent orchestration" — that's a crowded,
VC-flavored phrase. The wedge is visceral and financial:

> You're already paying for 4 AI subscriptions. They've never met each other.

Claude Code, Codex, Cursor, Grok — the target user has 2–4 of these logins
right now, siloed. Allnighter is the only tool that makes them a **team** using
the subscriptions you already have — no API keys, no new bills. That's a
genuinely differentiated claim (almost every competitor is BYOK, which reads as
"surprise $200 API bill"). Lead with it everywhere.

**Second wedge — the name itself:** "Go to sleep. Wake up to reviewed,
committed work." The relay/pilot overnight loop is the brand. Allnighter isn't
a metaphor — it's the feature. Very few products get to have their name be the
demo.

**Third — adversarial multi-model:** "Claude writes it, ChatGPT reviews it,
Grok breaks it." People intuitively trust cross-examination between rival models
more than one model grading its own homework. Spec Review is very marketable
this way: "before you burn a weekend building the wrong thing, let three
frontier models fight over your plan."

---

## 2. Receipts are your content engine

Allnighter has something most tools fake: run-truth artifacts. Commit logs,
RelayVerdicts, proof commands, impact ledgers. Every real overnight run is a
screenshot-able story:

- **Recurring X format:** "Went to bed at 11:40pm. Here's what Claude (PM) +
  Grok (dev) shipped by 7am: 3 defects fixed, 2 rounds, commits db058e6…" —
  with the actual relay thread screenshot. Post one every time you dogfood.
  This is a **series**, not a launch post — series compound, launches don't.
- **Meta-story:** Allnighter is being built by Allnighter. The first real
  piloted delivery (Claude PM + Grok dev fixing works-test defects on the repo
  itself) is a legendary launch-post anchor. "The tool merged its own bug fixes
  overnight" is HN front-page material.
- **Spec Review impact ledger →** "here's the disaster three models caught in
  my spec before I wrote a line of code" posts. Devs love dodged-bullet stories.

**Rule: never post claims, only receipts.** Zero-budget marketing lives and
dies on credibility, and Allnighter has mechanically-honest proof surfaces as a
product principle. Make that the marketing principle too.

---

## 3. The built-in viral loops (cheapest distribution)

Genuine product-native loops:

- **Agents are a distribution channel.** The Agent Onboarding snippet means
  Claude Code / Cursor sessions suggest Allnighter at the moment of intent
  ("get a second opinion", "keep going overnight"). That's install-time seeding
  of a recommender that lives inside the tools users already trust. No other
  indie tool has "the user's own AI recommends us" as a loop. Marketing
  implication: the recipe cards and snippet **are** marketing collateral —
  publish them publicly (an awesome-alln-recipes style repo / gist thread) so
  people encounter them before installing.
- **Commit trailers.** Overnight runs produce commits. A tasteful,
  off-by-default trailer (`Overnight run by <models> via Allnighter`) turns
  every dogfooder's public repo into a billboard. GitHub search for that
  trailer becomes social proof. (Careful with the no-git-management law —
  this is the worker CLIs writing their own messages, so it'd be a recipe-level
  convention, not an Allnighter feature. Worth a think.)
- **Shareable run receipts.** A "share this run" card (redacted, pretty,
  static) — the relay round summary as an image/page. People screenshot
  terminal output anyway; give them a version that looks great and carries the
  brand.

---

## 4. Channel playbook (priority order for $0)

1. **X/Twitter — build-in-public, daily.** The AI-coding corner of X (Claude
   Code power users, Cursor community, "vibe coding" discourse) is small,
   dense, and exactly the buyer. The overnight-receipt series above + replying
   with genuinely useful takes in every "I wish Claude Code could get a second
   opinion" thread. Founder account > brand account. This is the primary
   channel; everything else feeds it.
2. **Reddit — service first, tool second.** r/ClaudeAI, r/ChatGPTCoding,
   r/cursor, r/LocalLLaMA (adjacent), r/SideProject. Reddit torches self-promo
   but rewards useful field reports: "I ran the same spec past Claude, GPT and
   Grok as an adversarial panel — here's what each caught" is a great post that
   happens to mention the tool in a comment when asked. Budget: one high-effort
   post per sub per month, heavy comment presence.
3. **Hacker News — Show HN, timed for a story.** Don't launch on "multi-agent
   tool #47." Launch on the meta-story: "Show HN: Allnighter — my Mac app that
   lets my AI subscriptions work together overnight (it fixed its own bugs last
   night)." HN loves: local-first, no API keys, uses-what-you-own, honest proof
   surfaces, Swift/Mac craftsmanship. All of that is real. Have the receipts
   thread ready for the inevitable "does it actually work" comment.
4. **Product Hunt — second, not first.** PH is best after a small vocal user
   base to show up in comments. Good for the "$20/mo prosumer" audience; the
   no-API-keys angle demos well in the gallery video (screen recording of a
   real relay night, time-lapsed).
5. **Newsletters & podcasts — free if the story's good.** TLDR AI, Latent
   Space, Ben's Bites, How About Tomorrow / dev-adjacent pods. Pitch the story
   ("solo founder's app builds itself overnight using four rival AI models"),
   not the tool. One newsletter mention outperforms a month of Reddit.
6. **YouTube/Shorts — one honest time-lapse.** A single well-made "8 hours of
   overnight AI dev in 90 seconds" screen recording is endlessly re-postable
   across every channel above.

---

## 5. Early-user engine (before any "launch")

- **Concierge beta, 20–50 users,** hand-picked from X replies. People already
  complaining about exactly the problem ("juggling Claude and Cursor", "wish it
  kept going overnight"). DM them. Small enough to support personally; loud
  enough to seed launch-day social proof.
- **Make the first-run experience the referral.** CLI-setup/doctor work
  matters here: the distance from `brew install` → first successful relay night
  is the real conversion funnel. Every hour spent on that beats any outreach
  hour.
- **A "wall of nights" page.** Public, opt-in log of real overnight runs
  (models used, rounds, commits count). Social proof + FOMO + SEO in one
  static page.

---

## 6. The meta-move

Allnighter literally shipped a Growth team inside the product. Use Allnighter's
own Growth team to generate and pressure-test this playbook — then publish that
as content: "I asked my product's multi-model growth team how to market itself.
Here's the transcript." It's a demo, a dogfood receipt, and a marketing
artifact simultaneously. Recursive stunts travel on X/HN.

---

## 7. What to explicitly NOT do

- Paid ads, obviously — but also no generic "AI agent platform" language. The
  moment the copy sounds like a funded startup's landing page, the
  indie-credibility channels (the only channels) are lost.
- No launch before the receipts exist. One "it didn't work" HN comment with no
  counter-evidence kills a zero-budget launch.
- Don't spread across channels; X + one Reddit sub done daily beats six
  channels done weekly.

---

## Next (not in v0.1)

- Slice this into an experiment queue (hypothesis / cost / measurable signal
  per experiment) in house style.
- Run this brainstorm through Allnighter's own Growth team and compare —
  useful and postable.
