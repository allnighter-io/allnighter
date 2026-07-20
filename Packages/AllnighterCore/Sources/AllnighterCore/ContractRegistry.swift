import CryptoKit
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

    /// Stable hash over the full agent-facing surface (AE-S11).
    /// Covers commands, flags, value types, summaries, errors, events, examples,
    /// and declared output schemas — not merely command names — so any surface
    /// edit flips the hash. Agents use this to detect a stale cached snapshot
    /// (`alln version`'s `contractHash`).
    public static func contractHash(_ registry: ContractRegistry = .milestone1) -> String {
        let digest = SHA256.hash(data: Data(canonicalSurfacePayload(registry).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Names of M1 flags with `takesValue == false`. Single owner for argv boolean
    /// parsing (`Options.booleanFlags`) so FlagSpec cannot drift from the parser.
    public static func booleanFlagNames(_ registry: ContractRegistry = .milestone1) -> Set<String> {
        Set(
            registry.commands
                .filter { $0.milestone == .m1 }
                .flatMap(\.flags)
                .filter { !$0.takesValue }
                .map(\.name)
        )
    }

    /// Canonical serialization hashed by `contractHash`. Deterministic: CoreJSON
    /// (sorted keys) of the registry, plus sorted schema artifact bodies.
    /// Encode / schema projection failures fail loud — a truncated payload would
    /// silently under-hash the surface (AE code-audit / no silent fallbacks).
    public static func canonicalSurfacePayload(_ registry: ContractRegistry = .milestone1) -> String {
        guard let data = try? CoreJSON.encode(registry) else {
            preconditionFailure("ContractRegistry.canonicalSurfacePayload: registry encode failed")
        }
        var parts: [String] = [String(decoding: data, as: UTF8.self)]
        do {
            let schemas = try ContractExport.schemaArtifactsForHash()
            for artifact in schemas.sorted(by: { $0.filename < $1.filename }) {
                parts.append(artifact.filename)
                parts.append(artifact.contents)
            }
        } catch {
            preconditionFailure("ContractRegistry.canonicalSurfacePayload: schema artifacts failed: \(error)")
        }
        return parts.joined(separator: "\n")
    }

    /// Checked-in lock file payload (`docs/generated/alln/contract.lock.json`).
    public struct ContractLock: Codable, Sendable, Equatable {
        public var contractVersion: String
        public var contractHash: String
        public init(contractVersion: String, contractHash: String) {
            self.contractVersion = contractVersion
            self.contractHash = contractHash
        }

        public static func current(_ registry: ContractRegistry = .milestone1) -> ContractLock {
            ContractLock(
                contractVersion: registry.contractVersion,
                contractHash: ContractRegistry.contractHash(registry)
            )
        }
    }

    /// Longest-prefix match of an invocation (`alln run --dry-run …`) to a registered M1 command name.
    public static func resolveCommandName(
        from invocation: String,
        registry: ContractRegistry = .milestone1
    ) -> String? {
        var rest = invocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.hasPrefix("alln ") { rest = String(rest.dropFirst(5)) }
        let names = registry.commands.filter { $0.milestone == .m1 }.map(\.name).sorted { $0.count > $1.count }
        return names.first { rest == $0 || rest.hasPrefix($0 + " ") }
    }

    public enum Milestone: String, Codable, Sendable { case m1, deferred }

    /// Primary machine-output schema a command projects to.
    public enum OutputSchema: String, Codable, Sendable, CaseIterable {
        case none, teamRunJSON, doctorResult, coordinatorHealth, teamStartResponse, teamStatusResponse, teamCancelResponse, pendingItemJSON, pendingListJSON, stallEpisodeListJSON, stallListJSON, modelListJSON, floorRun, specResult, teamCatalogJSON, skillCatalogJSON, historyJSON, threadStatus, threadGetJSON, threadAttachmentJSON, errorEnvelope, markdown, contractDoc
        case projectJSON, projectListJSON, projectContextJSON, projectWorkersJSON
        case projectThreadsJSON, projectPendingJSON
        case defaultSettingsJSON
        case boostWindowSettingsJSON
        case utilizationSeedEventJSON
        case utilizationObservationsClearJSON
        case helpSearchJSON, helpGetJSON, helpTopicsJSON
        case errorExplainJSON
        case stallEpisodeJSON
        case pendingQueueJSON
        case relayJSON
        case panelJSON
        case panelRoundJSON
        case bootstrapJSON
        case installCLIJSON
        case versionJSON
        case ownershipPsJSON
        case ownershipKillJSON
        case ownershipGarbageCollectionJSON
        case menuJSON
        case menuShowJSON
    }

    /// Registry-owned parser visibility (MR-S01). Public rows appear in `alln menu`;
    /// developer/internal stay out of the agent front door.
    public enum CommandVisibility: String, Codable, Sendable, CaseIterable {
        case `public`
        case developer
        case `internal`
    }

    /// Structured effect level for one effect axis (MR-S01).
    public enum EffectLevel: String, Codable, Sendable, CaseIterable {
        case never
        case always
        case dependsOnFlags
        case dependsOnSelection
    }

    /// Registry-owned command effects (MR-S01). Facts, not adjectives.
    public struct EffectProfile: Codable, Sendable, Equatable {
        public var workerStart: EffectLevel
        public var quotaSpend: EffectLevel
        public var repoWrite: EffectLevel
        public var destructive: EffectLevel
        public var humanInteraction: EffectLevel

        public init(
            workerStart: EffectLevel = .never,
            quotaSpend: EffectLevel = .never,
            repoWrite: EffectLevel = .never,
            destructive: EffectLevel = .never,
            humanInteraction: EffectLevel = .never
        ) {
            self.workerStart = workerStart
            self.quotaSpend = quotaSpend
            self.repoWrite = repoWrite
            self.destructive = destructive
            self.humanInteraction = humanInteraction
        }

        /// Sensible defaults from `spendsQuota` + command-name semantics.
        public static func inferred(spendsQuota: Bool, name: String) -> EffectProfile {
            let startsWorker =
                spendsQuota
                || name == "run"
                || name.hasPrefix("pair ")
                || name.hasPrefix("panel start")
                || name.hasPrefix("thread send")
            let catalogWrite =
                name.hasPrefix("teams edit")
                || name.hasPrefix("teams delete")
                || name.hasPrefix("teams duplicate")
                || name.hasPrefix("teams new")
                || name.hasPrefix("teams restore")
                || name.hasPrefix("teams set-default")
                || name.hasPrefix("skills edit")
                || name.hasPrefix("skills delete")
                || name.hasPrefix("skills new")
                || name.hasPrefix("models add")
                || name.hasPrefix("models update")
                || name.hasPrefix("models delete")
                || name.hasPrefix("models enable")
                || name.hasPrefix("models disable")
                || name.hasPrefix("project add")
                || name.hasPrefix("project archive")
                || name.hasPrefix("defaults ")
                || name.hasPrefix("boost-window set")
            let destructive =
                name == "kill"
                || name == "gc"
                || name.hasPrefix("teams delete")
                || name.hasPrefix("skills delete")
                || name.hasPrefix("models delete")
                || name.hasPrefix("pending cancel")
                || name.hasPrefix("team cancel")
            return EffectProfile(
                workerStart: startsWorker ? .dependsOnFlags : .never,
                quotaSpend: spendsQuota ? .dependsOnFlags : .never,
                repoWrite: startsWorker ? .dependsOnSelection : (catalogWrite ? .always : .never),
                destructive: destructive ? .dependsOnSelection : .never,
                humanInteraction: .never
            )
        }

        /// Stable short key for `effectProfiles` dedup maps.
        public var profileKey: String {
            func abbrev(_ level: EffectLevel) -> String {
                switch level {
                case .never: return "n"
                case .always: return "a"
                case .dependsOnFlags: return "f"
                case .dependsOnSelection: return "s"
                }
            }
            return [
                abbrev(workerStart),
                abbrev(quotaSpend),
                abbrev(repoWrite),
                abbrev(destructive),
                abbrev(humanInteraction),
            ].joined(separator: "")
        }
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
        /// Closed enum domain for this flag (SH-S10). Resolved from
        /// `valueTypeDomains[valueType]` when omitted at init; open types stay nil.
        public var allowedValues: [String]?
        public var summary: String
        public init(
            _ name: String,
            takesValue: Bool = false,
            valueType: String? = nil,
            defaultValue: String? = nil,
            allowedValues: [String]? = nil,
            summary: String
        ) {
            self.name = name
            self.takesValue = takesValue
            self.valueType = valueType
            self.defaultValue = defaultValue
            self.allowedValues = allowedValues
                ?? valueType.flatMap { ContractRegistry.valueTypeDomains[$0] }
            self.summary = summary
        }
    }

    /// Closed flag value domains keyed by `FlagSpec.valueType` (Law 6 / SH-S10).
    /// Open types (`path`, `id`, `string`, …) are intentionally absent. A flag may
    /// override with an explicit `allowedValues` when one valueType name spans
    /// different domains (e.g. export vs help `format`).
    public static let valueTypeDomains: [String: [String]] = [
        "effort": EffortLevel.allCases.map(\.rawValue),
        "lane": WorkLane.allCases.map(\.rawValue),
        "host": ["claude", "cursor", "codex", "generic"],
        "modelRole": ModelRole.allCases.map(\.rawValue),
        "purpose": SkillPurpose.allCases.map(\.rawValue),
        "state": RunLifecycle.allCases.map(\.rawValue) + ["terminal"],
        "detail": SpecRetrieval.Detail.allCases.map(\.rawValue),
        "verdict": ["continue", "done", "escalate"],
    ]

    /// Mode / companion requirements beyond mutual exclusion (Law 6).
    /// `mutuallyExclusiveFlags` stays the exclusive-group owner; this owns
    /// `requires` (all companions) and `onlyWith` (at least one companion).
    public struct FlagConstraint: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable, Equatable {
            /// If `subject` is present, every flag in `peers` must also be present.
            case requires
            /// If `subject` is present, at least one flag in `peers` must also be present.
            case onlyWith
        }

        public let kind: Kind
        public let subject: String
        public let peers: [String]

        public init(_ kind: Kind, _ subject: String, _ peers: [String]) {
            self.kind = kind
            self.subject = subject
            self.peers = peers
        }

        public init(_ kind: Kind, _ subject: String, _ peer: String) {
            self.init(kind, subject, [peer])
        }
    }

    public struct CommandSpec: Codable, Sendable, Equatable {
        public var name: String                       // full path, e.g. "doctor explain"
        public var summary: String
        /// Optional trigger situation (AE-S15). When nil, `summary` is the trigger.
        public var trigger: String?
        /// Optional worked invocation with real values (AE-S15).
        public var example: String?
        /// Optional anti-example: "Do NOT use this when…" (AE-S15).
        public var antiExample: String?
        public var milestone: Milestone
        public var args: [ArgSpec]
        public var flags: [FlagSpec]
        public var mutuallyExclusiveFlags: [[String]]
        /// Companion / mode requirements (`requires`, `onlyWith`).
        public var flagConstraints: [FlagConstraint]
        public var outputSchema: OutputSchema
        public var exampleIds: [String]
        /// AE-S04: true when invoking this command may spend model quota.
        public var spendsQuota: Bool
        /// Free twin invocation when `spendsQuota` (e.g. `alln run --dry-run`).
        public var freeTwinCommand: String?
        /// Parser visibility (MR-S01). Default `.public` for Codable back-compat.
        public var visibility: CommandVisibility
        /// When true, this command generates one `menu.actions[]` row (1:1, MR-S01).
        public var menuAction: Bool
        /// Structured effects (MR-S01). Inferred from semantics when omitted at init.
        public var effects: EffectProfile
        public init(
            _ name: String,
            summary: String,
            milestone: Milestone,
            trigger: String? = nil,
            example: String? = nil,
            antiExample: String? = nil,
            args: [ArgSpec] = [],
            flags: [FlagSpec] = [],
            mutuallyExclusiveFlags: [[String]] = [],
            flagConstraints: [FlagConstraint] = [],
            outputSchema: OutputSchema = .none,
            exampleIds: [String] = [],
            spendsQuota: Bool = false,
            freeTwinCommand: String? = nil,
            visibility: CommandVisibility = .public,
            menuAction: Bool = false,
            effects: EffectProfile? = nil
        ) {
            self.name = name; self.summary = summary; self.milestone = milestone
            self.trigger = trigger; self.example = example; self.antiExample = antiExample
            self.args = args; self.flags = flags
            self.mutuallyExclusiveFlags = mutuallyExclusiveFlags
            self.flagConstraints = flagConstraints
            self.outputSchema = outputSchema; self.exampleIds = exampleIds
            self.spendsQuota = spendsQuota
            self.freeTwinCommand = freeTwinCommand
            self.visibility = visibility
            self.menuAction = menuAction
            self.effects = effects ?? EffectProfile.inferred(spendsQuota: spendsQuota, name: name)
        }

        private enum CodingKeys: String, CodingKey {
            case name, summary, trigger, example, antiExample, milestone, args, flags
            case mutuallyExclusiveFlags, flagConstraints, outputSchema, exampleIds, spendsQuota, freeTwinCommand
            case visibility, menuAction, effects
        }

        /// Tolerant decode: pre-1.7.0 artifacts without visibility/menuAction/effects
        /// read as public / false / inferred; missing `flagConstraints` → [].
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            summary = try c.decode(String.self, forKey: .summary)
            trigger = try c.decodeIfPresent(String.self, forKey: .trigger)
            example = try c.decodeIfPresent(String.self, forKey: .example)
            antiExample = try c.decodeIfPresent(String.self, forKey: .antiExample)
            milestone = try c.decode(Milestone.self, forKey: .milestone)
            args = try c.decodeIfPresent([ArgSpec].self, forKey: .args) ?? []
            flags = try c.decodeIfPresent([FlagSpec].self, forKey: .flags) ?? []
            mutuallyExclusiveFlags = try c.decodeIfPresent([[String]].self, forKey: .mutuallyExclusiveFlags) ?? []
            flagConstraints = try c.decodeIfPresent([FlagConstraint].self, forKey: .flagConstraints) ?? []
            outputSchema = try c.decodeIfPresent(OutputSchema.self, forKey: .outputSchema) ?? .none
            exampleIds = try c.decodeIfPresent([String].self, forKey: .exampleIds) ?? []
            spendsQuota = try c.decodeIfPresent(Bool.self, forKey: .spendsQuota) ?? false
            freeTwinCommand = try c.decodeIfPresent(String.self, forKey: .freeTwinCommand)
            visibility = try c.decodeIfPresent(CommandVisibility.self, forKey: .visibility) ?? .public
            menuAction = try c.decodeIfPresent(Bool.self, forKey: .menuAction) ?? false
            effects = try c.decodeIfPresent(EffectProfile.self, forKey: .effects)
                ?? EffectProfile.inferred(spendsQuota: spendsQuota, name: name)
        }
    }

    /// The process exit class of an error code (M-C + PO-F3). Maps to the stable
    /// `ExitCode` table (`0` is success and carries no error code). See the
    /// exit-code table in `docs/phases/CLI_Implementation_Contract.md` §Process
    /// exit codes. Classes must never be renumbered without a contract bump.
    public enum ErrorExitClass: String, Codable, Sendable, CaseIterable {
        /// Well-formed command, but the operation failed or an entity was
        /// unavailable. Exit `1` (`ExitCode.runFailed`).
        case operational
        /// The command/subcommand/flag/argument was invalid before any work
        /// started. Exit `2` (`ExitCode.usageError`).
        case usage
        /// A bounded wait expired before the target condition. Exit `3`
        /// (`ExitCode.timeout`).
        case timeout
        /// Per-root execution/write lane stayed busy past the wait bound. Exit
        /// `4` (`ExitCode.laneBusy`).
        case laneBusy

        public var processExitCode: Int32 {
            switch self {
            case .operational: return ExitCode.runFailed
            case .usage: return ExitCode.usageError
            case .timeout: return ExitCode.timeout
            case .laneBusy: return ExitCode.laneBusy
            }
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

}
