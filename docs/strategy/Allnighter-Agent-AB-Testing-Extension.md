# Allnighter Agent A/B Testing Extension

**Later-stage strategy doc**  
June 12, 2026

> Status: Future extension, not MVP. This document maps the opportunity in full
> so the idea is preserved, but it should not expand the first Allnighter build
> scope. The core product still starts with lanes, races, teams, picker as
> prompt, previews, landing, and preference memory.

---

## 1. Executive Summary

Allnighter begins by learning from the founder's picks:

```text
Agents generate options
-> founder selects the best direction
-> selection becomes preference data
-> Allnighter learns the founder's taste and review
```

The A/B testing extension completes the loop by learning from the market's
picks:

```text
Agents generate variants
-> Allnighter implements them in isolated lanes
-> A/B platform routes real users to variants
-> behavior selects the winner
-> winner lands or rolls out
-> agent scorecards and taste models update
```

The combined thesis:

> Founder taste chooses what is worth testing. Market behavior chooses what
> actually works. Allnighter learns from both.

This creates a viral and strategically important future mode:

> Your AI workers do not just ship ideas. They compete in production.

---

## 2. Why This Is Later, Not MVP

This is a powerful extension, but it should not ship before the core factory is
working.

A/B testing adds several hard surfaces:

- feature flagging;
- traffic allocation;
- analytics ingestion;
- metric definition;
- statistical confidence;
- experiment safety;
- production rollout;
- false-positive control;
- privacy/compliance;
- attribution between agents and outcomes.

The core Allnighter MVP needs to prove:

- isolated lanes work;
- agents can create multiple drafts safely;
- previews and artifacts are useful;
- "Pick this and implement it" feels magical;
- landing can be trusted;
- preference events compound.

Only after that does it make sense to connect agent output to live market
experiments.

Recommended timing:

```text
After Allnighter Phase 20: Speculative Builds v0
and after the A/B testing app has stable flagging, metrics, and variant APIs.
```

---

## 3. Core Thesis

Allnighter creates an **agent option factory**.

The A/B testing app creates a **market selection engine**.

Together, they create an **autonomous experimentation team**:

1. Generate hypotheses.
2. Create multiple variants.
3. Implement each variant safely.
4. QA the variants.
5. Launch an experiment.
6. Monitor real behavior.
7. Promote winners.
8. Kill losers.
9. Learn which agents are good at which kind of outcome.

The defensible asset is not access to models. It is the data loop:

- which agent produced which variant;
- what the founder preferred;
- what users actually did;
- which metrics moved;
- which variant won;
- which worker should be trusted next time.

---

## 4. Viral Hook

The viral story is simple:

```text
We had Claude, Grok, and Codex compete on our signup page.
Grok won by +18%.
```

Variations:

- "Claude wrote the calm version. Grok wrote the punchy version. Users picked
  Grok."
- "Our AI growth team ran 12 onboarding tests while we slept."
- "Codex lost the copy test but won the implementation reliability score."
- "The model I personally liked lost to the market. Allnighter learned that."

This is shareable because it turns abstract model quality into visible business
outcomes.

The product should eventually make results easy to share:

- experiment result card;
- agent leaderboard;
- before/after screenshots;
- metric lift;
- attribution;
- "built by" labels;
- sanitized public recap.

---

## 5. Positioning

### 5.1 Extension Positioning

> Run a testing team of AI agents.

### 5.2 Supporting Lines

- "Let Claude, Grok, Codex, and local models compete on real conversion."
- "Your agents generate variants. Your users pick the winner."
- "Turn every product idea into a measured experiment."
- "Find out which agent is best at copy, onboarding, pricing, design, and
  implementation."
- "Founder taste starts the loop. Market behavior closes it."

### 5.3 Category

Agent-driven growth experimentation.

Not:

- generic A/B testing only;
- landing page builder only;
- analytics dashboard only;
- prompt comparison tool only.

---

## 6. The Strategic Flywheel

