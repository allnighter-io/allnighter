# Keep Going — Brief

**Tier:** D
**Visual kit:** midnight overlay (in-window card + scrim), not a separate OS sheet
**Behavioral owner:** `docs/phases/Trial_And_Entitlement.md` + `EntitlementCopy` / `EntitlementChrome`

## Purpose

Convert at the blocked 4th run. Settings › Plan is the honest destination if someone goes looking. The title bar stays quiet except the last 3 trial days or when today's three are used.

CLI agents must quote `tellHuman` to the human — they cannot paraphrase a JSON error.

## States

idle — paid, early trial, or free with runs remaining: no chip, no overlay.

trialEnding — ≤3 calendar days left: quiet title-bar chip `Trial · N days left`. Tap opens Settings › Plan.

capped — 0 runs left today: title-bar chip `Keep going`. Blocked Run opens the overlay.

checkoutBusy — primary button reads Opening… while Stripe Checkout is requested.

checkoutError — failure copy on the overlay; overlay stays open.

paid — chip gone, Plan row reads Builder / yearly / Founding Builder, no upgrade CTA.

## Intents

- Blocked Run → `RunService` `ENTITLEMENT_LIMIT` → overlay (Mac) or `tellHuman` + `nextAction.command` (CLI).
- Keep going — $8/month → `EntitlementGate.checkoutJSON(.monthly)` → `NSWorkspace.open` (human click). Never a Stripe URL in a command field.
- $80/year / Founding → same checkout with `.yearly` / `.founding`.
- Not now → dismiss overlay. User message stays. Assistant turn is the headline only.
- Plan chip / Settings › Plan → `PlanSettingsView` bound to `BillingJSON`.

## Field Ownership Ledger

| GUI field | Core model field | Source | States | Test owner |
| --- | --- | --- | --- | --- |
| Overlay headline | `EntitlementCopy.dailyCapHeadline` | Core copy SSOT | capped | EntitlementPresentationTests |
| Overlay body | `EntitlementCopy.dailyCapBody` | Core | capped | EntitlementPresentationTests |
| Primary button | `EntitlementCopy.keepGoingButton` | Core | capped | EntitlementPresentationTests |
| Title-bar chip | `EntitlementChrome.headerChip` | `BillingJSON` | trialEnding, capped | EntitlementPresentationTests |
| Settings › Plan subtitle | `EntitlementChrome.planRow.subtitle` | `BillingJSON` | all | EntitlementPresentationTests |
| CLI `tellHuman` | `ErrorEnvelope.tellHuman` / `BillingJSON.tellHuman` | Core | ENTITLEMENT_LIMIT, at-cap status, checkout | EntitlementGateTests + EntitlementPresentationTests |
| `nextAction.command` | `EntitlementPolicy.checkoutCommand` | compiled-in | ENTITLEMENT_LIMIT | EntitlementGateTests |

Do not invent a GUI-only plan name. Do not say Upgrade App. Do not feature-lock copy.
