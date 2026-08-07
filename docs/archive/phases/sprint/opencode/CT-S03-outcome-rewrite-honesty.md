# CT-S03 — Outcome rewrite must not clobber classified failures

Status: **in_progress**
SSOT: [`OpenCode_Completion_Truth_Followup.md`](../../OpenCode_Completion_Truth_Followup.md) CT-04 + CT-13
Repo: **Allnighter**

## Goal

Permission / session / prompt failures stay visible after `OpenCodeOutcomeAuthority` rewrite; idle vs promptEcho precedence matches AgentOS `emitTerminal`.

## Touch only

- `Packages/AllnighterCore/Sources/AllnighterEngine/OpenCodeOutcomeAuthority.swift`
- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift` (pass existing kind/reason)
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/OpenCodeOutcomeAuthorityTests.swift`

## Works Test

```bash
scripts/swift-test.sh --filter OpenCodeOutcomeAuthorityTests
```