```text
Prompt
-> agent race/team
-> variants
-> implementation lanes
-> QA
-> experiment launch
-> user behavior
-> winner
-> landing/promotion
-> scorecard update
-> better routing next time
```

The long-term compounding data:

- founder preference graph;
- market response graph;
- agent capability graph;
- task-to-agent routing history;
- variant-to-outcome dataset;
- risk and rollback history.

Allnighter alone learns:

```text
What does this founder mean by good?
```

Allnighter plus A/B testing learns:

```text
What does this market reward, and which worker reliably produces it?
```

---

## 7. Product Architecture

### 7.1 System Roles

**Allnighter**

- receives product/growth goal;
- creates work orders;
- runs teams/races;
- creates implementation lanes;
- captures artifacts;
- runs QA;
- lands or opens PRs;
- records agent attribution;
- updates worker scorecards.

**A/B Testing App**

- owns experiments;
- owns flags/variants;
- routes traffic;
- collects events;
- calculates results;
- controls rollout;
- determines winners;
- exposes experiment APIs.

**Mac Runner**

- creates lanes and branches;
- implements variants;
- runs local preview and QA;
- prepares production-ready changes.

**iOS/Mac UI**

- captures experiment goals;
- shows variant previews;
- approves launch;
- monitors results;
- promotes winners;
- shows agent performance.

### 7.2 Integration Diagram

```text
User goal
  |
  v
Allnighter Team/Race
  |
  v
Variant Work Orders
  |
  v
Lane A / Lane B / Lane C
  |
  v
QA + Preview + Attribution
  |
  v
A/B App Experiment API
  |
  v
Traffic + Metrics
  |
  v
Winner Decision
  |
  v
Promote Variant + Update Agent Scorecards
```

### 7.3 Two Integration Modes

#### Mode A: Allnighter Generates, A/B App Runs

Allnighter creates variants and hands them to the A/B app for experiment setup.

Best for:

- keeping Allnighter focused;
- clear product boundaries;
- easier rollout;
- using the A/B app's existing flag/analytics engine.

#### Mode B: A/B App Requests Agents

The A/B app detects an opportunity and asks Allnighter for variants.

Best for:

- automated growth suggestions;
- experiment backlog generation;
- self-filling testing team.

Long-term, both modes should exist.

---

## 8. Core Workflow

### 8.1 Experiment Brief

User says:

```text
Improve signup conversion without changing pricing.
```

Allnighter turns it into:

```json
{
  "goal": "Improve signup conversion",
  "primary_metric": "signup_completed",
  "guardrails": [
    "Do not change pricing",
    "Do not remove SSO",
    "Do not touch billing code"
  ],
  "variant_count": 3,
  "eligible_agents": ["claude_code", "grok_build", "codex_cli"],
  "duration": "7 days or 1000 visitors",
  "minimum_effect": "5% relative lift"
}
```

### 8.2 Hypothesis Team

Agents propose hypotheses:

- reduce fields;
- improve headline;
- move social proof above form;
- add magic-link copy;
- create shorter onboarding path.

Team output:

- consensus opportunities;
- strongest dissent;
- expected risk;
- recommended variant set.

### 8.3 Variant Race

Allnighter dispatches:

- Claude: clarity-first variant;
- Grok: punchier copy/visual variant;
- Codex: conservative implementation/test-heavy variant;
- local model: extra copy or QA summary, if enabled.

Each variant gets:

- lane;
- branch;
- agent attribution;
- preview URL;
- screenshots;
- QA notes;
- test results.

### 8.4 Launch Review

User sees:

- Variant A preview;
- Variant B preview;
- Variant C preview;
- expected metric impact;
- risk tier;
- QA result;
- launch button.

Actions:

- launch all variants;
- pick subset;
- ask for one more variant;
- combine ideas;
- save for later;
- abandon.

### 8.5 Experiment Launch

A/B app receives:

- experiment metadata;
- variant ids;
- flag names;
- traffic allocation;
- primary metric;
- guardrail metrics;
- attribution data;
- rollback plan.

Example:

