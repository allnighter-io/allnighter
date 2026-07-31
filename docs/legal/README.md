# Allnighter — Legal

Status: **Draft v1 — not yet reviewed by a lawyer, not yet accepted by any user**  
Owner: Founder  
Created: 2026-07-31

Public-facing legal surfaces for Allnighter. These are **drafts written by an
engineer, not legal advice.** Have a technology lawyer review both documents
before charging money (roughly one hour of their time; this is the cheapest
insurance available on the whole launch).

| Doc | Covers |
| --- | --- |
| [`EULA.md`](EULA.md) | Licence to use the software itself, restrictions, warranty, liability |
| [`Terms_of_Service.md`](Terms_of_Service.md) | Fees, trial, free core, third-party providers, privacy, termination |

## Fill these in before publishing

Every `[BRACKETED]` token below is a placeholder that must be replaced in both
documents before they go public.

| Token | Meaning |
| --- | --- |
| `[ENTITY]` | Legal entity name (sole proprietor name, LLC, etc.) |
| `[JURISDICTION]` | Governing law and venue |
| `[CONTACT_EMAIL]` | Support / legal contact |
| `[EFFECTIVE_DATE]` | Date first published |

## Acceptance gate — NOT BUILT

There is currently **no first-run acceptance flow** in the Mac app or CLI. No
user has agreed to anything. Unaccepted terms are close to worthless.

Required before charging:

- [ ] First-run acceptance in the Mac app: show the terms, record acceptance
      (version + timestamp) locally, block use until accepted
- [ ] CLI acceptance: `alln bootstrap` / first dispatch prints the terms URL and
      records acceptance; **must not** block discovery commands (menu, help,
      doctor, version, capacity) — same law as entitlement
- [ ] Checkout re-affirms acceptance at purchase (the legally strongest moment)
- [ ] Acceptance record carries the **document version**, so a future revision
      can be re-accepted rather than silently substituted
- [ ] Terms published at a stable public URL, versioned, with a change history

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
