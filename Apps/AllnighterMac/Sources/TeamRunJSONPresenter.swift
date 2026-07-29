import Foundation
import AllnighterCore

/// Pure view-state that renders a public `TeamRunJSON` (the shared CLI/iOS
/// contract) into display-ready values for the Mac UI — with **no legacy field
/// translation**. This is the GUI-side proof for CLI M1 step 9: the same shape
/// `alln team --json` emits drives the app directly. Reads only new-vocabulary
/// fields (`agents`, `answers`, `answer`, `stages`, `plan`, `errors`); it never sees
/// `seat`/`member`/`council`/`panel`/`masterPlan`. No SwiftUI/AppKit here.
struct TeamRunJSONPresenter {
    let run: TeamRunJSON

    var prompt: String { run.teamRun.prompt }
    var statusLabel: String { run.teamRun.status.rawValue }
    /// Canonical result text. Prefer `answer.markdown`; plan/agent rows no longer duplicate it.
    var planMarkdown: String? { run.answer?.markdown ?? run.plan?.markdown }
    var answerMarkdown: String? { run.answer?.markdown }
    var planWriterAgentId: String? { run.teamRun.planWriterAgentId }
    var stageSummaries: [String] { run.stages.map { "\($0.purpose.rawValue): \($0.status.rawValue)" } }

    struct AgentRow: Identifiable {
        let id: String
        let modelName: String
        let skillName: String?
        let statusLabel: String
        let durationMs: Int?
        let answerMarkdown: String?
        /// Honest failure surface — a failed agent is shown failed, never hidden.
        let failureReason: String?
        var didFail: Bool { failureReason != nil }
    }

    var agentRows: [AgentRow] {
        run.agents.map { agent in
            let answer = run.answers.first { $0.agentId == agent.id }
            // One-agent canonical text lives on `run.answer`; surface it on that row.
            let seatMarkdown = answer?.markdown.flatMap { $0.isEmpty ? nil : $0 }
            let rowMarkdown = seatMarkdown
                ?? (run.answer?.source.agentId == agent.id ? run.answer?.markdown : nil)
            return AgentRow(
                id: agent.id,
                modelName: agent.modelName,
                skillName: agent.skillName,
                statusLabel: (answer?.status ?? .queued).rawValue,
                durationMs: answer?.durationMs,
                answerMarkdown: rowMarkdown,
                failureReason: answer?.error?.message
            )
        }
    }

    var failedAgents: [AgentRow] { agentRows.filter(\.didFail) }
    var hasPlan: Bool { run.plan != nil || run.answer?.source.kind == .plan }
    var hasAnswer: Bool { run.answer?.markdown != nil }
}
