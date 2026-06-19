import Foundation

/// Product law: judgment teams may mix sources; mutating teams must
/// resolve to one CLI driver before spawn (`Execution_Team_Source_Gate.md`).
public enum ExecutionSourcePolicy: String, Codable, Sendable, Equatable {
    case mixedAllowed
    case singleSourceRequired
}

public enum SourceGateStatus: String, Codable, Sendable, Equatable {
    case pass
    case blocked
}

public struct SourceGateRepairOption: Codable, Sendable, Equatable {
    /// switchNonMutating | pickOneSource | twoStepFlow | revealOnly
    public var kind: String
    public var label: String
    public var detail: String?

    public init(kind: String, label: String, detail: String? = nil) {
        self.kind = kind; self.label = label; self.detail = detail
    }
}

public struct SourceGateBlocker: Codable, Sendable, Equatable {
    public var code: String
    public var message: String
    public var resolvedSourceIds: [String]
    public var resolvedSourceNames: [String]
    public var repairOptions: [SourceGateRepairOption]

    public init(
        code: String, message: String, resolvedSourceIds: [String],
        resolvedSourceNames: [String], repairOptions: [SourceGateRepairOption]
    ) {
        self.code = code; self.message = message
        self.resolvedSourceIds = resolvedSourceIds; self.resolvedSourceNames = resolvedSourceNames
        self.repairOptions = repairOptions
    }
}

public struct ExecutionTeamSourceGateResult: Sendable, Equatable {
    public var executionSourcePolicy: ExecutionSourcePolicy
    public var resolvedSourceIds: [String]
    public var executionSourceId: String?
    public var sourceGateStatus: SourceGateStatus
    public var sourceGateBlocker: SourceGateBlocker?

    public init(
        executionSourcePolicy: ExecutionSourcePolicy,
        resolvedSourceIds: [String],
        executionSourceId: String?,
        sourceGateStatus: SourceGateStatus,
        sourceGateBlocker: SourceGateBlocker?
    ) {
        self.executionSourcePolicy = executionSourcePolicy
        self.resolvedSourceIds = resolvedSourceIds
        self.executionSourceId = executionSourceId
        self.sourceGateStatus = sourceGateStatus
        self.sourceGateBlocker = sourceGateBlocker
    }
}

/// Deterministic source/driver facts for a resolved team snapshot.
public enum TeamSourceFacts {
    public static func resolvedSourceIds(workers: [Worker], models: [Model]) -> [String] {
        let byModel = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ids = workers.compactMap { byModel[$0.modelId]?.driverId }
        return Array(Set(ids)).sorted()
    }

    public static func sourceDisplayName(
        sourceId: String, registry: DriverRegistry? = nil
    ) -> String {
        registry?.manifest(id: sourceId)?.displayName ?? sourceId
    }

    public static func enrich(
        _ result: inout ResolvedTeamRun, models: [Model]
    ) {
        let ids = resolvedSourceIds(workers: result.allWorkers, models: models)
        result.resolvedSourceIds = ids
        result.executionSourceId = ids.count == 1 ? ids.first : nil
    }
}

public enum ExecutionTeamSourceGate {
    public static let mixedSourcesCode = "EXECUTION_TEAM_MIXED_SOURCES"

    /// V1 gate trigger: mutating team.
    public static func applies(to resolved: ResolvedTeamRun) -> Bool {
        resolved.mutating
    }

    public static func evaluate(
        resolved: ResolvedTeamRun,
        models: [Model],
        registry: DriverRegistry? = nil
    ) -> ExecutionTeamSourceGateResult {
        var snapshot = resolved
        TeamSourceFacts.enrich(&snapshot, models: models)
        let sourceIds = snapshot.resolvedSourceIds
        let policy: ExecutionSourcePolicy = applies(to: resolved) ? .singleSourceRequired : .mixedAllowed

        guard applies(to: resolved) else {
            return ExecutionTeamSourceGateResult(
                executionSourcePolicy: policy,
                resolvedSourceIds: sourceIds,
                executionSourceId: sourceIds.count == 1 ? sourceIds.first : nil,
                sourceGateStatus: .pass,
                sourceGateBlocker: nil
            )
        }

        guard sourceIds.count <= 1 else {
            let names = sourceIds.map { TeamSourceFacts.sourceDisplayName(sourceId: $0, registry: registry) }
            let nameList = formattedSourceList(names)
            let blocker = SourceGateBlocker(
                code: mixedSourcesCode,
                message: "Execution teams run on one CLI. This team resolves to \(nameList). Pick one execution source, or run it as a non-mutating review/proposal team first.",
                resolvedSourceIds: sourceIds,
                resolvedSourceNames: names,
                repairOptions: defaultRepairOptions(sourceIds: sourceIds, sourceNames: names)
            )
            return ExecutionTeamSourceGateResult(
                executionSourcePolicy: policy,
                resolvedSourceIds: sourceIds,
                executionSourceId: nil,
                sourceGateStatus: .blocked,
                sourceGateBlocker: blocker
            )
        }

        return ExecutionTeamSourceGateResult(
            executionSourcePolicy: policy,
            resolvedSourceIds: sourceIds,
            executionSourceId: sourceIds.first,
            sourceGateStatus: .pass,
            sourceGateBlocker: nil
        )
    }

    static func formattedSourceList(_ names: [String]) -> String {
        switch names.count {
        case 0: return "no sources"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            let head = names.dropLast().joined(separator: ", ")
            return "\(head), and \(names.last!)"
        }
    }

    static func defaultRepairOptions(sourceIds: [String], sourceNames: [String]) -> [SourceGateRepairOption] {
        var options: [SourceGateRepairOption] = [
            SourceGateRepairOption(
                kind: "switchNonMutating",
                label: "Run as review or proposal",
                detail: "Keep mixed sources for judgment; no Project mutation."
            ),
            SourceGateRepairOption(
                kind: "twoStepFlow",
                label: "Split into judgment then execution",
                detail: "Run a mixed-source review team first, then dispatch one execution source."
            ),
            SourceGateRepairOption(
                kind: "revealOnly",
                label: "Reveal work order without dispatch",
                detail: "Show the handoff text without starting a mutating run."
            ),
        ]
        for (id, name) in zip(sourceIds, sourceNames) {
            options.insert(SourceGateRepairOption(
                kind: "pickOneSource",
                label: "Use \(name) only",
                detail: "Remap worker rows to \(name) (\(id))."
            ), at: options.count - 2)
        }
        return options
    }
}
