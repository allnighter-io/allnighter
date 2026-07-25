# SSOT Founder Input Workflow

Founder input is fast, valuable intent. It is not final semantic authority.

## Scope of This Doc

This doc owns **intake**: turning founder input into something specifiable, and
saying what founder input may and may not settle on its own.

It does not restate the build laws. `docs/workflows/SSOT_Feature_Workflow.md`
owns those — the CLI-first rule, the teaching-surface rule, honest reporting,
deterministic guardrails, the Feature Packet and inference bans. They were
written out in full in both docs, which is the duplicate truth these workflows
exist to ban.

Read this to intake a request. Read the Feature Workflow to spec it.

## Agent-facing help — closeout questions

The *rule* lives in `SSOT_Feature_Workflow.md` §Teaching Surface Rule. These are
the questions that close it out. For every CLI capability change, the packet /
closeout must answer:

- which `HelpTopicRegistry` topic(s) teach this surface?
- do those topics name only flags/commands that resolve in `ContractRegistry`?
- does `help search "<obvious synonym>"` hit them (driver names, model family
  names, job phrases)?
- if search misses, is recovery non-empty (`nextToolPlan` → models / teams /
  doctor / hello --for)?

If those answers are missing, the feature is not ready to close — same bar as
"no CLI surface."

Active polish phase (Complete): archived
`docs/archive/phases/CLI_Agent_Surface_Fidelity.md` (ASF).

## Why the teaching layer needs its own gate

Version sync and teaching sync are separate machines, and only the first was ever
gated. `ContractRegistry` → `alln dev export-contracts --check` and `contractHash`
both fail loudly on drift; `HelpTopicRegistry` prose and living ops playbooks are
hand-authored and had no mechanical check. That is how agents kept being taught
retired MCP grammar while the contract hash flipped happily on every edit.

Closed by ASF (complete, `docs/archive/phases/CLI_Agent_Surface_Fidelity.md`):
forbidden-pattern CI on the help corpus, a resolvable-command scan, an
empty-search recovery test, and the closeout law that a PR changing a flag or
command updates or deletes the topic that names it.

The durable rule, which outlives that phase: **changing a command changes its
teaching in the same slice, or the gate fails.**

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
