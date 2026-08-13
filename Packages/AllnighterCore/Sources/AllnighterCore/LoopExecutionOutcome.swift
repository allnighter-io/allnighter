import Foundation

/// Allnighter-owned record of one Loop execution (dev) turn.
///
/// OCL-S07: a frontier lead plans; a local seat may execute. Delegation multiplies
/// whatever the execution seat is — including false-done prose. Status and reasons
/// come from worker terminal status, `repoDelta`, declared proofs, standing
/// invariants, and write-scope — never from the seat's report text.
public struct LoopExecutionOutcome: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable, Equatable {
        /// Worker finished `.done`, the tree moved (or the turn was non-mutating),
        /// and no declared proof / standing invariant / scope check failed.
        case completed
        /// Worker failed/timed out, a proof or invariant failed, scope was
        /// violated, or a mutating turn left commit-range and worktree unchanged.
        case failed
    }

    public var status: Status
    /// Observed facts. Never copied from assistant prose.
    public var reasons: [String]

    public init(status: Status, reasons: [String]) {
        self.status = status
        self.reasons = reasons
    }

    /// `nil` when there is no execution run to judge (PM-only round, dispatch
    /// never started). Absence is not success.
    public static func evaluate(
        run: TeamRun?,
        proofResults: [HarnessProofResult] = [],
        standingFailed: [String]? = nil,
        scopeViolation: ScopeViolation? = nil
    ) -> LoopExecutionOutcome? {
        guard let run else { return nil }

        var failReasons: [String] = []
        var facts: [String] = []

        let answers = run.answers.filter { $0.result.status != .skipped }
        let worker = answers.first?.result
        let workerStatus = worker?.status
        facts.append("worker status \(workerStatus?.rawValue ?? "missing")")

        if workerStatus == .failed || workerStatus == .timedOut {
            if let reason = worker?.errorReason, !reason.isEmpty {
                failReasons.append("worker \(workerStatus!.rawValue): \(reason)")
            } else {
                failReasons.append("worker status \(workerStatus!.rawValue)")
            }
        } else if workerStatus != .done {
            failReasons.append("worker status \(workerStatus?.rawValue ?? "missing")")
        }

        let commitsLanded = run.repoDelta?.changed == true
        let worktreeDirty = run.repoDelta?.worktreeDirty == true
        let repoHadEffect = commitsLanded || worktreeDirty
        if repoHadEffect {
            facts.append("repo had effect")
        } else {
            facts.append("repo unchanged (commit-range and worktree)")
        }
        if run.mutating, workerStatus == .done, !repoHadEffect {
            failReasons.append("mutating turn produced no repo effect")
        }

        let declaredProofs = proofResults.filter { !$0.standing }
        if declaredProofs.isEmpty {
            facts.append("no declared proofs ran")
        } else {
            for proof in declaredProofs where !proof.passed {
                if proof.timedOut {
                    failReasons.append("declared proof timed out: \(proof.command)")
                } else {
                    let code = proof.exitCode.map(String.init) ?? "nil"
                    failReasons.append("declared proof `\(proof.command)` exited \(code)")
                }
            }
            if declaredProofs.allSatisfy(\.passed) {
                facts.append("declared proofs passed")
            }
        }

        if let standingFailed, !standingFailed.isEmpty {
            failReasons.append("standing invariants failed: \(standingFailed.joined(separator: ", "))")
        }
        if let scopeViolation {
            failReasons.append(scopeViolation.message)
        }

        if failReasons.isEmpty {
            return LoopExecutionOutcome(status: .completed, reasons: facts)
        }
        return LoopExecutionOutcome(status: .failed, reasons: failReasons)
    }

    /// Block injected into the next PM prompt. Never includes the seat's prose.
    public func promptBlock() -> String {
        var lines = [
            "## Allnighter execution outcome",
            "This block is Allnighter's record of the last execution seat — not the seat's prose.",
            "status: \(status.rawValue)",
        ]
        for reason in reasons {
            lines.append("- \(reason)")
        }
        lines.append(
            "The execution seat's own report is a claim, not evidence. Judge from these facts and the git range."
        )
        return lines.joined(separator: "\n")
    }
}
