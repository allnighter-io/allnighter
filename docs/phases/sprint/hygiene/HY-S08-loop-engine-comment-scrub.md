# HY-S08 — Loop engine comment scrub (PM Relay → Loop)

Status: ready
Owner: hygiene / comment truth
Updated: 2026-08-03

## Goal

More Core/Engine loop files: comment prose `PM Relay` → `Loop` where teaching
product vocabulary. **Comments only — no symbol or string literal changes.**

## Copy-paste prompt

```text
Implement HY-S08 only.

Touch ONLY // and /// comments in:
- Packages/AllnighterCore/Sources/AllnighterCLI/LoopDispatch.swift
- Packages/AllnighterCore/Sources/AllnighterEngine/LoopCoordinator.swift
- Packages/AllnighterCore/Sources/AllnighterEngine/LoopThreadProjector.swift
- Packages/AllnighterCore/Sources/AllnighterCore/HandoverGate.swift
- Packages/AllnighterCore/Sources/AllnighterCore/LoopVerdict.swift
- Packages/AllnighterCore/Sources/AllnighterEngine/LoopTurnClassifier.swift

In comments: "PM Relay" → "Loop" (product noun). Keep archive doc path refs
(PM_Relay.md) where citing historical packets.

Do NOT touch LoopPrompts.swift (live prompt headers — separate slice).

Proof: scripts/swift-test.sh --filter RetiredVocabulary

Commit only listed files.
Message: docs(swift): loop engine comment scrub PM Relay → Loop
```

## Works Test

```text
scripts/swift-test.sh --filter RetiredVocabulary
```
