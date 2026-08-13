import Foundation
import AgentOSTeam

/// Result of one dispatched attempt against a sweep target.
///
/// `notFinished` leaves the target `not-attempted` so resume retries it.
/// Never map an unattempted or interrupted run to `done`.
public enum SweepAttempt: Sendable, Equatable {
    case done(runId: String)
    case failed(runId: String?, reason: String)
    case notFinished(runId: String?)
}

public protocol SweepTargetExecuting: Sendable {
    func attempt(order: String, targetId: String) async throws -> SweepAttempt
}

public protocol SweepPersisting: Sendable {
    func save(_ state: SweepState) throws
    func load(id: String) throws -> SweepState?
    /// Writes the one sweep artifact. Returns the absolute path recorded on state.
    func writeArtifact(_ state: SweepState, json: Data, markdown: String) throws -> String
}

/// Maps a `TeamRun` (existing run journal) onto a sweep attempt. Skipped workers
/// and interrupted runs are never `done`.
public enum SweepRunOutcome {
    public static func map(_ run: TeamRun) -> SweepAttempt {
        if !run.status.isTerminal {
            return .notFinished(runId: run.id)
        }
        if run.status == .interrupted {
            return .notFinished(runId: run.id)
        }
        if run.status == .cancelled {
            return .failed(runId: run.id, reason: "run cancelled")
        }
        if run.status == .failed || run.status == .timedOut {
            let reason = run.answers.compactMap(\.result.errorReason).first
                ?? run.status.rawValue
            return .failed(runId: run.id, reason: reason)
        }

        let attempted = run.answers.filter { $0.result.status != .skipped }
        if attempted.isEmpty {
            return .failed(runId: run.id, reason: "no worker attempted the target")
        }
        if attempted.contains(where: { $0.result.status == .failed || $0.result.status == .timedOut }) {
            let reason = attempted.compactMap(\.result.errorReason).first
                ?? "worker failed"
            return .failed(runId: run.id, reason: reason)
        }
        if run.status == .done || run.status == .complete || run.status == .partial {
            return .done(runId: run.id)
        }
        return .failed(runId: run.id, reason: "unclassified status \(run.status.rawValue)")
    }
}
