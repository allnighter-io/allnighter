import Foundation

/// Renders the human/agent-facing `alln` reference (`help_alln_cli_spec.md`) from
/// the contract registry (docs/phases/CLI_Implementation_Contract.md §Generated
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
            if !c.args.isEmpty {
                line("Arguments:")
                for a in c.args {
                    line("- `\(a.name)`\(a.required ? " (required)" : " (optional)") — \(a.summary)")
                }
                line()
            }
            if !c.flags.isEmpty {
                line("Flags:")
                for f in c.flags {
                    let value = f.takesValue ? " <\(f.valueType ?? "value")>" : ""
                    let def = f.defaultValue.map { " (default: \($0))" } ?? ""
                    line("- `--\(f.name)\(value)`\(def) — \(f.summary)")
                }
                line()
            }
            for group in c.mutuallyExclusiveFlags {
                line("Mutually exclusive: \(group.map { "`--\($0)`" }.joined(separator: ", ")).")
                line()
            }
            for constraint in c.flagConstraints {
                let peers = constraint.peers.map { "`--\($0)`" }.joined(separator: ", ")
                switch constraint.kind {
                case .requires:
                    line("Requires: `--\(constraint.subject)` requires \(peers).")
                case .onlyWith:
                    line("Only with: `--\(constraint.subject)` only with \(peers).")
                }
                line()
            }
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

        return out
    }
}
