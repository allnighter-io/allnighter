# HY-S03 — Help: remove false `loop step --no-wait` teaching

Status: ready (queue after HY-S01)
Owner: hygiene / agent-facing help fidelity
Updated: 2026-08-03

## Goal

Help must not teach `loop step --no-wait` — that flag does not exist in the
locked v7 loop grammar. Long-job guidance should point to `loop wait` /
`loop status --wait-for parked` and `--no-wait` on `loop start` / `resume` / `pm`.

## Copy-paste prompt

```text
You are implementing sprint HY-S03 only. Read this file and the allowlist.

Goal: Remove teaching of `loop step --no-wait` from HelpTopicRegistry loop help.
`alln loop step` has NO --no-wait flag (locked v7 grammar).

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterCore/HelpTopicRegistry.swift

Find the `loop` help topic (topicId related to loop / relay). In prose strings
ONLY (not aliases like "no-wait" search aliases — those can stay for discovery):

WRONG (remove/replace):
- "prefer `step --no-wait`"
- "Long jobs: `step --no-wait`"

RIGHT (use instead):
- After `loop step`, wait with `loop wait <loop-id>` OR
  `loop status <loop-id> --wait-for parked` to receive the pmTurn.
- For unattended dispatch, `--no-wait` applies to `loop start`, `loop resume`,
  and `loop pm` — NOT to `loop step`.

Also in the "notify" section string: "PM Relay needs an answer" → "Loop needs
an answer" (product noun is Loop, not PM Relay).

Do NOT edit ContractRegistry, generated JSON, tests unless a test asserts the
old false string. Do NOT rename types or symbols.

Works Test:
scripts/swift-test.sh --filter HelpTopicRegistry

Commit:
git add Packages/AllnighterCore/Sources/AllnighterCore/HelpTopicRegistry.swift
git commit -m "help: stop teaching loop step --no-wait; use loop wait/status"
```

## Read only

- This file
- `docs/workflows/Product_Vocabulary.md` — §Loop grammar
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/CompletionDeliveryWorksTests.swift:69-74` — locked grammar note

## Touch only

- `Packages/AllnighterCore/Sources/AllnighterCore/HelpTopicRegistry.swift`

## Do not read / do not touch

- `ContractRegistry+Milestone1.swift` (HY-S04)
- Generated `docs/generated/`
- GUI, LoopEngineCLI.swift

## Steps

1. Open HelpTopicRegistry; locate loop topic prose (main body + caller-pm section).
2. Replace false `step --no-wait` guidance per prompt above.
3. Fix notify section "PM Relay" → "Loop" in user-visible notification description.
4. Run Works Test; fix any failing assertion if it pinned old prose.
5. Commit one file (or + test file if needed).

## Works Test

```text
scripts/swift-test.sh --filter HelpTopicRegistry
```

## Done when

- [ ] No help prose teaches `loop step --no-wait`
- [ ] Long-job path documents `loop wait` / `status --wait-for parked`
- [ ] Notify section says Loop, not PM Relay
- [ ] HelpTopicRegistry tests green
- [ ] One commit

## SSOT

`docs/phases/One_Run_Surface.md` known follow-up; `Product_Vocabulary.md` loop grammar.
