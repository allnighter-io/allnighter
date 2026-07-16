# Pilot Polish + Agent UX — frictionless handoff, post-MCP hello, Auto Fix discovery

Status: In progress — piloted delivery #2 (PM = live Claude session; dev = Cursor Grok 4.5)
Owner: AllnighterCore + CLI
Updated: 2026-07-16

Three bounded fixes from dogfooding piloted delivery #1 and a fresh-eyes agent audit
of help/doctor/activation.

## P1 — frictionless handoff: no JSON authoring at the cockpit (CLI)

Today `pilot handoff --file round.md` requires the PM to embed the ENTIRE order inside
a JSON `handover` string (the RelayVerdict tail), forcing escape-generation scripts.
The pilot cockpit should accept plain markdown:

`alln pair pilot handoff --relay <id> --verdict continue --handover-file order.md
[--note "…"] [--no-wait] [--json]`
- `--handover-file` (or `--handover-stdin`): the file's RAW text IS the handover,
  sent to the dev verbatim — no JSON, no escaping.
- `--verdict` required with it (`continue|done|escalate`); `--note` optional for
  done/escalate (then `--handover-file` optional).
- The existing `--file` (verdict-tail format) STAYS — it is the format a spawned PM
  emits, and scripts may prefer it. Both paths converge on the same
  `runExternalRound` submission (internally the new path may synthesize the verdict
  JSON — implementation's choice, but the dev must receive the file text byte-exact).
- Mutually exclusive with `--file`; usage errors follow the catalog (exit 2).

**Acceptance:** a handoff driven by `--verdict continue --handover-file` delivers the
markdown byte-exact to the dev prompt (test through the real dispatch capture seam);
done/escalate via flags work; `--file` path unchanged and still tested; help/usage
strings updated.

## P2 — `alln team hello` next plan is post-MCP (CLI contract)

Observed: `nextToolPlan` says `{"tool": "team_start", "args": {"dryRun": "true"}}` —
retired MCP tool names. A fresh agent following the bootstrap snippet hits a dead
reference on its first call. The plan must name runnable CLI commands.

**Acceptance:** hello's next-action plan carries a literal runnable command string
(e.g. `alln team preflight --team <id>` / `alln team ask …`) plus the reason; NO
field anywhere in the hello payload names a tool that doesn't exist as a CLI verb;
schema/contract regenerated; a drift test asserts every command string in the hello
payload parses against the ContractRegistry command set.

## P3 — Auto Fix is discoverable (help)

Observed: `alln help search "fix a bug in my repo"` → projects topic; `"try fix"` →
the error-envelope topic. `alln run --try-fix` (Bug Hunt → gate → one bounded fix
attempt) has NO help topic.

**Acceptance:** a new `auto_fix` help topic (what it is, the safety gate, the exact
command, when to prefer it vs a plain team run — reference ContractRegistry, never
hand-author flags); search routing: "fix a bug", "try fix", "auto fix" rank it top;
existing HelpTopicRegistry drift gates green.

## Works test

Delivered via `alln pair pilot` with `model_cursor_grok_45` (Cursor CLI seat —
second CLI dogfooded in the dev chair, first turn after the project-scoped
`.cursor/cli.json` allowlist override). PM verifies: byte-exact handover delivery,
hello payload contains zero dead references, the three searches route to auto_fix.
`swift test --filter 'Relay|Pilot|Help|Hello'` green; contracts regenerated.
