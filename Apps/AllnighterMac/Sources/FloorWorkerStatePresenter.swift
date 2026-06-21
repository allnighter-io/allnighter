import SwiftUI
import AllnighterCore

/// Pure presentation for a Factory Floor worker's state + response time (bug list #2).
/// Derives the dot color and the duration label honestly from persisted timing — never
/// from view mount time. Kept pure so the running/done/failed/timed-out cases are tested.
enum FloorWorkerStatePresenter {
    enum Dot: Equatable {
        case running   // blue — live
        case done      // amber — a finished reply (new-message feel)
        case failed    // red — failed / timed out / cancelled
        case neutral   // queued / skipped — honest, not a fake success/failure

        var color: Color {
            switch self {
            case .running: return ALPalette.blue500
            case .done: return ALColor.accent
            case .failed: return ALPalette.red400
            case .neutral: return ALColor.textFaint
            }
        }
    }

    static func dot(status: String) -> Dot {
        switch WorkerAnswerStatus(rawValue: status) {
        case .running: return .running
        case .done: return .done
        case .failed, .timedOut, .cancelled: return .failed
        case .queued, .skipped, .none: return .neutral
        }
    }

    /// The response-time label. Terminal workers use `durationMs` (else finishedAt-startedAt);
    /// a running worker shows live elapsed from `startedAt`; queued/skipped show nothing.
    static func durationLabel(
        status: String, startedAt: Date?, finishedAt: Date?, durationMs: Int?, now: Date
    ) -> String? {
        switch WorkerAnswerStatus(rawValue: status) {
        case .running:
            guard let startedAt else { return nil }
            return format(seconds: now.timeIntervalSince(startedAt))
        case .done, .failed, .timedOut, .cancelled:
            if let durationMs { return format(seconds: Double(durationMs) / 1000) }
            if let startedAt, let finishedAt { return format(seconds: finishedAt.timeIntervalSince(startedAt)) }
            return nil
        case .queued, .skipped, .none:
            return nil
        }
    }

    private static func format(seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 1 { return String(format: "%.0fms", s * 1000) }
        if s < 60 { return String(format: "%.1fs", s) }
        let m = Int(s) / 60
        let rem = Int(s) % 60
        return "\(m)m \(rem)s"
    }
}
