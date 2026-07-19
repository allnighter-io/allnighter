import Foundation

/// Frozen public run lifecycle (RLR-L3). The single wire vocabulary for
/// status, `--wait-for`, `ps` rows, and every JSON/NDJSON projection. Durable
/// `RunStatus` (with its multi-worker stage names) projects onto this via
/// `RunStatus.lifecycle`; nothing on disk stores `RunLifecycle` directly.
public enum RunLifecycle: String, Codable, Sendable, CaseIterable {
    case queued, running, done, failed, timedOut, cancelled

    public var isTerminal: Bool {
        switch self {
        case .queued, .running:
            return false
        case .done, .failed, .timedOut, .cancelled:
            return true
        }
    }
}

/// Frozen public phase axis (RLR-L3). Only meaningful for non-terminal runs;
/// terminal runs omit `phase`. `queued` runs are `waitingForWriteLock` or
/// `spawningWorker`; `running` runs are `working`, `proving`, or `settling`.
public enum RunPhase: String, Codable, Sendable, CaseIterable {
    case waitingForWriteLock, spawningWorker   // lifecycle == .queued
    case working, proving, settling            // lifecycle == .running

    /// The lifecycle this phase is legal under (RLR-L3 phase table).
    public var lifecycle: RunLifecycle {
        switch self {
        case .waitingForWriteLock, .spawningWorker:
            return .queued
        case .working, .proving, .settling:
            return .running
        }
    }
}
