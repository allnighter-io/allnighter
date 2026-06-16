import Foundation

/// Full spec/result retrieval for messaging agents (Agent_First §Full Spec
/// Retrieval). Lets an agent present a concise answer and then reveal the complete
/// packet without opening the GUI. Failed workers and warnings are ALWAYS included
/// in full detail — never summarized away. Pure projection over a persisted run.
public enum SpecRetrieval {
    public enum Detail: String, Codable, Sendable, CaseIterable {
        case summary
        case full
        case artifactRefsOnly
    }

    public struct FailedWorker: Codable, Sendable, Equatable {
        public var workerId: String
        public var skillName: String?
        public var reason: String
    }

    public struct Result: Codable, Sendable, Equatable {
        public var schemaVersion = 1
        public var runId: String
        public var status: String
        public var lane: String?
        public var teamPresetId: String?
        public var outputKind: String?
        public var selector: String
        public var detail: String
        /// Chat-optimized short answer (always present).
        public var summary: String
        /// Complete markdown packet — present only for `detail: full`.
        public var full: String?
        public var warnings: [String]
        /// Failed/timed-out workers, always surfaced honestly.
        public var failedWorkers: [FailedWorker]
        /// Local paths/ids for agents that will fetch/export.
        public var artifactRefs: [String]
    }

    public static func project(
        run: TeamRun,
        models: [Model],
        detail: Detail,
        selector: String = "latest",
        artifactRefs: [String] = []
    ) -> Result {
        let modelName = Dictionary(models.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let skillNameByWorker = Dictionary(run.workers.map { ($0.id, $0.skillName ?? $0.skillId) }, uniquingKeysWith: { a, _ in a })
        let plan = run.plan
        let modelCount = Set(run.workers.map(\.modelId)).count
        let failed = run.failedWorkerAnswers.map {
            FailedWorker(workerId: $0.workerId, skillName: skillNameByWorker[$0.workerId] ?? nil,
                         reason: $0.errorReason ?? $0.status.rawValue)
        }

        var summaryLines = [
            "\(run.teamDisplayName ?? run.presetId ?? "Team") · \(run.status.rawValue) · \(run.workers.count) workers / \(modelCount) model\(modelCount == 1 ? "" : "s")"
        ]
        if let plan { summaryLines.append(String(plan.prefix(400))) }
        else { summaryLines.append("(no synthesized output — status \(run.status.rawValue))") }
        if !failed.isEmpty {
            let names = failed.map { $0.skillName ?? $0.workerId }.joined(separator: ", ")
            summaryLines.append("Failed workers: \(names)")
        }
        _ = modelName // reserved for richer per-worker summaries

        return Result(
            runId: run.id, status: run.status.rawValue, lane: run.lane?.rawValue,
            teamPresetId: run.presetId, outputKind: run.outputKind?.rawValue,
            selector: selector, detail: detail.rawValue,
            summary: summaryLines.joined(separator: "\n"),
            full: detail == .full ? (plan ?? "") : nil,
            warnings: run.warnings, failedWorkers: failed, artifactRefs: artifactRefs)
    }
}
