# Ask AI — Brief

**Tier:** D (starts a read-only Auto run; entitlement can fire)
**Visual kit:** midnight title-bar pill + attached panel (Cloudflare Ask AI chrome)
**Behavioral owner:** `AskAIPrompt` (Core) · `AskAIModel` (Mac) · `ChromeCatalog` · undocumented `alln dev ask-ai`

## Purpose

A labeled door for questions about Allnighter on this Mac. Regular composer stays aimed at the project. Not a Team. Not an artifact. Screenshot capture is out of v1.

## States

idle — panel open, empty field, Ask disabled.

running — Auto turn in flight; field disabled; answer streams in the panel.

done — answer visible; field ready for a follow-up (same vendor session).

failed — honest error (including daily cap headline). Email hatch still visible.

## Intents

- Title bar **Ask AI** → open panel.
- Ask → `RunService.run` Auto, `readOnly: true`, preamble from `AskAIPrompt.assemble`. Orientation tells the model to call `alln chrome --json` for app chrome. Do not stuff labels into the prompt.
- Email a person → `mailto:support@allnighter.io`.
- Inbox / Teams / scrim / doctor / Models → close the panel.

## Field Ownership Ledger

| GUI field | Core model field | Source | States | Test owner |
| --- | --- | --- | --- | --- |
| Title / deck / placeholder | `AskAIPrompt.title` / `deck` / `placeholder` | Core | idle+ | AskAIPromptTests |
| Live facts (hidden) | `AskAIPrompt.Context` | version, PATH, bench tally, screen | running | AskAIPromptTests |
| Chrome labels | `ChromeCopy` / `alln chrome --json` | same strings SwiftUI draws | running | ChromeCatalogTests |
| Streamed answer | `RunEvent` `workerAnswerDelta` | RunService | running, done | GUI streams; no live vendor in tests |
| Email | `AskAIPrompt.supportEmail` | Core | all | AskAIPromptTests |
| Daily cap | `EntitlementCopy.dailyCapHeadline` | Core | failed | existing entitlement tests |

Developer CLI (`alln dev ask-ai`) is not in `alln menu` / ContractRegistry / customer help. Default `--print-prompt` spends no quota. `--run` is the live twin of the button. `--project` is required for `--run` when cwd is not a registered project.