```json
{
  "experiment_id": "exp_signup_hero_2026_06",
  "project_id": "project_allnighter_site",
  "goal": "Improve signup conversion",
  "primary_metric": "signup_completed",
  "variants": [
    {
      "id": "variant_a",
      "lane_id": "lane_claude_clarity",
      "agent_id": "claude_code",
      "branch": "allnighter/signup-clarity/a17f9c"
    },
    {
      "id": "variant_b",
      "lane_id": "lane_grok_punchy",
      "agent_id": "grok_build",
      "branch": "allnighter/signup-punchy/b93d2e"
    }
  ],
  "traffic": {
    "control": 0.5,
    "variant_a": 0.25,
    "variant_b": 0.25
  }
}
```

### 8.6 Results

Morning Pull:

```text
Signup experiment has a likely winner.

Grok's punchy variant is up 14.8% on completed signup.
Claude's clarity variant is neutral.
No guardrail metric regression detected.

Promote Grok's variant?
```

Actions:

- promote winner;
- continue experiment;
- stop loser;
- ask agents to explain results;
- generate next round.

### 8.7 Learning Event

Allnighter records:

```json
{
  "event_type": "market_winner",
  "experiment_id": "exp_signup_hero_2026_06",
  "winner_agent_id": "grok_build",
  "winner_variant_id": "variant_b",
  "category": "signup_copy",
  "primary_metric_lift": 0.148,
  "guardrail_regressions": [],
  "founder_preferred_variant": "variant_a",
  "market_preferred_variant": "variant_b",
  "learning": "User preferred Claude's clarity, but market rewarded Grok's punchier emotional copy."
}
```

---

## 9. Use Cases

### 9.1 Landing Pages

Agents generate:

- headline variations;
- hero layouts;
- CTA copy;
- social proof placement;
- pricing card copy.

Metrics:

- signup click;
- demo request;
- purchase;
- scroll depth;
- bounce rate.

### 9.2 Onboarding

Agents generate:

- shorter flows;
- different first-run screens;
- alternate empty states;
- onboarding copy;
- checklist sequences.

Metrics:

- activation;
- first successful action;
- completion rate;
- time to value.

### 9.3 Pricing

Agents generate:

- page copy;
- plan framing;
- feature grouping;
- FAQ language;
- trial messaging.

Guardrails:

- do not change actual prices without explicit approval;
- do not alter billing logic;
- draft-only for payment code.

### 9.4 Ads and Creatives

Agents generate:

- ad copy;
- image prompts;
- landing page alignment;
- audience-specific hooks.

Metrics:

- CTR;
- CPC;
- conversion;
- downstream activation.

### 9.5 Email and Lifecycle

Agents generate:

- subject lines;
- onboarding emails;
- winback emails;
- upgrade nudges.

Metrics:

- open;
- click;
- conversion;
- unsubscribe.

### 9.6 App Store and Product Listings

Agents generate:

- subtitle options;
- screenshots;
- preview copy;
- release-note tones.

Metrics:

- listing conversion;
- install;
- retained users.

### 9.7 In-App UX

Agents generate:

- empty state copy;
- button labels;
- nav order;
- help text;
- upgrade prompts.

Metrics:

- feature adoption;
- conversion;
- task completion.

---

## 10. Agent Scorecards From Market Data

The extension should update scorecards with real performance:

| Dimension | Example |
| --- | --- |
| Signup conversion | Grok +14.8%, Claude neutral |
| Implementation reliability | Codex passed tests first 92% |
| Founder preference | Claude picked 60% of the time |
| Market preference | Grok won copy tests 55% |
| Risk | Agent X caused guardrail regressions twice |
| Time to variant | Local model fastest for copy drafts |
| QA quality | Claude caught more edge cases |

The important insight:

```text
Best model is not global. It is task-specific, product-specific, and metric-specific.
```

Future routing should be able to say:

```text
For onboarding copy, Grok has the best market win rate.
For implementation of the selected variant, Codex has the best landing rate.
For risk review, Claude has the best dissent quality.
```

