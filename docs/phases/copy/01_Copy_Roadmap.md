# 01 - Copy Roadmap

Status: Draft
Owner: Founder + Shared Core + Mac
Updated: 2026-06-15
Depends on: `00_Copy_MVP.md`

## Goal

Turn Copy from one landing-page MVP into a full lane of specialized copy types,
without making the user fill out forms.

The durable rule stays:

```text
Prompt required.
Copy type and Effort route the team.
Context is optional.
```

Vocabulary follows `docs/phases/Work_Order_Team_Model.md`: a team is a lineup of
workers, and each worker is one model wearing one skill.

## Product Value

Copy becomes great when the skill suite changes for the job:

- Landing page optimization is not an email funnel.
- Email funnels are not paid ads.
- Paid ads are not UGC scripts.
- UGC scripts are not lead magnets.
- Newsletters are not app store pages.

Each copy type should have its own skill suite, default team, optional context
chips, output shape, and quality rubric.

The roadmap is gated by quality, not by how easy it is to add another prompt
profile. A copy type does not become active until its board beats a strong
single-prompt baseline in founder dogfood.

## Copy Type Packs

`Copy type pack` is an internal planning term. The UI says `Copy type`.

Each pack defines:

- display name;
- prompt examples that auto-route to it;
- optional context chips;
- generation skills;
- review skills;
- default team lineup;
- effort mapping;
- output sections;
- Works Test.

### Landing Page Optimization

Purpose: rewrite a website/product page to convert a specific audience.

Optional context:

```text
URL | Current draft | Customer | Offer | Proof | Competitors | Brand voice
```

Outputs:

```text
hero variants
section-by-section rewrite
CTA set
objection coverage
claims/proof table
A/B test notes
implementation notes
```

### Email Funnel

Purpose: sequence several emails toward one conversion.

Optional context:

```text
Offer | List source | Audience stage | Sequence length | Send cadence | Proof
```

Outputs:

```text
sequence map
subject lines
preheaders
full emails
segmentation notes
follow-up variants
deliverability warnings
```

### Paid Ads

Purpose: generate high-converting ad angles and variants for a platform.

Optional context:

```text
Platform | Offer | Audience | Landing page | Policy constraints | Proof
```

Outputs:

```text
angle map
primary text variants
headlines
CTA variants
creative notes
policy-risk notes
test matrix
```

### UGC Script

Purpose: create short-form scripts that feel native to a creator and platform.

Optional context:

```text
Platform | Creator persona | Product demo | Length | Offer | Required disclosures
```

Outputs:

```text
hooks
script
shot list
b-roll notes
on-screen text
caption
retention beats
creator delivery notes
```

### Lead Magnet

Purpose: create a downloadable or interactive asset that attracts qualified leads.

Optional context:

```text
Audience | Pain | Desired lead quality | Offer bridge | Format | Proof
```

Outputs:

```text
lead magnet concept
title variants
outline
sample section
landing copy
delivery email
offer bridge
```

### Newsletter

Purpose: write useful recurring content that earns attention and trust.

Optional context:

```text
Audience | Topic | Point of view | Links/sources | Offer | Voice
```

Outputs:

```text
subject lines
lede variants
full issue
section headings
CTA
repurposed posts
source list
```

### App Store Page

Purpose: improve store listing conversion while staying platform-safe.

Optional context:

```text
App | Audience | Screenshots | Competitors | Keywords | Proof
```

Outputs:

```text
title/subtitle variants
description
keyword notes
what's new
screenshot caption ideas
review-response notes
```

### SEO / Blog

Purpose: create search-aware content without flattening the product voice.

Optional context:

```text
Keyword | Audience | Search intent | Sources | Product tie-in | Brand voice
```

Outputs:

```text
angle
outline
full draft
title/meta variants
internal-link notes
evidence/source list
product CTA
```

### Sales Page

Purpose: long-form persuasion for a paid offer.

Optional context:

```text
Offer | Audience | Price | Proof | Objections | Guarantee | Scarcity/urgency
```

Outputs:

```text
offer framing
long-form sales copy
proof stack
FAQ/objections
CTA blocks
risk reversal
```

## Effort by Copy Type

Effort stays simple in the UI:

```text
Quick | Standard | Deep
```

Internal examples:

| Type | Quick | Standard | Deep |
| --- | --- | --- | --- |
| Landing page | 2 versions | 4 versions + light objection review | 6 versions + research + proof review |
| Email funnel | 1 short sequence | 1 full sequence + subject variants | 2 sequences + segmentation/rebuttal review |
| Ads | 6 variants | 12 variants across angles | angle research + platform-risk review |
| UGC | 2 scripts | 4 scripts + shot notes | 6 scripts + retention/disclosure review |
| Newsletter | 1 issue | 1 issue + subject/lede variants | research-backed issue + repurposing pack |

