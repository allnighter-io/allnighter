/// Single owner for projecting registry flag domains and constraints onto usage,
/// docs, menu detail, and teaching text (archived Alln_Sharpening SH-S10 / Law 6).
/// Validation stays in `CLIUsage.validateFlagConstraints`; this file only teaches.
public enum CommandProjection {
    public enum Style: Sendable {
        /// Markdown / docs (`--json`, backticks).
        case markdown
        /// Plain CLI `--help` lines.
        case plain
    }

    /// Value placeholder for a takes-value flag: enum domain when known, else valueType.
    public static func valueToken(for flag: ContractRegistry.FlagSpec) -> String {
        if let values = flag.allowedValues, !values.isEmpty {
            return values.joined(separator: "|")
        }
        return flag.valueType ?? "value"
    }

    public static func usageFlagClause(for flag: ContractRegistry.FlagSpec) -> String {
        if flag.takesValue {
            return "[--\(flag.name) <\(valueToken(for: flag))>]"
        }
        return "[--\(flag.name)]"
    }

    public static func constraintLines(
        for spec: ContractRegistry.CommandSpec,
        style: Style = .markdown
    ) -> [String] {
        func flagName(_ name: String) -> String {
            switch style {
            case .markdown: return "`--\(name)`"
            case .plain: return "--\(name)"
            }
        }
        var lines: [String] = []
        for group in spec.mutuallyExclusiveFlags {
            lines.append("Mutually exclusive: \(group.map(flagName).joined(separator: ", ")).")
        }
        for constraint in spec.flagConstraints {
            let peers = constraint.peers.map(flagName).joined(separator: ", ")
            switch constraint.kind {
            case .requires:
                lines.append("Requires: \(flagName(constraint.subject)) requires \(peers).")
            case .onlyWith:
                lines.append("Only with: \(flagName(constraint.subject)) only with \(peers).")
            }
        }
        return lines
    }

    /// Args + flags (with enum domains) + constraints for one command.
    /// Used by full `ContractDocs` and per-topic `alln docs <cmd>`.
    public static func markdownCommandBody(_ spec: ContractRegistry.CommandSpec) -> String {
        var out = ""
        func line(_ s: String = "") { out += s + "\n" }

        if !spec.args.isEmpty {
            line("Arguments:")
            for a in spec.args {
                line("- `\(a.name)`\(a.required ? " (required)" : " (optional)") — \(a.summary)")
            }
            line()
        }
        if !spec.flags.isEmpty {
            line("Flags:")
            for f in spec.flags {
                let value = f.takesValue ? " <\(valueToken(for: f))>" : ""
                let def = f.defaultValue.map { " (default: \($0))" } ?? ""
                line("- `--\(f.name)\(value)`\(def) — \(f.summary)")
            }
            line()
        }
        for text in constraintLines(for: spec, style: .markdown) {
            line(text)
            line()
        }
        return out
    }

    /// NDJSON `--stream` framing and terminal rule (code SSOT:
    /// `NDJSONStreamProjector.terminalEventNames`).
    public static var streamFramingMarkdown: String {
        let terminals = NDJSONStreamProjector.terminalEventNames.sorted().map { "`\($0)`" }.joined(separator: ", ")
        return """
        ## Run stream mode (`--stream`)

        `--stream` emits **NDJSON**: one JSON object per line on stdout. Human progress
        never mixes into stdout. Events are ordered by durable `seq`. A stream ends with
        exactly one terminal event among \(terminals).

        On `run`, `--stream` is mutually exclusive with `--json`, `--dry-run`, and `--no-wait`
        (registry constraints; invalid combinations exit 2 before any provider start).

        """
    }

    /// Why Alln does not expose OpenAI-style sampling controls on `run`.
    public static var vendorCLIControlsMarkdown: String {
        """
        ## Model controls (vendor CLI boundary)

        `alln run` drives **subscription CLIs** the user already pays for. It does **not**
        expose model-API knobs such as `--temperature` or `--max-tokens` — Alln cannot
        enforce those through every vendor CLI. Use `--effort` (`low|med|high`), `--worker`,
        and the driver's own supported flags (via manifests) for controls that actually reach
        the selected CLI.

        """
    }
}
