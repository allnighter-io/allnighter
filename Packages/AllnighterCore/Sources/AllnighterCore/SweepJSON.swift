import Foundation

/// Machine contract for `alln sweep start|resume|status`.
public struct SweepJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var sweepId: String
    public var order: String
    public var projectRoot: String
    public var modelId: String?
    public var status: String
    /// Honesty bound. False whenever any target is `not-attempted`.
    public var complete: Bool
    public var doneCount: Int
    public var failedCount: Int
    public var notAttemptedCount: Int
    public var targets: [SweepTargetRecord]
    public var artifactPath: String?
    public var nextAction: String?

    public static func project(
        _ state: SweepState,
        contractVersion: String = ContractRegistry.contractVersion
    ) -> SweepJSON {
        let counts = SweepHonesty.counts(state)
        let complete = SweepHonesty.canReportComplete(state)
        let next: String?
        if complete {
            next = nil
        } else {
            next = "alln sweep resume \(state.id) --json"
        }
        return SweepJSON(
            schemaVersion: 1,
            contractVersion: contractVersion,
            sweepId: state.id,
            order: state.order,
            projectRoot: state.projectRoot,
            modelId: state.modelId,
            status: state.status.rawValue,
            complete: complete,
            doneCount: counts.done,
            failedCount: counts.failed,
            notAttemptedCount: counts.notAttempted,
            targets: state.targets,
            artifactPath: state.artifactPath,
            nextAction: next
        )
    }
}
