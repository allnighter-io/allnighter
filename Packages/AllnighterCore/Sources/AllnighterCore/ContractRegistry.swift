import Foundation

/// `ContractRegistry` — the Core-owned source of truth for the `alln` command
/// contract (docs/phases/CLI_Implementation_Contract.md §Contract Registry).
///
/// Everything agent-facing is a *projection* of this: `alln --help`, `alln docs`
/// (+ `--errors`/`--schema`/`--examples`), `alln doctor explain <code>`, the
/// checked-in JSON artifacts, and MCP descriptors. Rule: change the registry
/// first, regenerate, then patch runtime behavior — never hand-edit generated
/// artifacts.
///
/// This file is step 2 (the registry data + M1 content). The generators that
/// emit docs/schemas from it, and `dev export-contracts --check`, are step 3.
public struct ContractRegistry: Sendable, Equatable, Codable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var commands: [CommandSpec]
    public var errors: [ErrorSpec]
    public var doctorChecks: [DoctorCheckSpec]
    public var events: [EventSpec]
    public var nextActionKinds: [NextActionKindSpec]
    public var examples: [ExampleRecipe]

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        commands: [CommandSpec],
        errors: [ErrorSpec],
        doctorChecks: [DoctorCheckSpec],
        events: [EventSpec],
        nextActionKinds: [NextActionKindSpec],
        examples: [ExampleRecipe]
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.commands = commands
        self.errors = errors
        self.doctorChecks = doctorChecks
        self.events = events
        self.nextActionKinds = nextActionKinds
        self.examples = examples
    }

    public enum Milestone: String, Codable, Sendable { case m1, deferred }

    /// Primary machine-output schema a command projects to.
    public enum OutputSchema: String, Codable, Sendable {
        case none, teamRunJSON, doctorResult, errorEnvelope, markdown, contractDoc
    }

    public struct ArgSpec: Codable, Sendable, Equatable {
        public var name: String
        public var required: Bool
        public var summary: String
        public init(_ name: String, required: Bool, summary: String) {
            self.name = name; self.required = required; self.summary = summary
        }
    }

    public struct FlagSpec: Codable, Sendable, Equatable {
        public var name: String
        public var takesValue: Bool
        public var valueType: String?     // "path", "lane", "effort", "format", … nil ⇒ boolean
        public var defaultValue: String?
        public var summary: String
        public init(_ name: String, takesValue: Bool = false, valueType: String? = nil, defaultValue: String? = nil, summary: String) {
            self.name = name; self.takesValue = takesValue; self.valueType = valueType
            self.defaultValue = defaultValue; self.summary = summary
        }
    }

    public struct CommandSpec: Codable, Sendable, Equatable {
        public var name: String                       // full path, e.g. "doctor explain"
        public var summary: String
        public var milestone: Milestone
        public var args: [ArgSpec]
        public var flags: [FlagSpec]
        public var mutuallyExclusiveFlags: [[String]]
        public var outputSchema: OutputSchema
        public var exampleIds: [String]
        public init(_ name: String, summary: String, milestone: Milestone, args: [ArgSpec] = [], flags: [FlagSpec] = [], mutuallyExclusiveFlags: [[String]] = [], outputSchema: OutputSchema = .none, exampleIds: [String] = []) {
            self.name = name; self.summary = summary; self.milestone = milestone
            self.args = args; self.flags = flags
            self.mutuallyExclusiveFlags = mutuallyExclusiveFlags
            self.outputSchema = outputSchema; self.exampleIds = exampleIds
        }
    }

    /// One row of the error catalog. The recovery ladder reads these fields.
    public struct ErrorSpec: Codable, Sendable, Equatable {
        public var code: String
        public var ruleId: String
        public var agentAction: String
        public var requiresManual: Bool
        public var retryable: Bool
        public var explain: String
        public init(_ code: String, ruleId: String, agentAction: String, requiresManual: Bool, retryable: Bool, explain: String) {
            self.code = code; self.ruleId = ruleId; self.agentAction = agentAction
            self.requiresManual = requiresManual; self.retryable = retryable; self.explain = explain
        }
    }

    public struct DoctorCheckSpec: Codable, Sendable, Equatable {
        public var name: String           // stable name or template ("source.<sourceId>.auth")
        public var meaning: String
        public init(_ name: String, meaning: String) { self.name = name; self.meaning = meaning }
    }

    public struct EventSpec: Codable, Sendable, Equatable {
        public var name: String
        public var requiredData: [String]
        public init(_ name: String, requiredData: [String]) { self.name = name; self.requiredData = requiredData }
    }

    public struct NextActionKindSpec: Codable, Sendable, Equatable {
        public var kind: String
        public var summary: String
        public init(_ kind: String, summary: String) { self.kind = kind; self.summary = summary }
    }

    public struct ExampleRecipe: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var command: String
        public init(_ id: String, title: String, command: String) { self.id = id; self.title = title; self.command = command }
    }
}
