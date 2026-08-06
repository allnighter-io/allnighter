# Bailian Token Plan parser fixtures

Synthetic JSON fixtures for `BailianTokenPlanCapacityProbe` and the related
executor tests. Adapted from the public CodexBar fixture shape documented in
[steipete/CodexBar#2487](https://github.com/steipete/CodexBar/pull/2487).

**ORIGIN: SYNTHETIC** — hand-authored, NOT a captured page. No session cookies.

## Capturing a real fixture (founder-only)

1. Log into [Token Plan Personal (intl)](https://modelstudio.console.alibabacloud.com/ap-southeast-1?tab=plan#/efm/subscription/token-plan/personal)
2. DevTools → Network → reload → find `usage` request to `bailian-singapore-cs.alibabacloud.com`
3. Copy response body only; redact cookies and account identifiers
4. Store outside repo until reviewed; never commit raw captures automatically
