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
    public var mcpTools: [MCPToolSpec]

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        commands: [CommandSpec],
        errors: [ErrorSpec],
        doctorChecks: [DoctorCheckSpec],
        events: [EventSpec],
        nextActionKinds: [NextActionKindSpec],
        examples: [ExampleRecipe],
        mcpTools: [MCPToolSpec] = []
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.commands = commands
        self.errors = errors
        self.doctorChecks = doctorChecks
        self.events = events
        self.nextActionKinds = nextActionKinds
        self.examples = examples
        self.mcpTools = mcpTools
    }

    public enum Milestone: String, Codable, Sendable { case m1, deferred }

    /// Primary machine-output schema a command projects to.
    public enum OutputSchema: String, Codable, Sendable, CaseIterable {
        case none, teamRunJSON, doctorResult, coordinatorHealth, teamStartResponse, teamStatusResponse, teamCancelResponse, pendingItemJSON, pendingListJSON, stallEpisodeListJSON, stallListJSON, modelListJSON, floorRun, specResult, teamCatalogJSON, skillCatalogJSON, historyJSON, threadStatus, errorEnvelope, markdown, contractDoc
        case projectJSON, projectListJSON, projectContextJSON, projectWorkersJSON
        case projectThreadsJSON, projectPendingJSON
        case defaultSettingsJSON
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

    /// The process exit class of an error code (M-C). Error codes only ever map to
    /// `1` or `2`; `0` is success and carries no error code. See the exit-code table
    /// in `docs/phases/CLI_Implementation_Contract.md` §Process exit codes.
    public enum ErrorExitClass: String, Codable, Sendable, CaseIterable {
        /// Well-formed command, but the operation failed or an entity was
        /// unavailable. Exit `1`.
        case operational
        /// The command/subcommand/flag/argument was invalid before any work
        /// started. Exit `2`.
        case usage

        public var processExitCode: Int32 { self == .usage ? 2 : 1 }
    }

    /// One row of the error catalog. The recovery ladder reads these fields.
    public struct ErrorSpec: Codable, Sendable, Equatable {
        public var code: String
        public var ruleId: String
        public var agentAction: String
        public var requiresManual: Bool
        public var retryable: Bool
        public var explain: String
        /// Process exit class for this code (M-C). Most failures are `operational`;
        /// only pre-work argument/usage violations are `usage`.
        public var exitClass: ErrorExitClass
        public init(_ code: String, ruleId: String, agentAction: String, requiresManual: Bool, retryable: Bool, explain: String, exitClass: ErrorExitClass = .operational) {
            self.code = code; self.ruleId = ruleId; self.agentAction = agentAction
            self.requiresManual = requiresManual; self.retryable = retryable; self.explain = explain
            self.exitClass = exitClass
        }

        private enum CodingKeys: String, CodingKey {
            case code, ruleId, agentAction, requiresManual, retryable, explain, exitClass
        }
        // Tolerant decode: a pre-M-C artifact without `exitClass` reads as operational.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(String.self, forKey: .code)
            ruleId = try c.decode(String.self, forKey: .ruleId)
            agentAction = try c.decode(String.self, forKey: .agentAction)
            requiresManual = try c.decode(Bool.self, forKey: .requiresManual)
            retryable = try c.decode(Bool.self, forKey: .retryable)
            explain = try c.decode(String.self, forKey: .explain)
            exitClass = try c.decodeIfPresent(ErrorExitClass.self, forKey: .exitClass) ?? .operational
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

    /// An MCP tool — a thin projection of an `alln` command. MCP descriptors and
    /// behavior derive from these; no MCP-only schemas (contract §MCP Projection).
    /// Whether re-invoking a tool with the same arguments is safe (M-A).
    public enum Idempotency: String, Codable, Sendable, CaseIterable {
        /// Read-only, or a convergent write whose repeat reaches the same end state
        /// (set-default, save, delete).
        case idempotent
        /// Re-invoking may duplicate work or side effects (start a fresh run, create
        /// a new entity).
        case notIdempotent = "not_idempotent"
        /// De-duplicated by a client-supplied idempotency key within a retention
        /// window (`team_start`, `thread_send`).
        case keyed
    }

    public struct MCPToolSpec: Codable, Sendable, Equatable {
        public var name: String            // MCP tool name, e.g. "team_ask"
        public var command: String         // the alln command it projects, e.g. "team"
        public var summary: String
        public var params: [Param]
        public var outputSchema: OutputSchema
        /// Catalog error codes this tool can surface (M-A). Every entry must exist
        /// in the error catalog (`ContractRegistryTests` enforces this).
        public var errors: [String]
        /// Retry-safety contract for this tool (M-A).
        public var idempotency: Idempotency
        public struct Param: Codable, Sendable, Equatable {
            public var name: String
            public var type: String        // "string" | "boolean" | "array" | "object"
            public var required: Bool
            public var summary: String
            public var arrayItems: ArrayItemsSpec?

            public struct ArrayItemsSpec: Codable, Sendable, Equatable {
                public var oneOf: [UnionItemSpec]
                public init(oneOf: [UnionItemSpec]) { self.oneOf = oneOf }
            }

            public struct UnionItemSpec: Codable, Sendable, Equatable {
                public var type: String?
                public var properties: [String: PropertySpec]?
                public var required: [String]?
                public init(type: String? = nil, properties: [String: PropertySpec]? = nil, required: [String]? = nil) {
                    self.type = type; self.properties = properties; self.required = required
                }
            }

            public struct PropertySpec: Codable, Sendable, Equatable {
                public var type: String
                public init(type: String) { self.type = type }
            }

            public init(
                _ name: String,
                type: String = "string",
                required: Bool = false,
                summary: String,
                arrayItems: ArrayItemsSpec? = nil
            ) {
                self.name = name; self.type = type; self.required = required; self.summary = summary
                self.arrayItems = arrayItems
            }
        }
        public init(_ name: String, command: String, summary: String, params: [Param] = [], outputSchema: OutputSchema = .none, errors: [String] = [], idempotency: Idempotency = .notIdempotent) {
            self.name = name; self.command = command; self.summary = summary
            self.params = params; self.outputSchema = outputSchema
            self.errors = errors; self.idempotency = idempotency
        }

        private enum CodingKeys: String, CodingKey {
            case name, command, summary, params, outputSchema, errors, idempotency
        }
        // Tolerant decode: a pre-M-A artifact without `errors`/`idempotency` reads
        // as no declared errors and not-idempotent.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            command = try c.decode(String.self, forKey: .command)
            summary = try c.decode(String.self, forKey: .summary)
            params = try c.decode([Param].self, forKey: .params)
            outputSchema = try c.decode(OutputSchema.self, forKey: .outputSchema)
            errors = try c.decodeIfPresent([String].self, forKey: .errors) ?? []
            idempotency = try c.decodeIfPresent(Idempotency.self, forKey: .idempotency) ?? .notIdempotent
        }
    }
}
