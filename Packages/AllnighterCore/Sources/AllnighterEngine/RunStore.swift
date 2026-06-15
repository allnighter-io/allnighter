import Foundation
import AllnighterCore

/// Persists runs to disk as a folder per run under Application Support. Flat
/// files now (Core models are `Codable`); GRDB is the documented growth path
/// when history/query needs exceed files.
public struct RunStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AllnighterPaths.runs
    }

    @discardableResult
    public func save(_ run: CouncilRun, workers: [Worker]) throws -> URL {
        let directory = rootDirectory.appendingPathComponent("run_\(run.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try CoreJSON.encode(run).write(to: directory.appendingPathComponent("run.json"))

        // Derived artifacts (regenerated from run.json truth on each save).
        let bundle = RunMarkdown.bundle(run, workers: workers)
        try Data(bundle.utf8).write(to: directory.appendingPathComponent("bundle.md"))

        let analysis = RunMarkdown.analysis(run)
        if !analysis.isEmpty {
            try Data(analysis.utf8).write(to: directory.appendingPathComponent("analysis.md"))
        }

        if let plan = run.masterPlan, !plan.isEmpty {
            try Data(plan.utf8).write(to: directory.appendingPathComponent("master_plan.md"))
        }

        // RB artifacts, all derived from run.json stages.
        for review in RunMarkdown.latestReviews(run) where review.status == .done {
            let lensId = review.payload?.review?.lensId ?? review.promptProfileId ?? review.id
            if let md = review.payload?.markdown {
                try Data(md.utf8).write(to: directory.appendingPathComponent("review_\(lensId).md"))
            }
        }
        let finalSpec = RunMarkdown.finalSpec(run)
        if !finalSpec.isEmpty {
            try Data(finalSpec.utf8).write(to: directory.appendingPathComponent("final_spec.md"))
        }
        return directory
    }

    /// Lists saved runs, newest first.
    public func list() -> [CouncilRun] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return entries
            .filter { $0.lastPathComponent.hasPrefix("run_") }
            .compactMap { try? CoreJSON.decode(CouncilRun.self, from: Data(contentsOf: $0.appendingPathComponent("run.json"))) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
