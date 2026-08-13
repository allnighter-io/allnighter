import Foundation

/// One target in a sweep queue (OCL-S08 / packet §2.6.1).
///
/// Outcomes are the honesty bound: every target is `done`, `failed`, or
/// `not-attempted`. A skip that reports `done` is the lie-prone layer in §9.
public enum SweepTargetOutcome: String, Codable, Sendable, Equatable, CaseIterable {
    case done
    case failed
    case notAttempted = "not-attempted"
}

public enum SweepStatus: String, Codable, Sendable, Equatable, CaseIterable {
    /// Owner process is advancing remaining `not-attempted` targets.
    case running
    /// Stopped before every target was attempted. Resume continues; this is not complete.
    case interrupted
    /// Every target is `done` or `failed`. Never stamped while any target is `not-attempted`.
    case complete
}

public struct SweepTargetRecord: Codable, Sendable, Equatable {
    public var id: String
    public var outcome: SweepTargetOutcome
    /// Run journal id when this target was dispatched through `RunService`.
    public var runId: String?
    public var reason: String?

    public init(
        id: String,
        outcome: SweepTargetOutcome = .notAttempted,
        runId: String? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.outcome = outcome
        self.runId = runId
        self.reason = reason
    }
}

/// Durable sweep: one order × N targets, checkpointed, one artifact.
/// Target runs reuse `RunService` / the journal / the per-root write lock.
/// This record is the queue, not a second run model.
public struct SweepState: Codable, Sendable, Equatable {
    public var id: String
    public var order: String
    public var projectRoot: String
    public var modelId: String?
    public var targets: [SweepTargetRecord]
    public var status: SweepStatus
    public var createdAt: Date
    public var updatedAt: Date
    /// Absolute path of the one sweep artifact, written on every checkpoint.
    public var artifactPath: String?

    public init(
        id: String,
        order: String,
        projectRoot: String,
        modelId: String? = nil,
        targets: [SweepTargetRecord],
        status: SweepStatus = .running,
        createdAt: Date,
        updatedAt: Date,
        artifactPath: String? = nil
    ) {
        self.id = id
        self.order = order
        self.projectRoot = projectRoot
        self.modelId = modelId
        self.targets = targets
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.artifactPath = artifactPath
    }
}

public enum SweepHonesty {
    public static func unattemptedIds(_ state: SweepState) -> [String] {
        state.targets.filter { $0.outcome == .notAttempted }.map(\.id)
    }

    /// True only when every target was attempted. Absence of an attempt is never success.
    public static func canReportComplete(_ state: SweepState) -> Bool {
        !state.targets.isEmpty && unattemptedIds(state).isEmpty
    }

    public static func counts(_ state: SweepState) -> (done: Int, failed: Int, notAttempted: Int) {
        var done = 0, failed = 0, notAttempted = 0
        for target in state.targets {
            switch target.outcome {
            case .done: done += 1
            case .failed: failed += 1
            case .notAttempted: notAttempted += 1
            }
        }
        return (done, failed, notAttempted)
    }

    public static func requireComplete(_ state: SweepState) throws {
        let leftover = unattemptedIds(state)
        guard leftover.isEmpty else {
            throw SweepError.incomplete(unattempted: leftover)
        }
        guard !state.targets.isEmpty else {
            throw SweepError.noTargets
        }
    }
}

public enum SweepError: Error, Equatable, Sendable {
    case noTargets
    case duplicateTargets([String])
    case notFound(id: String)
    case incomplete(unattempted: [String])
    case invalidState(id: String, status: SweepStatus)

    public var errorCode: String {
        switch self {
        case .noTargets: return "SWEEP_NO_TARGETS"
        case .duplicateTargets: return "SWEEP_DUPLICATE_TARGETS"
        case .notFound: return "SWEEP_NOT_FOUND"
        case .incomplete: return "SWEEP_INCOMPLETE"
        case .invalidState: return "SWEEP_INVALID_STATE"
        }
    }

    public var message: String {
        switch self {
        case .noTargets:
            return "sweep needs at least one target — pass --target, --targets, or --targets-file"
        case .duplicateTargets(let ids):
            return "duplicate sweep targets are refused (would hide a skip): \(ids.joined(separator: ", "))"
        case .notFound(let id):
            return "no sweep matches \(id)"
        case .incomplete(let leftover):
            return "sweep cannot report complete while targets remain not-attempted: \(leftover.joined(separator: ", "))"
        case .invalidState(let id, let status):
            return "sweep \(id) is \(status.rawValue) and cannot accept that transition"
        }
    }
}

/// Kill mid-target: the current target stays `not-attempted` and the sweep is interrupted.
public struct SweepInterrupt: Error, Equatable, Sendable {}
