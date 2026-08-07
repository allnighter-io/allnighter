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

    /// Apply the D3 outcome table. Returns nil when there is no OpenCode signal
    /// (non-OpenCode seats) — caller keeps the worker's terminal as-is.
    public static func resolve(
        signal: OpenCodeTurnSignal?,
        repoDelta: RepoDelta?,
        workerOutput: String?
    ) -> Verdict? {
        guard let signal else { return nil }

        // answerOnly: client already decided; re-check promptEcho / foreign idle.
        if signal.intent == .answerOnly {
            if signal.promptEcho { return .failed(reason: "incomplete_no_final_message") }
            switch signal.idleReason {
            case .foreignIdle, .streamDrop, .timeout, .stalledNoProgress:
                return .failed(reason: "incomplete_no_final_message")
            case .localIdle:
                break
            }
            if let text = signal.assistantText, !text.isEmpty {
                return .done(output: text)
            }
            return .failed(reason: "incomplete_no_final_message")
        }

        // mutating — sole authority here.
        if signal.promptEcho {
            return .failed(reason: "incomplete_no_final_message")
        }
        switch signal.idleReason {
        case .foreignIdle, .streamDrop, .timeout, .stalledNoProgress:
            return .failed(reason: "incomplete_no_final_message")
        case .localIdle:
            break
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
