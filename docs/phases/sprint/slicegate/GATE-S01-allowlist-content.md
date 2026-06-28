# GATE-S01 — SliceGate allowlist content + check.method validation

Status: **done**
Source: [`code_review/triage/CR-03-findings.md`](../../code_review/triage/CR-03-findings.md) (P1)

## Goal

Reject empty/whitespace `touchAllowlist` entries (e.g. `[""]`) and fail closed on
unknown `check.method` values instead of silently skipping validation.

## Copy-paste prompt

```text
You are implementing sprint work order GATE-S01 ONLY.

Read ONLY:
- docs/phases/sprint/slicegate/GATE-S01-allowlist-content.md
- Packages/AllnighterCore/Sources/AllnighterEngine/SliceGate.swift

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/SliceGate.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/SliceGateTests.swift (extend)

Fix touchAllowlist: require at least one non-empty trimmed path after normalization.
Fix check.method: replace `default: break` with fail-closed rejection for unknown methods.

Proof: swift test --package-path Packages/AllnighterCore --filter SliceGate
```

## Read only

- `SliceGate.swift` (`validate` / allowlist branch)

## Touch only

- `SliceGate.swift`
- `SliceGateTests.swift`

## Steps

1. Trim and filter allowlist entries; fail if none remain.
2. Enumerate known check methods; `default` → validation failure with reason.
3. Tests: `[""]` fails; unknown method fails; valid packet still passes.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter SliceGate
```

## Done when

- [x] Empty allowlist entries cannot pass gate
- [x] Unknown check methods rejected
- [x] No scope creep into PairCoordinator
