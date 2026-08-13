# Trial & Entitlement

Status: **V1 SHIPPED — public 1.1.3 (2026-08-13)**  
Owner: pay Worker + Core gate + `alln billing`  
Offer SSOT: `docs/marketing/Pricing_Recommendation.md` v4  
Standing law: `docs/operations/Project_Laws.md` §Entitlement  
Vocab: `docs/workflows/Product_Vocabulary.md` §Trial, pay, Keep going

Ephemeral packet. V1 buy path is live. Closeout remaining: terms-acceptance
recording + cross-machine sync, then archive. Do not relitigate the buy path.

---

## The buy path (founder-locked 2026-08-13)

**Stripe Checkout with email. Sign in with Apple is not part of it.**

SIWA stays for iPhone pairing later, not the cash register. Apple also forbids SIWA on Developer ID, so the website DMG cannot use it anyway.

Stranger flow:

1. Install CLI or DMG. No account.
2. First **run** starts a 14-day unlimited trial (server clock). A run is `alln run`, `alln loop start`, or hitting Run in the Mac app. Looking at capacity, help, doctor, or billing does **not** count.
3. After trial: 3 of those runs per day.
4. Cap or `alln billing` → one hosted Stripe Checkout URL (monthly / yearly / founding).
5. Pay. Stripe has email. Webhook marks paid.
6. CLI/app refreshes entitlement. No Apple ID, no license-key paste, no IAP.

## Offer (do not edit numbers here)

| Tier | Price | Dispatch |
| --- | --- | --- |
| Free forever | $0 | 3/day, full product |
| Trial | $0, 14 calendar days | Unlimited. Starts at **first run**, not install |
| Builder | $8/mo or $80/yr | Unlimited |
| Founding Builder | $160 once, first 100 | Unlimited, then retired |

Meter: dispatch only (`alln run`, `loop start`, any worker spawn). A loop counts **once at start**. In-flight runs are never killed. Discovery (`menu`, `help`, `doctor`, `billing`) is free forever.

Degrade never bricks: server down → 72h provisional trial, then local 3/day.

## Identity

Checkout is bound to a **machine hash**: HMAC-SHA256 over IOKit `IOPlatformUUID` with a compiled-in salt. The raw UUID never leaves the machine.

Stripe `client_reference_id` = that hash. Email lives on the Stripe customer for receipts. Cross-machine sync is a follow-up.

Residual accepted: VM / hardware spoof. No DRM arms race.

Reinstall must **not** mint a new 14-day trial (server `trial_started_at`, earliest wins). The local daily 3-count may reset on reinstall — accepted for V1.

## Surfaces

- Worker: `infra/pay/` at `https://pay.allnighter.io` (override `ALLN_ENTITLEMENT_BASE_URL`). D1. **Not** mixed into `get-faucet`.
- `POST /v1/status` `{ machineHash }` — upsert; set `trial_started_at` if null; return plan/trial.
- `POST /v1/checkout` `{ machineHash, plan }` — Stripe Checkout session.
- `POST /v1/webhook` — `checkout.session.completed` → paid plan. Founding: refuse checkout if ≥ 100 sold.
- CLI: `alln billing [--json]`, `alln billing checkout --plan monthly|yearly|founding [--json]`.
- Menu: optional `entitlement` sibling of `update`. Omit when skipped.
- Dispatch admission: `RunService.run` (one call site). Loop start admits once, then `EntitlementAdmission.skipInnerDispatch` so rounds do not count again.
- Failure: `ENTITLEMENT_LIMIT`. `message` and `tellHuman` are the same verbatim paragraph for the human. Agents quote it; they do not paraphrase. `nextAction.command` is compiled-in `alln billing checkout --plan monthly --json` — **never** a Stripe URL in a field an agent will exec (law 9). Human opens the `url` field.
- Mac: Keep going overlay on the blocked 4th Run; Settings › Plan; quiet title-bar chip (last 3 trial days or out of runs). Copy SSOT: `EntitlementCopy` / `EntitlementChrome`.
- Token: `~/Library/Application Support/Allnighter/Entitlement/state.json`, **0600, never Keychain** (BUG-9).
- XCTest host and `ALLN_NO_ENTITLEMENT_CHECK=1` skip HTTP (Green Wall).

## Do not

- Require Sign in with Apple to buy.
- Put a Stripe URL in `nextAction.command`.
- Serve billing from `get.allnighter.io`.
- Use xterminal’s Stripe Keychain item (`xterminal.live_mode_api_key`).
- Hit live Stripe from tests.
- Kill an in-flight run on expiry.

## Live (2026-08-13)

Public floor: CLI + Mac **1.1.3** on `get.allnighter.io`. Pay Worker:
`https://pay.allnighter.io` against **Allnighter live** Stripe (not sandbox,
not xterminal). Checkout sessions are `cs_live_`. Webhook:
`POST /v1/webhook`. Strangers install from allnighter.io, then pay from the
product. There is no website Buy button.

## Remaining (not V1 blockers)

- Stripe Dashboard: Checkout **legal policies consent** (ToS + Privacy URLs)
  if not already on.
- Record terms acceptance (version + timestamp) at first Mac run / CLI first
  dispatch. Must not block discovery commands. See `docs/legal/README.md`.
- Cross-machine sync (email on the Stripe customer; V1 is machine-hash only).

## Code SSOT

`Entitlement.swift`, `BillingCLI.swift`, `RunService.run`, `infra/pay/src/index.ts`.
