import AllnighterCore

/// An honest one-line cause for a failed / timed-out / no-output worker (bug list #8) — so
/// distinct causes (auth, rate limit, wrong CLI, timeout, empty output, cancelled) never
/// collapse into a single "timed out" label. Pure + tested. The capacity observation (when
/// present) is the truer cause behind a timeout/exit and wins.
enum WorkerFailurePresenter {
    static func cause(
        status: WorkerAnswerStatus,
        errorKind: WorkerAnswerErrorKind?,
        errorReason: String?,
        capacity: CapacityObservation?
    ) -> String? {
        if let capacity {
            switch capacity.kind {
            case .authRequired: return "Auth required — sign in to \(capacity.source)"
            case .accountRateLimit: return "Rate limited — \(capacity.source)"
            case .providerBusy: return "Provider busy — \(capacity.source)"
            case .cooldown: return "Cooling down — \(capacity.source)"
            case .manualRequired: return "Needs manual action — \(capacity.source)"
            case .unknownCapacity: break
            }
        }
        switch status {
        case .timedOut:
            return errorReason ?? "Timed out (no output)"
        case .failed:
            switch errorKind {
            case .authRequired: return "Auth required"
            case .missingCLI: return "CLI not installed / wrong CLI"
            case .emptyOutput: return "No output (exited cleanly, empty)"
            case .timedOut: return "Timed out (no output)"
            case .nonzeroExit: return errorReason ?? "Exited with an error"
            case .cancelled: return "Cancelled"
            case .none: return errorReason
            }
        case .cancelled:
            return "Cancelled"
        case .done, .queued, .running, .skipped:
            return nil
        }
    }

    /// Whether a partial answer was preserved — surfaced, never hidden behind the failure.
    static func hasPartialOutput(_ output: String?) -> Bool {
        !(output ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
