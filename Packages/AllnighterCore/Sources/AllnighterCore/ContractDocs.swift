import Foundation

/// Renders the human/agent-facing `alln` reference (`help_alln_cli_spec.md`) from
/// the contract registry (docs/archive/phases/CLI_Implementation_Contract.md §Generated
/// Artifacts). Deterministic: arrays are emitted in registry order. This is what
/// `alln docs` projects from; do not hand-edit the generated file.
public enum ContractDocs {
    public static func markdown(_ registry: ContractRegistry = .milestone1) -> String {
        var out = ""
        func line(_ s: String = "") { out += s + "\n" }

        line("# alln — Agent-Facing CLI Reference")
        line()
        line("Generated from the contract registry (contractVersion \(registry.contractVersion), schemaVersion \(registry.schemaVersion)).")
        line("Do not hand-edit — run `alln dev export-contracts`.")
        line()

        line("## Commands (milestone 1)")
        line()
        for c in registry.commands where c.milestone == .m1 {
            line("### `alln \(c.name)`")
            line()
            line(c.summary)
            line()
            out += CommandProjection.markdownCommandBody(c)
            if c.outputSchema != .none {
                line("Output schema: `\(c.outputSchema.rawValue)`.")
                line()
            }
            if !c.exampleIds.isEmpty {
                line("Examples: \(c.exampleIds.map { "`\($0)`" }.joined(separator: ", ")).")
                line()
            }
        }

        line("## Commands (named but deferred)")
        line()
        for c in registry.commands where c.milestone == .deferred {
            line("- `alln \(c.name)` — \(c.summary)")
        }
        line()

        line("## Process exit codes")
        line()
        line("Stable table (PO-F3 / M-C). Never renumber silently — drift is gated.")
        line()
        line("| Exit code | Name | Meaning |")
        line("| --- | --- | --- |")
        for row in ExitCode.stableTable {
            line("| `\(row.code)` | `\(row.name)` | \(row.meaning) |")
        }
        line()

        line("## Error codes")
        line()
        line("| Code | Manual | Retryable | Exit class | Agent action |")
        line("| --- | --- | --- | --- | --- |")
        for e in registry.errors {
            line("| `\(e.code)` | \(e.requiresManual ? "yes" : "no") | \(e.retryable ? "yes" : "no") | `\(e.exitClass.rawValue)` | \(e.agentAction) |")
        }
        line()

        line("## NDJSON events")
        line()
        line("| Event | Required data |")
        line("| --- | --- |")
        for ev in registry.events {
            line("| `\(ev.name)` | \(ev.requiredData.map { "`\($0)`" }.joined(separator: ", ")) |")
        }
        line()

        out += CommandProjection.streamFramingMarkdown
        out += CommandProjection.vendorCLIControlsMarkdown

        line("## Next-action kinds")
        line()
        for k in registry.nextActionKinds {
            line("- `\(k.kind)` — \(k.summary)")
        }
        line()

        line("## Example recipes")
        line()
        for ex in registry.examples {
            line("- `\(ex.id)` — \(ex.title): `\(ex.command)`")
        }
        line()

        line("## Run dry-run write policy")
        line()
        line("`alln run --dry-run --json` returns `writePolicy` (`readOnly` | `mutating`) and an `effects` block:")
        line("`workerStart`, `quotaSpend`, `repoWrite`, `destructive`, `humanInteraction`.")
        line()
        line("- `effects.repoWrite` is **permission** after selectors resolve — the invocation *may* write and therefore uses write safety. It is not a prediction from prompt prose, and it is not an observed git delta.")
        line("- Terminal `TeamRunJSON.repoDelta` reports whether a mutating run *did* write.")
        line("- Research Teams are observational in the registered repository; they do not use copied files or vendor permission flags. Default Team and explicit `--worker` may be mutating.")
        line("- Dry-run itself starts no worker and spends no quota; `effects.workerStart` / `effects.quotaSpend` describe the spend twin `nextAction` would run.")
        line()

        line("## Observed run timing")
        line()
        line("Terminal `TeamRunJSON` projects observed clocks only — null means the driver did not report that observation. No forecasts or targets.")
        line()
        line("Per-worker on `workerAnswers[]`:")
        line()
        line("- `queueMs` — run request accepted → this seat's CLI spawn (lock / lane / resolution / staging).")
        line("- `ttftMs` — CLI spawn → first visible streamed delta (null off the streaming path).")
        line("- `durationMs` — CLI spawn → process exit (worker work-time).")
        line()
        line("Terminal `outcome.timing.wallMs` — run `createdAt` → latest worker `finishedAt`.")
        line()
        line("Clock boundaries are named above. A single-worker `outcome.headline` may list those observed phases; do not invent an orchestration tax by subtracting duration from wall, and do not assign blame across parallel seats.")
        line()

        return out
    }
}