These are work-shape defaults only. They are not forecasts.

## Research

Research should make Copy meaningfully better, but it must stay honest and visible.

Research sources:

- public competitor pages;
- public reviews/testimonials;
- public forums/social posts when permitted by the worker/tool;
- user's attached URLs;
- user's attached docs/files;
- local run history and selected prior copy.

Rules:

- Show research as plain text in the work order summary, e.g.
  `6 versions - UGC scripts - web research`.
- Save sources with the run.
- Keep source snippets bounded.
- Do not send private repo files, credentials, customer data, or unpublished
  context to public research unless the user selected it for this run.
- A model/source without browsing can still run writing or review workers.

Research is a future slice, not C0. Do not imply web research in the MVP summary
until source capture and source viewing exist.

## Memory

Later Copy should compound:

- house voice;
- banned phrases;
- banned claims;
- proof assets that are safe to reuse;
- audience notes;
- picked/rejected hooks;
- copy type defaults;
- worker scorecards by copy type.

Memory is local by default. It should be visible and editable before it changes a
run.

Near-term memory starts as pick/reject history from C0. House voice and banned
claims come later, after the user can see and remove the memory chips that will
steer a run.

## Apply / Ship

Copy can feed Build, but it should not become a site editor too early.

Later handoffs:

- apply picked landing-page copy to an existing file through Build;
- export email sequence as Markdown/CSV;
- export ad variants as CSV;
- export UGC scripts as a production sheet;
- create a design request from copy, e.g. "make a hero for this page";
- create a campaign pack that includes Build, Design, and Copy turns.

The first apply-to-site path should reuse Build: selected copy plus target files,
then a coding agent edits the existing page.

This is the first fast follow after C0. See `02_Copy_Apply_To_Site.md`. It should
ship before a long tail of copy types, because it is what makes Copy belong inside
Allnighter instead of a separate writing surface.

## Campaign Run

Longer term, Copy is one part of a campaign:

```text
Launch this feature
-> Build: implementation/spec
-> Design: screen/hero/mockups
-> Copy: landing page, announcement, emails, ads
-> Review: consistency, claims, proof
-> Ship pack
```

This should remain an advanced work order, not the default first-run path.

## Ordered Roadmap

- [ ] C1 - Copy MVP: landing page board and copy pack (`00_Copy_MVP.md`).
- [ ] C2 - Apply-to-site via Build (`02_Copy_Apply_To_Site.md`).
- [ ] C3 - Copy type registry: internal model for packs, auto-route examples,
  optional context chips, skill suites, default teams, output schemas.
- [ ] C4 - Email funnel and ads packs.
- [ ] C5 - Research source capture and source browser.
- [ ] C6 - House voice and copy memory.
- [ ] C7 - UGC script and lead magnet packs.
- [ ] C8 - Newsletter, app store, SEO/blog, sales page packs.
- [ ] C9 - Campaign run: Build + Design + Copy.

## Avoid / Discard

- Do not add a fourth peer composer lane for research, legal, SEO, sales, or
  scripts. They are types or presets inside Build/Design/Copy.
- Do not ship half-built copy type chips.
- Do not add Mailchimp, Meta Ads, Webflow, CMS, or auto-publish integrations in
  this roadmap.
- Do not let Allnighter directly rewrite ASTs, localization files, or constants.
  Use Build handoff so the code agent edits selected files under the existing
  repo safety rules.
- Do not silently scan the whole repo to invent product claims. Source context
  must be user-selected or explicitly routed by a future source-scan slice.
- Do not use new paid APIs or BYOK as the default path. Copy continues the
  subscription-CLI, zero-marginal-cost posture.

## Works Tests

Each copy type needs one owner-visible Works Test. Examples:

```text
/copy email
Prompt: Write a 5-email onboarding sequence for a trial user who created a
project but has not invited a teammate.
Effort: Standard
Expected: sequence map, subjects, preheaders, full emails, segmentation notes.
```

```text
/copy ugc
Prompt: Create TikTok scripts for a Mac app that runs AI agents overnight.
Effort: Standard
Expected: hooks, scripts, shot list, on-screen text, captions, disclosure notes.
```

```text
/copy ads
Prompt: Generate Meta ad angles for a $29/month AI-agent productivity app.
Effort: Deep
Expected: angle map, variants, CTA, creative notes, platform-risk notes.
```

## Done When

- Copy type packs can be added without changing the composer surface.
- Copy type packs define skills and default teams using the shared team model.
- Each pack has a specific output shape and Works Test.
- Effort stays Quick / Standard / Deep in the UI.
- Optional context stays optional.
- Research is visible and source-saved.
- Pick/reject events feed local copy memory.
- Selected copy can hand off to Build without copy/paste.
