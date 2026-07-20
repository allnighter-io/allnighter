import Foundation

/// `alln commands --json` — full M1 command manifest for agent discovery (AE-S13).
/// Two-tier disclosure: `--help` lists names; this hydrate path carries trigger,
/// args, examples, and anti-examples. Anti-examples stay empty until AE-S15.
public struct CommandsManifestJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var contractHash: String
    public var commands: [Entry]

    public struct Entry: Codable, Sendable, Equatable {
        public var name: String
        /// When-to-use trigger. Today: `CommandSpec.summary` (AE-S15 will split).
        public var trigger: String
        public var args: [Arg]
        public var flags: [Flag]
        public var examples: [Example]
        public var antiExamples: [String]

        public struct Arg: Codable, Sendable, Equatable {
            public var name: String
            public var required: Bool
            public var summary: String
        }

        public struct Flag: Codable, Sendable, Equatable {
            public var name: String
            public var takesValue: Bool
            public var valueType: String?
            public var defaultValue: String?
            public var summary: String
        }

        public struct Example: Codable, Sendable, Equatable {
            public var id: String
            public var title: String
            public var command: String
        }
    }

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        contractHash: String,
        commands: [Entry]
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.contractHash = contractHash
        self.commands = commands
    }

    /// Project the M1 registry into the machine front-door manifest.
    public static func project(registry: ContractRegistry = .milestone1) -> CommandsManifestJSON {
        let recipes = Dictionary(uniqueKeysWithValues: registry.examples.map { ($0.id, $0) })
        let entries = registry.commands
            .filter { $0.milestone == .m1 }
            .sorted { $0.name < $1.name }
            .map { spec -> Entry in
                Entry(
                    name: spec.name,
                    trigger: spec.summary,
                    args: spec.args.map {
                        Entry.Arg(name: $0.name, required: $0.required, summary: $0.summary)
                    },
                    flags: spec.flags.map {
                        Entry.Flag(
                            name: $0.name,
                            takesValue: $0.takesValue,
                            valueType: $0.valueType,
                            defaultValue: $0.defaultValue,
                            summary: $0.summary
                        )
                    },
                    examples: spec.exampleIds.compactMap { id in
                        guard let recipe = recipes[id] else { return nil }
                        return Entry.Example(id: recipe.id, title: recipe.title, command: recipe.command)
                    },
                    antiExamples: []
                )
            }
        return CommandsManifestJSON(
            contractVersion: registry.contractVersion,
            contractHash: ContractRegistry.contractHash(registry),
            commands: entries
        )
    }
}