---

## 11. Founder Taste vs Market Taste

The extension creates a useful tension:

```text
Founder liked A.
Market picked B.
```

This is not a failure. It is product intelligence.

Useful outputs:

- "You tend to prefer calmer copy; your market responds to more direct copy."
- "You usually pick visually polished variants; users convert on simpler ones."
- "Your instincts are strongest for UI structure, weaker for ad copy."
- "Claude matches your taste. Grok has won the market more often."

This can become one of the most valuable learning surfaces in the product.

---

## 12. Experiment Types

### 12.1 Founder-Picked Experiment

The user picks variants manually before launch.

Best for:

- high-risk changes;
- early trust;
- brand-sensitive surfaces.

### 12.2 Agent-Recommended Experiment

Team recommends variants and the user approves.

Best for:

- mature projects;
- clear metrics;
- moderate trust.

### 12.3 Autonomous Experiment Draft

Allnighter creates variants but does not launch without approval.

Best for:

- speculative growth work;
- Morning Pull ritual;
- high creativity.

### 12.4 Autonomous Experiment Launch

Allnighter creates, QA's, launches, monitors, and stops/promotes within
standing orders.

Best for:

- later stage only;
- low-risk copy/creative tests;
- high-trust accounts.

This should not exist in v1.

---

## 13. Safety and Guardrails

### 13.1 Product Guardrails

Examples:

- do not change pricing amount;
- do not touch billing code;
- do not alter privacy claims;
- do not change legal text;
- do not degrade accessibility;
- do not remove sign-in options;
- do not collect new personal data.

### 13.2 Metric Guardrails

Every experiment should support primary and guardrail metrics.

Example:

```text
Primary: completed signup
Guardrail: support tickets, refund requests, unsubscribe, crash rate
```

### 13.3 Rollback

Every experiment must have:

- flag off switch;
- rollback commit or branch;
- automatic stop conditions;
- owner notification.

### 13.4 Human Approval Levels

| Level | Behavior |
| --- | --- |
| Draft | agents prepare variants only |
| Approve launch | user approves before traffic |
| Approve promote | user approves winner promotion |
| Autonomous low-risk | system can launch/promote within standing orders |

Default:

```text
Approve launch + approve promote.
```

---

## 14. Statistical Discipline

This feature can become dangerous if it overclaims.

Requirements:

- label early results as directional;
- avoid declaring winners too soon;
- show sample size;
- show confidence or probability in plain language;
- support minimum experiment duration;
- protect against novelty spikes;
- allow guardrail metric veto;
- record inconclusive results as useful data.

User-facing language should be conservative:

Bad:

```text
Grok won.
```

Better:

```text
Grok's variant is currently ahead by 14.8%. Confidence is moderate. Continue
for 2 more days or promote now?
```

---

## 15. Data Model Sketch

### 15.1 Experiment

```json
{
  "id": "exp_signup_hero_2026_06",
  "project_id": "project_allnighter_site",
  "goal": "Improve signup conversion",
  "status": "running",
  "primary_metric": "signup_completed",
  "guardrail_metrics": ["refund_request", "support_ticket_created"],
  "created_from": "allnighter_council",
  "created_at": "2026-06-12T22:00:00Z"
}
```

### 15.2 Variant

```json
{
  "id": "variant_grok_punchy",
  "experiment_id": "exp_signup_hero_2026_06",
  "agent_id": "grok_build",
  "lane_id": "lane_b93d2e",
  "branch": "allnighter/signup-punchy/b93d2e",
  "hypothesis": "More direct, emotionally urgent copy will increase signup.",
  "status": "running",
  "traffic_allocation": 0.25
}
```

### 15.3 Result

```json
{
  "experiment_id": "exp_signup_hero_2026_06",
  "variant_id": "variant_grok_punchy",
  "metric": "signup_completed",
  "visitors": 1200,
  "conversions": 186,
  "conversion_rate": 0.155,
  "relative_lift": 0.148,
  "confidence_label": "moderate"
}
```

