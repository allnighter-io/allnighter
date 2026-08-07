# CT-S01 — Completion-truth trio (poll / stall / foreign SSE)

Status: **done**
SSOT: [`OpenCode_Completion_Truth_Followup.md`](../../OpenCode_Completion_Truth_Followup.md) CT-01…03
Repo: **AgentOS** (`Sources/AgentOSCLI`)
Shipped: AgentOS commit (completion-truth trio + F8/F9/F10 polish in same tree)

## Goal

Long OpenCode turns must not fake-complete from HTTP poll, must stall on real quiet, and must not let foreign `:4096` traffic reset the watchdog or abort reconnect.

## Slice packet

```text
Slice: CT-S01
Goal: Fix CT-01 + CT-02 + CT-03 together (one reinforcing loop)
Out of scope: CT-04+, smoke kill, spawn poison, answerOnly, sibling lock, parentID probe
Truth owner: OpenCodeServeClient.pollSessionProgress + IdleGate.touch + OpenCodeSSEParser scoping + consumeSSEBus reconnect
Lie-prone layer: poll signal(clean) / blanket touch / foreign rawEvent progress / foreignIdle abort
Works Test: AgentOS unit filters below
Proof command: swift test --filter OpenCodeServeClientTests --filter OpenCodeSSEParserTests
Done when: new predicates green; foreign reconnect reaches local idle; committed in AgentOS
```

## Touch only

- `Sources/AgentOSCLI/OpenCodeServeClient.swift`
- `Sources/AgentOSCLI/OpenCodeSSEParser.swift`
- `Tests/AgentOSCLITests/OpenCodeServeClientTests.swift`
- `Tests/AgentOSCLITests/OpenCodeSSEParserTests.swift`

## Steps

1. Poll: `signal(clean:)` only when answer non-empty **and** latest assistant has `time.completed` (no running tools).
2. Poll: `touch()` only on real progress (new text, running tools, active children) — never on bare successful GET.
3. SSE: scoped parser yields no progress events for foreign `message.*` / unknown types; still record message map.
4. Reconnect: do **not** abort the loop solely because `foreignIdleDetected` latched.
5. Add unit proofs; run filtered tests; commit AgentOS.

## Works Test

```bash
cd /Users/mike/Documents/GitHub/AgentOS
swift test --filter OpenCodeServeClientTests
swift test --filter OpenCodeSSEParserTests
```

## Done when

- [x] CT-01/02/03 behaviors match SSOT proposed fixes
- [x] Filtered tests green
- [x] AgentOS commit landed
- [x] Follow-up doc marks CT-01…03 coded
