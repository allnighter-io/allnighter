import Foundation

/// Shared CLI usage projection from `ContractRegistry` + the global `--help` law:
/// every subcommand prints usage and exits 0 when `--help`, `-h`, or bare `help` appears.
public enum CLIUsage {
    public static let helpTokens: Set<String> = ["--help", "-h", "help"]

    /// AE-S12: an argv flag not declared on the resolved command's `FlagSpec` list.
    public struct UnknownFlagError: Equatable, Sendable {
        public var flag: String
        public var commandName: String
        public var suggestions: [String]

        public init(flag: String, commandName: String, suggestions: [String]) {
            self.flag = flag
            self.commandName = commandName
            self.suggestions = suggestions
        }

        public var message: String {
            var msg = "unknown flag --\(flag) for command `\(commandName)`"
            if !suggestions.isEmpty {
                msg += "; did you mean: " + suggestions.map { "--\($0)" }.joined(separator: ", ")
            }
            msg += ". Run `alln \(commandName) --help`."
            return msg
        }
    }

    public static func helpRequested(_ args: [String]) -> Bool {
        args.contains { helpTokens.contains($0) }
    }

    public static func strippingHelp(_ args: [String]) -> [String] {
        args.filter { !helpTokens.contains($0) }
    }

    /// Full invocation path after the `alln` executable token (testable).
    public static func invocationPath(rootCommand: String, args: [String]) -> String {
        ([rootCommand] + strippingHelp(args)).joined(separator: " ")
    }

    /// Longest-prefix match against the M1 registry.
    public static func resolveCommandName(
        rootCommand: String,
        args: [String],
        registry: ContractRegistry = .milestone1
    ) -> String? {
        ContractRegistry.resolveCommandName(
            from: invocationPath(rootCommand: rootCommand, args: args),
            registry: registry
        )
    }

