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
    /// Canonical result text. Prefer `answer.markdown`; plan/worker rows no longer duplicate it.
    var planMarkdown: String? { run.answer?.markdown ?? run.plan?.markdown }
    var answerMarkdown: String? { run.answer?.markdown }
    var planWriterWorkerId: String? { run.teamRun.planWriterWorkerId }
    var stageSummaries: [String] { run.stages.map { "\($0.purpose.rawValue): \($0.status.rawValue)" } }

    struct WorkerRow: Identifiable {
        let id: String
        let modelName: String
        let skillName: String?
        let statusLabel: String
        let durationMs: Int?
        let answerMarkdown: String?
        /// Honest failure surface — a failed worker is shown failed, never hidden.
        let failureReason: String?
        var didFail: Bool { failureReason != nil }
    }

    var workerRows: [WorkerRow] {
        run.agents.map { worker in
            let answer = run.answers.first { $0.agentId == worker.id || $0.agentId == worker.agentId }
            // One-worker canonical text lives on `run.answer`; surface it on that row.
            let seatMarkdown = answer?.markdown.flatMap { $0.isEmpty ? nil : $0 }
            let rowMarkdown = seatMarkdown
                ?? (run.answer?.source.workerId == worker.id ? run.answer?.markdown : nil)
            return WorkerRow(
                id: worker.id,
                modelName: worker.modelName,
                skillName: worker.skillName,
                statusLabel: (answer?.status ?? .queued).rawValue,
                durationMs: answer?.durationMs,
                answerMarkdown: rowMarkdown,
                failureReason: answer?.error?.message
            )
        }
    }

    var failedWorkers: [WorkerRow] { workerRows.filter(\.didFail) }
    var hasPlan: Bool { run.plan != nil || run.answer?.source.kind == .plan }
    var hasAnswer: Bool { run.answer?.markdown != nil }
}
