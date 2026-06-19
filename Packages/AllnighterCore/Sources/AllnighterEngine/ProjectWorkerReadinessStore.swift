import Foundation
import AllnighterCore

/// PRJ-S07b: Allnighter's own cache of per-Project worker readiness — one JSON
/// file per project, atomically written. This is the cache the spec allows
/// ("Allnighter may write its own readiness cache; it must not write vendor
/// config"). `project workers` reads it; `project recheck-workers` reruns the
/// declared safe probes and rewrites it. It holds only the canonical
/// `ProjectWorkerReadiness` facts — never vendor trust/auth state.
public final class ProjectWorkerReadinessStore: @unchecked Sendable {
    public let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL = AllnighterPaths.projectReadiness, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    private func fileURL(projectId: String) -> URL {
        rootDirectory.appendingPathComponent("\(projectId).json")
    }

    private func ensureRoot() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    /// Cached readiness for one project (empty when never rechecked).
    public func load(projectId: String) -> [ProjectWorkerReadiness] {
        let url = fileURL(projectId: projectId)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let records = try? CoreJSON.decode([ProjectWorkerReadiness].self, from: data)
        else { return [] }
        return records
    }

    /// Replace the cached readiness for one project (full set from one recheck).
    public func save(projectId: String, _ records: [ProjectWorkerReadiness]) throws {
        try ensureRoot()
        try CoreJSON.encode(records).write(to: fileURL(projectId: projectId), options: .atomic)
    }

    /// Drop a project's cache (e.g. on archive/remove). Missing file is not an error.
    public func clear(projectId: String) {
        try? fileManager.removeItem(at: fileURL(projectId: projectId))
    }
}
