import Foundation
import CryptoKit

/// PRJ-S10: derives a dispatchable `WorkOrder` from an approved `ProjectProposal`,
/// deterministically (no model call — the proposal already carries the judgment).
/// Pure: git head + root come from the caller (the CLI re-observes at approval).
/// A work order always names proof (project commands or an explicit waiver) and an
/// expected return — the inference ban against silent "done".
public enum WorkOrderBuilder {

    public static func build(
        from proposal: ProjectProposal,
        project: Project,
        baseGitHead: String?,
        now: Date,
        idSuffix: String
    ) -> WorkOrder {
        let lane = proposal.suggestedLane.map(laneFor) ?? .none
        let proofCommands = project.proofCommands
        // "Proof commands OR an explicit waiver" — never silently nothing.
        let waiver: String? = proofCommands.isEmpty
            ? "No proof commands are declared for this project. Proof is reveal-only: the user runs proof, or verification is needs-human."
            : nil
        return WorkOrder(
            id: "wo_" + idSuffix,
            proposalId: proposal.id,
            projectId: project.id,
            title: proposal.title,
            lane: lane,
            mode: .reveal,                       // dispatch is an explicit S11 action
            promptBody: promptBody(for: proposal, project: project),
            scope: proposal.scope,
            nonGoals: proposal.nonGoals,
            constraints: proposal.risks,         // risks/unknowns travel as constraints
            expectedReturn: expectedReturn(for: proposal.kind),
            proofCommands: proofCommands,
            proofWaiver: waiver,
            baseGitHead: baseGitHead,
            localRootPathSnapshot: project.normalizedRootPath,
            createdAt: now
        )
    }

    /// The canonical hash of a proposal's editable content — recorded at approval so
    /// dispatch can detect edits-after-approval. Excludes status/timestamps/ids.
    public static func approvalContentHash(_ p: ProjectProposal) -> String {
        let material = [
            p.kind.rawValue, p.title, p.whyNow, p.userGoal, p.scope,
            p.currentTruth.joined(separator: "\u{1F}"),
            p.nonGoals.joined(separator: "\u{1F}"),
            p.likelyFilesOrAreas.joined(separator: "\u{1F}"),
            p.risks.joined(separator: "\u{1F}"),
            p.blockingQuestions.joined(separator: "\u{1F}"),
            p.suggestedLane?.rawValue ?? "", p.suggestedTeamId ?? "", p.suggestedEffort?.rawValue ?? "",
        ].joined(separator: "\u{1E}")
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Derivations

    static func laneFor(_ lane: WorkLane) -> WorkOrderLane {
        switch lane {
        case .code: return .code
        case .design: return .design
        case .copy: return .copy
        case .signal: return .none      // signal is not a mutating craft lane
        }
    }

    static func expectedReturn(for kind: ProposalKind) -> String {
        switch kind {
        case .execute_slice: return "A diff implementing the scope, plus the output of the declared proof commands."
        case .spec_explore: return "A synthesis of findings and 1–3 candidate work orders for human decision."
        case .synthesis_review: return "An interpretation of team agreement/contradiction and a recommended decision."
        case .docs_reconcile: return "Docs updated to match committed truth, plus a stale-reference scan."
        case .verify_completion: return "A verification record: proof results, scope findings, and git observation."
        case .audit: return "Findings with locations, or an explicit no-findings report."
        case .deslop: return "A behavior-preserving cleanup with proof that behavior is unchanged."
        case .ask_user: return "An answer to the blocking question(s)."
        case .wait: return "(no work — gates are red)"
        }
    }

    static func promptBody(for p: ProjectProposal, project: Project) -> String {
        var lines: [String] = []
        lines.append("# \(p.title)")
        if !p.userGoal.isEmpty { lines.append("\nGoal: \(p.userGoal)") }
        if !p.currentTruth.isEmpty { lines.append("\nCurrent truth:\n" + p.currentTruth.map { "- \($0)" }.joined(separator: "\n")) }
        if !p.scope.isEmpty { lines.append("\nScope:\n\(p.scope)") }
        if !p.nonGoals.isEmpty { lines.append("\nNon-goals:\n" + p.nonGoals.map { "- \($0)" }.joined(separator: "\n")) }
        if !p.likelyFilesOrAreas.isEmpty { lines.append("\nLikely files/areas:\n" + p.likelyFilesOrAreas.map { "- \($0)" }.joined(separator: "\n")) }
        if !p.risks.isEmpty { lines.append("\nRisks/constraints:\n" + p.risks.map { "- \($0)" }.joined(separator: "\n")) }
        lines.append("\nRoot: \(project.localRootPath)")
        lines.append("Expected return: \(expectedReturn(for: p.kind))")
        return lines.joined(separator: "\n")
    }
}
