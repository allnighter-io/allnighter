# SSOT Founder Input Workflow

Founder input is fast, valuable intent. It is not final semantic authority.

## Every Capability Is a CLI/MCP Contract First

Allnighter is agent-first: the `alln` CLI and the MCP tools ARE the product surface;
the GUI and iOS only *present* that contract. A feature is therefore not specced
until its CLI/MCP surface is specced alongside it. Never design a capability as
GUI-only with "wire up the CLI/MCP later" — that is exactly how the MCP surface fell
behind the app, and it must not recur. For every capability the packet must answer:
which `alln` command(s) and MCP tool(s) expose it, with what arguments, JSON output,
exit codes, and errors? If a capability has no CLI/MCP surface, the spec is
incomplete and cannot ship. (See the agent-first law in `AGENTS.md`: CLI, GUI, MCP,
and iOS share one contract, never parallel JSON.)

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
3. Define the CLI/MCP surface: name the `alln` command(s) and MCP tool(s) that
   expose the capability, with arguments, JSON shape, exit codes, and errors. The
   GUI/iOS present this contract; they never own a parallel one. A capability with
   no CLI/MCP surface is not ready to spec.
4. Classify risk: privacy, credentials, permissions, session data, destructive
   process control, distribution, cross-layer state.
5. Produce a Feature Packet or ordered slice list.
6. Name blocking questions only when they change semantics or risk.

## Default Output

```text
Founder intent:
Product value:
Trusted workflow slice:
Current state:
Truth owner:
CLI/MCP surface:
Proof scenario:
Blocking questions:
Next slice:
```