### 15.4 Agent Market Score Event

```json
{
  "agent_id": "grok_build",
  "project_id": "project_allnighter_site",
  "category": "signup_copy",
  "event_type": "market_win",
  "metric": "signup_completed",
  "relative_lift": 0.148,
  "confidence_label": "moderate",
  "created_at": "2026-06-20T12:00:00Z"
}
```

---

## 16. UI Concepts

### 16.1 Mac App

Mac should show experiment work like a lab bench:

- experiment backlog;
- variant lanes;
- preview grid;
- metric chart;
- agent attribution;
- launch checklist;
- rollout controls;
- result summary.

Mac is best for:

- comparing variants in detail;
- reviewing implementation risk;
- editing experiment config;
- inspecting analytics.

### 16.2 iOS App

iOS should show decision cards:

- "Approve launch?"
- "Variant B is ahead. Promote?"
- "Experiment is inconclusive. Run another generation?"
- "Guardrail regression detected. Stop?"

Morning Pull examples:

```text
Signup test update
Grok's punchy variant is ahead by 14.8%.
No guardrail regression detected.
Promote, continue, or ask for next generation?
```

```text
Agent scorecard changed
Grok is now your top worker for signup copy.
Claude remains best for architecture reviews.
```

---

## 17. Viral Surfaces

Later, add share cards:

```text
Agent Experiment Result

Goal: Improve signup conversion
Winner: Grok
Lift: +14.8%
Runner-up: Claude
Built by: Allnighter
```

Privacy rules:

- never expose repo names by default;
- redact screenshots unless user opts in;
- let user edit share text;
- show aggregate stats only if safe.

Possible public leaderboard:

- by anonymized task category;
- by agent;
- by metric type;
- opt-in only.

This could create organic distribution if handled carefully.

---

## 18. Build Phases

### Phase AB-0 - Contract Between Apps

Define:

- experiment API;
- variant schema;
- metric schema;
- agent attribution schema;
- result event schema.

### Phase AB-1 - Manual Variant Import

A/B app can import variants produced by Allnighter lanes.

Works Test:

```text
Allnighter creates two branches.
A/B app imports them as variants.
User launches experiment manually.
```

### Phase AB-2 - Agent-Generated Variant Race

Allnighter creates variants directly from an experiment brief.

Works Test:

```text
User asks for three signup variants.
Allnighter creates lanes and previews.
A/B app receives three launch-ready variants.
```

### Phase AB-3 - Result Feedback

A/B app sends winner/loser outcomes back to Allnighter.

Works Test:

```text
Experiment winner updates agent scorecards and preference history.
```

### Phase AB-4 - Morning Pull Integration

Experiment results become part of Allnighter's daily digest.

### Phase AB-5 - Agent Testing Team

Allnighter can run a bounded experiment cycle:

```text
goal -> variants -> QA -> launch approval -> monitor -> promote approval
```

### Phase AB-6 - Autonomous Low-Risk Experiments

Only after strong trust:

- copy-only experiments;
- no protected paths;
- small traffic allocation;
- automatic stop conditions;
- human promotion approval.

---

## 19. What Not To Build First

Do not start with:

- fully autonomous production experiments;
- complex Bayesian statistics UI;
- enterprise experimentation governance;
- multivariate testing;
- automatic pricing experiments;
- public model leaderboards;
- ad network automation;
- broad analytics replacement.

Start with:

```text
Allnighter-generated variants
-> A/B app runs test
-> result feeds agent scorecard
```

---

## 20. Recommendation

This is a major later extension and a natural companion to Allnighter.

It should be framed as:

> market-tested agent operations.

The first product earns trust by letting the founder pick and implement. The
extension earns compounding advantage by letting the market pick winners and by
teaching Allnighter which agents actually produce outcomes.

Do not add this to the core MVP. Do design the core data model so that future
preference events can include market outcomes:

```text
founder_pick
market_win
market_loss
guardrail_failure
experiment_inconclusive
promoted_winner
```

That one design choice keeps the door open without bloating the first build.

