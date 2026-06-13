# SSOT Founder Input Workflow

Founder input is fast, valuable intent. It is not final semantic authority.

## Founder Input May Define

- product value;
- workflow priority;
- taste and copy direction;
- examples and screenshots;
- constraints;
- what to investigate next.

## Founder Input May Not Directly Define

- durable data semantics;
- session lifecycle or persistence rules;
- device pairing or auth behavior;
- WebSocket message schemas;
- agent bridge contracts;
- permission or entitlement behavior;
- prompt-only product rules;
- UI-local durable truth.

If founder feedback requires new semantics, route it through
`Docs/workflows/SSOT_Feature_Workflow.md` before implementation.

## Passes

1. Read authority: `AGENTS.md`, product SSOT, relevant workflow/operation docs.
2. Inspect current state: what already exists, what owns it, what proves it.
3. Classify risk: privacy, credentials, permissions, session data, destructive
   process control, distribution, cross-layer state.
4. Produce a Feature Packet or ordered slice list.
5. Name blocking questions only when they change semantics or risk.

## Default Output

```text
Founder intent:
Product value:
Trusted workflow slice:
Current state:
Truth owner:
Proof scenario:
Blocking questions:
Next slice:
```
