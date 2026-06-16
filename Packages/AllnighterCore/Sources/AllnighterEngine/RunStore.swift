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

    /// The run's folder (created if needed). Used for dispatch artifacts (RB4).
    @discardableResult
    public func runDirectory(forRunId runId: String) throws -> URL {
        let directory = rootDirectory.appendingPathComponent("run_\(runId)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    public func save(_ run: TeamRun, models: [Model]) throws -> URL {
        let directory = rootDirectory.appendingPathComponent("run_\(run.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try CoreJSON.encode(run).write(to: directory.appendingPathComponent("run.json"))

        // Liveness marker: while a run is non-terminal, record the owning pid so a
        // reader can tell a genuinely-running run from an orphaned/crashed one.
        // Removed on terminal save so a clean run leaves no stale marker.
        let ownerURL = directory.appendingPathComponent("owner.pid")
        if run.status.isTerminal {
            try? FileManager.default.removeItem(at: ownerURL)
        } else {
            try? Data("\(RunStore.currentPID)".utf8).write(to: ownerURL)
        }

        // Derived artifacts (regenerated from run.json truth on each save).
        let bundle = RunMarkdown.bundle(run, models: models)
        try Data(bundle.utf8).write(to: directory.appendingPathComponent("bundle.md"))

        let analysis = RunMarkdown.analysis(run)
        if !analysis.isEmpty {
            try Data(analysis.utf8).write(to: directory.appendingPathComponent("analysis.md"))
        }

        if let plan = run.plan, !plan.isEmpty {
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

    /// Loads one run by id, applying orphan recovery (a non-terminal run whose
    /// owning process is gone resolves to `interrupted` — never falsely `running`,
    /// never silently absent). Returns nil only when no `run.json` exists.
    public func load(runId: String) -> TeamRun? {
        let directory = rootDirectory.appendingPathComponent("run_\(runId)", isDirectory: true)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("run.json")),
              let run = try? CoreJSON.decode(TeamRun.self, from: data) else { return nil }
        return recovered(run, directory: directory)
    }

    /// Lists saved runs, newest first, with orphan recovery applied.
    public func list() -> [TeamRun] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return entries
            .filter { $0.lastPathComponent.hasPrefix("run_") }
            .compactMap { dir -> TeamRun? in
                guard let run = try? CoreJSON.decode(TeamRun.self, from: Data(contentsOf: dir.appendingPathComponent("run.json"))) else { return nil }
                return recovered(run, directory: dir)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Orphan recovery

    /// Projects a non-terminal run to `interrupted` when its owning process is no
    /// longer alive (crash/orphan). A non-terminal run with a live owner pid is
    /// genuinely running and is returned unchanged. Pure: never writes on read.
    private func recovered(_ run: TeamRun, directory: URL) -> TeamRun {
        guard !run.status.isTerminal else { return run }
        if let pid = ownerPID(directory), RunStore.processAlive(pid) { return run }
        var orphan = run
        orphan.status = .interrupted
        return orphan
    }

    private func ownerPID(_ directory: URL) -> Int32? {
        guard let raw = try? String(contentsOf: directory.appendingPathComponent("owner.pid"), encoding: .utf8) else { return nil }
        return Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static var currentPID: Int32 { ProcessInfo.processInfo.processIdentifier }

    /// True when `pid` names a live process. `kill(pid, 0)` returns 0 when we can
    /// signal it, or fails with `EPERM` when it exists but we may not — both mean
    /// alive; `ESRCH` means gone.
    public static func processAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
