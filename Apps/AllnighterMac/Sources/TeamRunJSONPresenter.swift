import Foundation
import AllnighterCore

/// Pure view-state that renders a public `TeamRunJSON` (the shared CLI/MCP/iOS
/// contract) into display-ready values for the Mac UI — with **no legacy field
/// translation**. This is the GUI-side proof for CLI M1 step 9: the same shape
/// `alln team --json` emits drives the app directly. Reads only new-vocabulary
/// fields (`workers`, `workerAnswers`, `stages`, `plan`, `errors`); it never sees
/// `seat`/`member`/`council`/`panel`/`masterPlan`. No SwiftUI/AppKit here.
struct TeamRunJSONPresenter {
    let run: TeamRunJSON

    var prompt: String { run.teamRun.prompt }
    var statusLabel: String { run.teamRun.status.rawValue }
    var planMarkdown: String? { run.plan?.markdown }
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
        run.workers.map { worker in
            let answer = run.workerAnswers.first { $0.workerId == worker.id }
            return WorkerRow(
                id: worker.id,
                modelName: worker.modelName,
                skillName: worker.skillName,
                statusLabel: (answer?.status ?? .queued).rawValue,
                durationMs: answer?.durationMs,
                answerMarkdown: answer?.markdown,
                failureReason: answer?.error?.message
            )
        }
    }

    var failedWorkers: [WorkerRow] { workerRows.filter(\.didFail) }
    var hasPlan: Bool { run.plan != nil }
}
