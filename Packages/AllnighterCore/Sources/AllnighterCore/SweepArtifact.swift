import Foundation

/// One sweep artifact: every target named with its honest outcome.
public struct SweepArtifactCard: Codable, Sendable, Equatable {
    public var sweepId: String
    public var order: String
    /// Computed honesty bit. Never true while any target is `not-attempted`.
    public var complete: Bool
    public var status: String
    public var doneCount: Int
    public var failedCount: Int
    public var notAttemptedCount: Int
    public var targets: [SweepTargetRecord]

    public init(from state: SweepState) {
        let counts = SweepHonesty.counts(state)
        sweepId = state.id
        order = state.order
        complete = SweepHonesty.canReportComplete(state)
        status = state.status.rawValue
        doneCount = counts.done
        failedCount = counts.failed
        notAttemptedCount = counts.notAttempted
        targets = state.targets
    }
}

public enum SweepArtifact {
    public static func project(_ state: SweepState) -> SweepArtifactCard {
        SweepArtifactCard(from: state)
    }

    public static func jsonData(_ card: SweepArtifactCard) throws -> Data {
        try CoreJSON.encode(card)
    }

    public static func markdown(_ card: SweepArtifactCard) -> String {
        var lines = [
            "# Sweep \(card.sweepId)",
            "",
            "order: \(card.order)",
            "status: \(card.status)",
            "complete: \(card.complete)",
            "done: \(card.doneCount)  failed: \(card.failedCount)  not-attempted: \(card.notAttemptedCount)",
            "",
            "| target | outcome | run | reason |",
            "| --- | --- | --- | --- |",
        ]
        for target in card.targets {
            let run = target.runId ?? ""
            let reason = target.reason ?? ""
            lines.append("| \(target.id) | \(target.outcome.rawValue) | \(run) | \(reason) |")
        }
        if !card.complete {
            lines.append("")
            lines.append("This sweep is not complete. Targets listed `not-attempted` were never attempted — resume; do not treat this artifact as done.")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
