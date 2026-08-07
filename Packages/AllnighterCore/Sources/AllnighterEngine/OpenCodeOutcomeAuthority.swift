import Foundation
import AgentOSCLI
import AllnighterCore

/// S122.2-outcome — Allnighter is the sole authority for OpenCode `mutating` runs.
/// Combines `OpenCodeTurnSignal` with `repoDelta` (S122.3). Never invents a second
/// incomplete label beyond the fixed names in the phase table.
public enum OpenCodeOutcomeAuthority: Sendable {
    public enum Verdict: Equatable, Sendable {
        case done(output: String?)
        case failed(reason: String)
    }

    /// Map a non-local idle end to a classified `errorReason` (F8).
    /// Keeps `stalled_no_progress` / `stream_drop` / `foreign_idle` / `timeout`
    /// visible in `alln show` instead of collapsing them all to
    /// `incomplete_no_final_message`.
    private static func classifiedFailure(for idleReason: OpenCodeIdleReason) -> String {
        idleReason.rawValue
    }

    /// CT-04: client already emitted a human-action / session / prompt terminal.
    /// Do not let a stale non-local `idleReason` on the signal rewrite it to
    /// `stream_drop` / `emptyOutput`.
    static func shouldPreserveExistingFailure(
        errorKind: WorkerAnswerErrorKind?,
        errorReason: String?
    ) -> Bool {
        if errorKind == .permissionRequired { return true }
        guard let errorReason, !errorReason.isEmpty else { return false }
        if errorReason == "blockedOn: permission" { return true }
        if errorReason.hasPrefix("opencode session error:") { return true }
        if errorReason.hasPrefix("opencode prompt_async:") { return true }
        return false
    }

    /// Apply the D3 outcome table. Returns nil when there is no OpenCode signal
    /// (non-OpenCode seats) — caller keeps the worker's terminal as-is.
    /// Also returns nil when the worker already carries a classified failure
    /// that must survive rewrite (CT-04).
    public static func resolve(
        signal: OpenCodeTurnSignal?,
        repoDelta: RepoDelta?,
        workerOutput: String?,
        existingErrorKind: WorkerAnswerErrorKind? = nil,
        existingErrorReason: String? = nil
    ) -> Verdict? {
        guard let signal else { return nil }

        if shouldPreserveExistingFailure(
            errorKind: existingErrorKind, errorReason: existingErrorReason
        ) {
            return nil
        }

        // CT-13: match AgentOS `emitTerminal` precedence — non-local idleReason
        // before promptEcho — so both layers agree on the classified reason.
        func failNonLocalIdle() -> Verdict? {
            switch signal.idleReason {
            case .foreignIdle, .streamDrop, .timeout, .stalledNoProgress:
                return .failed(reason: classifiedFailure(for: signal.idleReason))
            case .localIdle:
                return nil
            }
        }

        // answerOnly: client already decided; re-check foreign idle / echo.
        if signal.intent == .answerOnly {
            if let failed = failNonLocalIdle() { return failed }
            if signal.promptEcho { return .failed(reason: "incomplete_no_final_message") }
            if let text = signal.assistantText, !text.isEmpty {
                return .done(output: text)
            }
            return .failed(reason: "incomplete_no_final_message")
        }

        // mutating — sole authority here.
        if let failed = failNonLocalIdle() { return failed }
        if signal.promptEcho {
            return .failed(reason: "incomplete_no_final_message")
        }

        if let text = signal.assistantText, !text.isEmpty {
            return .done(output: text)
        }

        let commitsPresent = repoDelta?.commitsChanged == true
            || (repoDelta?.commits.isEmpty == false)
        let dirty = repoDelta?.worktreeDirty == true

        if signal.toolOnlySummary != nil {
            if commitsPresent {
                return .done(output: signal.toolOnlySummary ?? workerOutput)
            }
            if dirty {
                return .failed(reason: "incomplete_uncommitted")
            }
            return .failed(reason: "incomplete_no_final_message")
        }

        return .failed(reason: "incomplete_no_final_message")
    }

    /// Mutate a worker outcome in place from the verdict.
    public static func apply(_ verdict: Verdict, to outcome: inout WorkerRunOutcome) {
        switch verdict {
        case .done(let output):
            outcome.status = .done
            outcome.errorKind = nil
            outcome.errorReason = nil
            if let output { outcome.output = output }
        case .failed(let reason):
            outcome.status = .failed
            outcome.errorKind = .emptyOutput
            outcome.errorReason = reason
        }
    }
}
