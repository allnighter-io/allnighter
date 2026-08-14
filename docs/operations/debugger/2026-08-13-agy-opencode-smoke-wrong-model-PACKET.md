# 2026-08-13 — AGY / OpenCode smoke benches a working CLI

```text
Tier: T2 SSOT
Symptom / repro: Signed DMG / allapp rebuild → Find my team / Re-check.
  Antigravity: probeFailed "Individual quota reached … Resets in 76h…"
  while Gemini pool still has capacity. Fixed in attempt 1; confirmed after
  local allapp rebuild.
  OpenCode: still probeFailed HTTP 500 UnknownError (ref err_7a20b2d7)
  while `opencode` 1.18.18 is installed and Go is connected.
Bug fingerprint (attempt 2):
  OpenCode smoke always pins `opencode/big-pickle` (Zen). This Mac’s
  auth.json keys are `opencode-go` only. Serve GET /config/providers
  advertises `opencode-go` + `ollama`, not Zen. POST wraps
  ProviderModelNotFoundError: "Model not found: opencode/big-pickle"
  as HTTP 500 UnknownError.
  (Attempt 1 recycled serve for zen smoke; that was not this 500.)
Truth owner:
  ModelCatalog.probeModelLabel (opencode → Go flash when
  OpenCodeModelGate.isGoConnected(), else zen big-pickle)
Lie-prone layer: driver-level probeFailed from one model's smoke.
Attempt count: 2
Seam: setup smoke model pick → CLIDetector.smokeClassify → Setup Needs Attention
Isolation harness: n/a — primitive already observed (serve log +
  GET /config/providers). Same class as AGY pin, not a third in-place guess.
Missing kill test / proof: named below
Fix boundary: pin OpenCode smoke to a model this serve has. No new probe status.
  Do not POST a live Go/zen smoke from tests.
Proof command:
  scripts/swift-test.sh --filter 'ModelCatalogTests/testOpenCodeProbeUsesGoFlashWhenGoConnected|ModelCatalogTests/testOpenCodeProbeUsesZenBigPickleNotGoCapacityLabel|SetupRecoveryCopyTests/testAttentionDetailSurfacesOpenCodeBadModel'
```
