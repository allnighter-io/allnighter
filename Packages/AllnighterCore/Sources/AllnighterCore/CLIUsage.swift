import Foundation

/// Shared CLI usage projection from `ContractRegistry` + the global `--help` law:
/// every subcommand prints usage and exits 0 when `--help`, `-h`, or bare `help` appears.
public enum CLIUsage {
    public static let helpTokens: Set<String> = ["--help", "-h", "help"]

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

    /// Usage text for a registered command (testable; no IO).
    public static func usageText(for commandName: String, registry: ContractRegistry = .milestone1) -> String {
        guard let spec = registry.commands.first(where: { $0.name == commandName && $0.milestone == .m1 }) else {
            return "usage: alln \(commandName)"
        }
        var syn = "alln \(spec.name)"
        for arg in spec.args {
            syn += arg.required ? " <\(arg.name)>" : " [<\(arg.name)>]"
        }
        for flag in spec.flags {
            if flag.takesValue {
                syn += " [--\(flag.name) <\(flag.valueType ?? "value")>]"
            } else {
                syn += " [--\(flag.name)]"
            }
        }
        return "usage: \(syn)\n\(spec.summary)"
    }

    /// When the invocation is not an exact registry name, enumerate immediate subcommands.
    public static func usageTextForPrefix(_ prefix: String, registry: ContractRegistry = .milestone1) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = registry.commands.filter {
            $0.milestone == .m1 && ($0.name == trimmed || $0.name.hasPrefix(trimmed + " "))
        }
        if let exact = matches.first(where: { $0.name == trimmed }) {
            return usageText(for: exact.name, registry: registry)
        }
        guard !matches.isEmpty else { return "usage: alln \(trimmed)" }
        let suffixes = matches.map { String($0.name.dropFirst(trimmed.count)).trimmingCharacters(in: .whitespaces) }
        let children = Array(Set(suffixes.compactMap { $0.split(separator: " ").first.map(String.init) })).sorted()
        if children.isEmpty { return "usage: alln \(trimmed)" }
        return "usage: alln \(trimmed) \(children.joined(separator: "|"))"
    }

    /// Resolve usage for a help request at the top-level funnel (testable).
    public static func helpText(rootCommand: String, args: [String], registry: ContractRegistry = .milestone1) -> String? {
        guard helpRequested(args) else { return nil }
        if let name = resolveCommandName(rootCommand: rootCommand, args: args, registry: registry) {
            return usageText(for: name, registry: registry)
        }
        return usageTextForPrefix(invocationPath(rootCommand: rootCommand, args: args), registry: registry)
    }
}
