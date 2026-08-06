# Bailian Token Plan Capacity

Status: **SPIKE — dogfood only (`--dogfood --source bailian_token_plan`)**
Owner: AllnighterCore (JSON API acquisition + parser) + AllnighterCLI (capacity +
`bailian-token-plan` setup)
Created: 2026-08-06

Origin: Founder dogfood — Alibaba Token Plan Personal (intl) quota exists only on
the Model Studio console, not in the inference API. Mirrors the OpenCode Go
capacity spike shape with a JSON gateway instead of HTML SSR.

Related: [`OpenCode_Go_Capacity.md`](OpenCode_Go_Capacity.md),
[`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md)

Prior art: [CodexBar Alibaba Token Plan](https://github.com/steipete/CodexBar/blob/main/docs/alibaba-token-plan.md) (Personal/Solo rolling-window API on `bailian-singapore-cs.alibabacloud.com`).

---

## Dogfood slice

```text
BAILIAN_TOKEN_PLAN_COOKIE (or encrypted file via configure)
  -> alln capacity --dogfood --refresh --source bailian_token_plan [--json]
  -> 7-day window required; 5-hour optional (limit-removed is explicit)
  -> or typed unknown + scrape diagnostics
```

**Without `--dogfood`:** `bailian_token_plan` is refused (`--dogfood required`).
The seat is **not** on `benchSourceOrder`.

## Setup

```text
# 1. Log into Token Plan Personal in Chrome
# 2. DevTools → Network → reload subscription page
# 3. Copy Cookie header from usage request to bailian-singapore-cs.alibabacloud.com
pbpaste | alln bailian-token-plan configure
alln bailian-token-plan status
alln capacity --dogfood --source bailian_token_plan --json
```

## Windows

| Console label | Scope | Notes |
| --- | --- | --- |
| 5-hour quota | `.fiveHour` when limited; omitted when "Limit Temporarily Removed" (strip `n/a`, same as Grok) |
| 7-day quota | `.weekly` | Required — whole sample fails without it |

## Code SSOT

- `BailianTokenPlanCapacityProbe.swift` — pure JSON parser
- `BailianTokenPlanCapacityClient.swift` — POST `IntlBroadScopeAspnGateway`
- `BailianTokenPlanCredentialStore.swift` — cookie env + AES-GCM file
- `BailianTokenPlanCapacityExecutor.swift` — orchestrator + qualification ledger
- `BailianTokenPlanCLI.swift` — `configure` / `status`

## Promotion gate (not started)

Same discipline as OpenCode Go: 14 days, 100 refreshes, 20 browser comparisons,
zero false numerics before bench inclusion.
