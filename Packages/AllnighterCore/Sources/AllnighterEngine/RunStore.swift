import Foundation
import AllnighterCore

/// Persists runs to disk as a folder per run under Application Support. Flat
/// files now (Core models are `Codable`); GRDB is the documented growth path
/// when history/query needs exceed files.
public struct RunStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.rootDirectory = base
                .appendingPathComponent("Allnighter", isDirectory: true)
                .appendingPathComponent("Runs", isDirectory: true)
        }
    }

    @discardableResult
    public func save(_ run: CouncilRun, workers: [Worker]) throws -> URL {
        let directory = rootDirectory.appendingPathComponent("run_\(run.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try CoreJSON.encode(run).write(to: directory.appendingPathComponent("run.json"))

        let bundle = RunMarkdown.bundle(run, workers: workers)
        try Data(bundle.utf8).write(to: directory.appendingPathComponent("bundle.md"))

        if let plan = run.synthesis?.masterPlanMarkdown, !plan.isEmpty {
            try Data(plan.utf8).write(to: directory.appendingPathComponent("master_plan.md"))
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
