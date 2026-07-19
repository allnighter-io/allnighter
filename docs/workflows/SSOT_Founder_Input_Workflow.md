# SSOT Founder Input Workflow

Founder input is fast, valuable intent. It is not final semantic authority.

## Every Capability Is a CLI Contract First

Allnighter is agent-first: the `alln` CLI IS the product surface (MCP was retired
2026-07-16, see archived `docs/archive/phases/MCP_Retirement.md` — the CLI is the
only agent surface now); the GUI and iOS only *present* that contract. A feature
is therefore not specced until its CLI surface is specced alongside it. Never
design a capability as GUI-only with "wire up the CLI later" — that is exactly
how the old MCP surface fell behind the app, and it must not recur. For every
capability the packet must answer: which `alln` command(s) expose it, with what
arguments, JSON output, exit codes, and errors? If a capability has no CLI
surface, the spec is incomplete and cannot ship. (See the agent-first law in
`AGENTS.md`: CLI, GUI, and iOS share one contract, never parallel JSON.)

## Agent-facing help is part of the capability (not optional polish)

Shipping a CLI verb without updating the **live help corpus** is the same class
of bug as shipping GUI-only truth. Agents read `alln help search` / `help get`
and living ops playbooks before they read phase archives.

For every CLI capability change, the packet / closeout must also answer:

- which `HelpTopicRegistry` topic(s) teach this surface?
- do those topics name only flags/commands that resolve in `ContractRegistry`?
- does `help search "<obvious synonym>"` hit them (driver names, model family
  names, job phrases)?
- if search misses, is recovery non-empty (`nextToolPlan` → models / teams /
  doctor / hello --for)?

If those answers are missing, the feature is not ready to close — same bar as
"no CLI surface."

Active polish phase: `docs/phases/CLI_Agent_Surface_Fidelity.md` (ASF).

## Why help/doc drift was still possible (2026-07-20 lesson)

**It was not because we never bumped `binaryVersion`.** Version and docs sync
are separate machines:

| Machine | What it covers | Drift gate today |
| --- | --- | --- |
| `ContractRegistry` → `alln dev export-contracts --check` / doctor `docsVersion` | Generated command/flag/error/example artifacts under `docs/generated/alln/` | **Yes** — regenerate or CI fails |
| `contractHash` in `version --json` | Fingerprint of the registry contract | **Yes** — changes when registry changes |
| `binaryVersion` (e.g. `0.9.0`) | Human/product release label | **No** — never auto-rewrote help |
| `HelpTopicRegistry` prose (`team_run_loop`, bootstrap topic bodies, …) | What agents are *taught* in `help get` / search | **No mechanical gate** — hand-authored; survived MCP retirement |
| Living ops playbooks agents are routed to (e.g. GLM best practices) | Extra recipes outside help | **No** — archive banners + disclaimers are not enough |

So agents still saw MCP `team_start(dryRun:true)` in `help get team_run_loop`
while `contractHash` flipped happily on every registry edit. The front door
shipped; the **teaching layer** did not get a regenerate/check loop.

### Make drift impossible (required direction — owned by ASF)

1. **Forbidden-pattern CI** on `HelpTopicRegistry` (and active ops docs ASF
   names): no `dryRun:true`, no MCP tool-call grammar, no deleted verbs
   (`pair slice`, …).
2. **Resolvable-command scan**: every `` `alln …` `` / named flag in help bodies
   must resolve via `ContractRegistry` (same idea as hello command resolution
   tests).
3. **Empty-search recovery test**: miss queries still return non-empty
   `nextToolPlan`.
4. **Closeout law**: changing a CLI flag/command in the same PR updates or
   deletes the teaching topic that names it — or the ASF gate fails.

Until ASF-S01–S03 land, treat help corpus edits as P0 when any agent dogfood
mentions invented flags or MCP vocabulary.

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
`docs/workflows/SSOT_Feature_Workflow.md` before implementation.

## Passes

1. Read authority: `AGENTS.md`, product SSOT, relevant workflow/operation docs.
2. Inspect current state: what already exists, what owns it, what proves it.
3. Define the CLI surface: name the `alln` command(s) that expose the capability,
   with arguments, JSON shape, exit codes, and errors. The GUI/iOS present this
   contract; they never own a parallel one. A capability with no CLI surface is
   not ready to spec.
4. Define the **help surface**: which topics/search terms teach it; confirm no
   stale MCP/retired grammar; name the empty-search recovery if discovery is new.
5. Classify risk: privacy, credentials, permissions, session data, destructive
   process control, distribution, cross-layer state.
6. Produce a Feature Packet or ordered slice list.
7. Name blocking questions only when they change semantics or risk.

## Default Output

```text
Founder intent:
Product value:
Trusted workflow slice:
Current state:
Truth owner:
CLI surface:
Help surface (topics / search terms / recovery):
Proof scenario:
Blocking questions:
Next slice:
```