    /// Flag keys present in argv (`--name` / `--name value`), excluding help tokens.
    /// Value consumption mirrors registry `FlagSpec.takesValue` when the command is
    /// known; unknown flags never consume the next token (so a following positional
    /// is not mistaken for a flag value during validation).
    public static func parsedFlagNames(
        from args: [String],
        commandName: String? = nil,
        registry: ContractRegistry = .milestone1
    ) -> [String] {
        let takesValue: Set<String> = {
            guard let commandName,
                  let spec = registry.commands.first(where: { $0.name == commandName && $0.milestone == .m1 })
            else { return [] }
            return Set(spec.flags.filter(\.takesValue).map(\.name))
        }()

        var names: [String] = []
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--" { break }
            if a.hasPrefix("--") {
                let key = String(a.dropFirst(2))
                if key == "help" {
                    i += 1
                    continue
                }
                names.append(key)
                if takesValue.contains(key), i + 1 < args.count, !args[i + 1].hasPrefix("-") {
                    i += 2
                } else {
                    i += 1
                }
            } else {
                i += 1
            }
        }
        return names
    }

    /// Fail-closed flag check (AE-S12). Returns the first unknown flag, or nil.
    public static func validateFlags(
        args: [String],
        commandName: String,
        registry: ContractRegistry = .milestone1
    ) -> UnknownFlagError? {
        guard let spec = registry.commands.first(where: { $0.name == commandName && $0.milestone == .m1 }) else {
            return nil
        }
        let allowed = Set(spec.flags.map(\.name))
        let candidates = spec.flags.map(\.name)
        for flag in parsedFlagNames(from: args, commandName: commandName, registry: registry) {
            if allowed.contains(flag) { continue }
            return UnknownFlagError(
                flag: flag,
                commandName: commandName,
                suggestions: nearestFlagMatches(to: flag, in: candidates)
            )
        }
        return nil
    }

    /// Registry-owned flag mode / companion violations (Law 6).
    /// Covers mutual-exclusion groups plus `requires` / `onlyWith` constraints.
    public struct FlagConstraintError: Equatable, Sendable {
        public let commandName: String
        public let message: String
        public let subject: String?
        public let peers: [String]

        public init(commandName: String, message: String, subject: String? = nil, peers: [String] = []) {
            self.commandName = commandName
            self.message = message
            self.subject = subject
            self.peers = peers
        }
    }

    /// Fail closed on registry constraints before dry-run / run / provider start.
    /// Returns the first violation, or nil when the present flag set is legal.
    public static func validateFlagConstraints(
        args: [String],
        commandName: String,
        registry: ContractRegistry = .milestone1
    ) -> FlagConstraintError? {
        guard let spec = registry.commands.first(where: { $0.name == commandName && $0.milestone == .m1 }) else {
            return nil
        }
        let present = Set(parsedFlagNames(from: args, commandName: commandName, registry: registry))

        for group in spec.mutuallyExclusiveFlags {
            let hit = group.filter { present.contains($0) }
            guard hit.count >= 2 else { continue }
            let labels = hit.map { "--\($0)" }
            let message: String
            if labels.count == 2 {
                message = "\(labels[0]) and \(labels[1]) are mutually exclusive"
            } else {
                message = "\(labels.joined(separator: ", ")) are mutually exclusive"
            }
            return FlagConstraintError(
                commandName: commandName,
                message: message,
                subject: hit.first,
                peers: Array(hit.dropFirst())
            )
        }

        for constraint in spec.flagConstraints {
            guard present.contains(constraint.subject) else { continue }
            switch constraint.kind {
            case .requires:
                let missing = constraint.peers.filter { !present.contains($0) }
                guard !missing.isEmpty else { continue }
                let needed = missing.map { "--\($0)" }.joined(separator: " and ")
                return FlagConstraintError(
                    commandName: commandName,
                    message: "--\(constraint.subject) requires \(needed)",
                    subject: constraint.subject,
                    peers: missing
                )
            case .onlyWith:
                let ok = constraint.peers.contains { present.contains($0) }
                guard !ok else { continue }
                let companions = constraint.peers.map { "--\($0)" }.joined(separator: " or ")
                return FlagConstraintError(
                    commandName: commandName,
                    message: "--\(constraint.subject) is only valid with \(companions)",
                    subject: constraint.subject,
                    peers: constraint.peers
                )
            }
        }
        return nil
    }

    /// Edit-distance nearest flag names (top `limit`), for did-you-mean recovery.
    public static func nearestFlagMatches(to flag: String, in candidates: [String], limit: Int = 3) -> [String] {
        guard !candidates.isEmpty, limit > 0 else { return [] }
        let scored = candidates.map { ($0, editDistance(flag, $0)) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0 < rhs.0
            }
        // Only suggest when reasonably close (typo / near-miss), not the whole flag list.
        let maxDist = max(2, flag.count / 2)
        return scored.filter { $0.1 <= maxDist }.prefix(limit).map(\.0)
    }

    /// Levenshtein edit distance (AE-S07 / AE-S12 did-you-mean).
    public static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// Usage text for a registered command (testable; no IO).
    /// Returns `nil` when the name is not in the registry — never invents a surface (AE-S01 / Law 8).
    /// Enum domains and registry flag constraints project from `CommandProjection` (SH-S10).
    public static func usageText(for commandName: String, registry: ContractRegistry = .milestone1) -> String? {
        guard let spec = registry.commands.first(where: { $0.name == commandName && $0.milestone == .m1 }) else {
            return nil
        }
        var syn = "alln \(spec.name)"
        for arg in spec.args {
            syn += arg.required ? " <\(arg.name)>" : " [<\(arg.name)>]"
        }
        for flag in spec.flags {
            syn += " \(CommandProjection.usageFlagClause(for: flag))"
        }
        var lines = ["usage: \(syn)", spec.summary]
        lines.append(contentsOf: CommandProjection.constraintLines(for: spec, style: .plain))
        return lines.joined(separator: "\n")
    }

    /// When the invocation is not an exact registry name, enumerate immediate subcommands.
    /// Returns `nil` when the prefix matches nothing — never fabricates `usage: alln <unknown>`.
    public static func usageTextForPrefix(_ prefix: String, registry: ContractRegistry = .milestone1) -> String? {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = registry.commands.filter {
            $0.milestone == .m1 && ($0.name == trimmed || $0.name.hasPrefix(trimmed + " "))
        }
        if let exact = matches.first(where: { $0.name == trimmed }) {
            return usageText(for: exact.name, registry: registry)
        }
        guard !matches.isEmpty else { return nil }
        let suffixes = matches.map { String($0.name.dropFirst(trimmed.count)).trimmingCharacters(in: .whitespaces) }
        let children = Array(Set(suffixes.compactMap { $0.split(separator: " ").first.map(String.init) })).sorted()
        if children.isEmpty { return nil }
        return "usage: alln \(trimmed) \(children.joined(separator: "|"))"
    }

    /// Resolve usage for a help request at the top-level funnel (testable).
    /// Unknown commands return `nil` so the CLI can fail closed without inventing usage (finding 12).
    public static func helpText(rootCommand: String, args: [String], registry: ContractRegistry = .milestone1) -> String? {
        guard helpRequested(args) else { return nil }
        if let name = resolveCommandName(rootCommand: rootCommand, args: args, registry: registry) {
            return usageText(for: name, registry: registry)
        }
        return usageTextForPrefix(invocationPath(rootCommand: rootCommand, args: args), registry: registry)
    }

    /// Top-level `alln --help` — exhaustive name list projected from the registry (AE-S01 / Law 1).
    /// One line per M1 command, grouped by family; no hand-written command rows.
    public static func topLevelHelpText(registry: ContractRegistry = .milestone1) -> String {
        let m1 = registry.commands.filter { $0.milestone == .m1 }.sorted { $0.name < $1.name }
        var families: [String: [(name: String, summary: String)]] = [:]
        for spec in m1 {
            let family = spec.name.split(separator: " ").first.map(String.init) ?? spec.name
            families[family, default: []].append((spec.name, spec.summary))
        }
        // Golden-path families first; remaining families alphabetical.
        let preferred = [
            "run", "teams", "models", "doctor", "bootstrap", "help", "docs", "menu",
            "version", "install-cli", "project", "thread", "skills", "pending", "stalled",
            "show", "export", "history", "floor", "spec", "defaults", "boost-window",
            "ps", "kill", "gc", "continuity", "serve", "pair", "panel", "dev",
        ]
        let remaining = families.keys.filter { !preferred.contains($0) }.sorted()
        let order = preferred.filter { families[$0] != nil } + remaining

        var lines: [String] = [
            "alln — local team run, callable by any agent (zero API cost)",
            "",
        ]
        for family in order {
            guard let rows = families[family] else { continue }
            lines.append(family)
            for row in rows {
                let pad = String(repeating: " ", count: max(1, 36 - row.name.count))
                let summary = row.summary.replacingOccurrences(of: "\n", with: " ")
                lines.append("  \(row.name)\(pad)\(summary)")
            }
            lines.append("")
        }
        let count = m1.count
        // AE-S13 completeness marker — incompleteness must never be implied.
        lines.append(
            "\(count) commands · alln docs <cmd> for schema · alln menu --json · alln help search \"<intent>\" to find one"
        )
        return lines.joined(separator: "\n")
    }
}
