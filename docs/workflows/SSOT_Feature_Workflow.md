# SSOT Feature Workflow

Use before planning any Allnighter feature, workflow, schema, WebSocket message,
agent driver, auth path, or UI state that carries product meaning.

## Product Unit

Allnighter ships trusted workflow slices.

A slice is valuable only when it includes:

- a user-visible claim;
- one truth owner;
- one Works Test or explicit proof waiver;
- generated artifacts updated from the source, if any;
- deletion targets for duplicate truth.

Example shape:

```text
enroll repo -> run council -> review master plan -> spawn lane work
```

MVP loop from `ALLNIGHTER.md`:

```text
enroll repo on Mac -> run council (parallel CLIs -> master plan) -> review on Mac
```

## Non-Negotiable Rule

Every semantic rule starts in an owning source of truth.

No durable product, permission, pairing, run, agent-driver, privacy, or
readiness rule may begin life only in:

- SwiftUI view code;
- prompt prose;
- docs;
- generated parser output;
- local fixture data;
- runtime heuristics.

## Deterministic Guardrail Rule

Recurring correctness questions should become deterministic checks: Swift types,
Codable schemas, parser tests, lint, fixture replay, XCTest, script, or CI gate.

Use agents for judgment-heavy work. Do not leave repeatable checks to model
judgment once the rule is known.

## Planning Order

1. Read `ALLNIGHTER.md`, `docs/mvp/README.md`, and `docs/WORKING_RULES.md`.
2. Translate founder/user input into a Feature Packet.
3. Identify the trusted workflow slice.
4. Name the truth owner.
5. Name affected models, WebSocket messages, Mac/iOS surfaces, parsers, and
   agent driver configs.
6. Define the user-visible claim.
7. Define the Works Test: setup, gesture, owner path, output, assertion.
8. Name supporting checks.
9. Name deletion targets for duplicate truth.
10. Name proof waiver only when proof cannot be built yet.

If the rule cannot be assigned to an owner, stop and fix the design.

## Feature Packet

```text
Allnighter Feature Packet

Status: Draft | Blocked | Ready for Implementation

Founder Intent
- Raw request:
- Product value:
- Trusted workflow slice:
- Non-goals:

Current State
- Existing truth owners:
- Existing models/API paths:
- Existing parsers/generated outputs:
- Existing UI surfaces:
- Existing tests/proof:

SSOT
- Truth owner:
- Lie-prone layers:
- New/changed semantic rules:
- Duplicate truth to delete:

Implementation
- Model/package impact:
- Mac app impact:
- iOS app impact:
- WebSocket/protocol impact:
- Agent driver impact:
- Auth/privacy/permissions impact:

Proof
- Works Test:
- User gesture:
- Fixture/scenario:
- Exact command:
- Missing proof / waiver:

Done When
- User-visible claim:
- Proof:
- Docs/logs:
```

## Inference Bans

For cross-layer features, add one row per layer junction.

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |

The ban should be specific enough to become a test or lint rule.
