# Allnighter — Legal

Status: **Published v1.1 — effective August 12, 2026**  
Entity: Happy Moose Apps Inc. (British Columbia, Canada)  
Contact: support@allnighter.io  
Created: 2026-07-31 · Published: 2026-08-07 · Revised: 2026-08-12 (v1.1 — drop Aider; iOS is when-available)

Public-facing legal surfaces for Allnighter. These four documents are the source
of truth; the pages on allnighter.io are rendered from them and must be
regenerated whenever a document here changes.

| Doc | Covers | Public URL |
| --- | --- | --- |
| [`Terms_of_Service.md`](Terms_of_Service.md) | Fees, trial, free tier, third-party providers, termination | `/terms` |
| [`EULA.md`](EULA.md) | Licence to use the software, restrictions, warranty, liability | `/terms#eula` |
| [`Privacy_Policy.md`](Privacy_Policy.md) | What we collect, processors, retention, your rights | `/privacy` |
| [`Refund_and_Cancellation_Policy.md`](Refund_and_Cancellation_Policy.md) | Refunds, cancellation, renewal, trial terms | `/refunds` |

All `[BRACKETED]` placeholders are filled. If you add a document, check it for
`[ENTITY]`, `[JURISDICTION]`, `[CONTACT_EMAIL]`, and `[EFFECTIVE_DATE]` before
it goes public.

## Keeping the site in sync

The website lives in a separate repo (`Ikiro/allnighter`) and holds a rendered
HTML copy of each document. There is no automated pipeline — editing a Markdown
file here does **not** update the site. After any change:

1. Edit the Markdown here.
2. Bump the version and effective date at the top of the changed document.
3. Mirror the change into the matching `content/*.html` page in the site repo.
4. Commit both, and push the site repo to publish.

## Stripe requirements

Stripe reviews merchant websites against its
[website checklist](https://docs.stripe.com/get-started/checklist/website).
What that checklist asks for, and where it now lives:

| Requirement | Where |
| --- | --- |
| Description of what you're selling | Homepage |
| Purchase currency, explicitly | Homepage pricing, ToS §3, refund policy |
| Customer service contact | Footer of every page, all four documents |
| Refund policy | `/refunds`, ToS §3 |
| Cancellation policy | `/refunds`, ToS §3 |
| Trial / promotion terms | Homepage, `/refunds`, ToS §2 |
| Privacy policy | `/privacy` |
| Payment security and PCI | ToS §3, Privacy §5 and §9, homepage pricing note |
| Shipping and returns | N/A — downloadable software, no fulfillment process |
| Business address | Not published. Given to Stripe privately for KYC. |

Set the **Terms of service URL** (`/terms`) and **Privacy policy URL**
(`/privacy`) in Stripe's business public details, and enable Checkout's legal
policies consent so acceptance is recorded at purchase.

## Acceptance gate — PARTIALLY BUILT

Terms are now published at stable public URLs, which is the prerequisite. What
remains is recording that a specific user accepted a specific version:

- [x] Terms published at stable public URLs, versioned, with an effective date
- [ ] Checkout re-affirms acceptance at purchase (the legally strongest moment)
      — Stripe Checkout consent collection does this; enable it when payments go
      live
- [ ] First-run acceptance in the Mac app: show the terms, record acceptance
      (version + timestamp) locally, block use until accepted
- [ ] CLI acceptance: `alln bootstrap` / first dispatch prints the terms URL and
      records acceptance; **must not** block discovery commands (menu, help,
      doctor, version, capacity) — same law as entitlement
- [ ] Acceptance record carries the **document version**, so a future revision
      can be re-accepted rather than silently substituted

Build it in the entitlement sibling packet (`docs/phases/One_Paste_Cold_Start.md`
§Trial → `Trial_And_Entitlement.md`); it lands naturally alongside the first
dispatch admission check.

## The compliance position (why we believe we can charge)

Load-bearing, and true by architecture — not by disclaimer:

1. **We never see provider credentials.** Allnighter spawns the vendor's own CLI,
   which authenticates itself with the user's own login. We do not read, store,
   proxy, extract, or transmit provider tokens. We never touch OAuth flows.
2. **We provide no model access.** No API keys, no BYOK, no pooled accounts, no
   resale. The user brings their own subscriptions.
3. **We use vendor-supported interfaces.** Headless/non-interactive CLI modes are
   first-party supported features.
4. **We do not circumvent limits.** We read what a CLI reports and route around a
   wall; we never defeat one.

These four facts are also the marketing claim. Keep them true in code
(`AGENTS.md` project laws already forbid API keys/BYOK and hidden credential
handling), and keep the copy free of anything implying circumvention — see
`docs/marketing/Pricing_Recommendation.md` §Claim Discipline.

A disclaimer does **not** make a terms violation lawful; it allocates risk
between us and our users. The architecture above is what actually keeps us on the
right side of the line.
