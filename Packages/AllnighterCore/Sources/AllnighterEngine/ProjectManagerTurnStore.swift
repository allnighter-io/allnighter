import Foundation
import AllnighterCore

/// PRJ-S08: durable record of Project Manager turns — the "recorded as run truth"
/// requirement (a Manager answer is as auditable as any worker output). One
/// append-only JSON log per project. Manager turns are model OUTPUTS recorded for
/// audit, never Project truth: Project/git/proof win on any conflict.
public final class ProjectManagerTurnStore: @unchecked Sendable {
    public let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL = AllnighterPaths.projectManagerTurns, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    private func fileURL(projectId: String) -> URL {
        rootDirectory.appendingPathComponent("\(projectId).json")
    }

    private func ensureRoot() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    /// All recorded turns for a project, oldest first.
    public func load(projectId: String) -> [ProjectManagerTurn] {
        let url = fileURL(projectId: projectId)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let turns = try? CoreJSON.decode([ProjectManagerTurn].self, from: data)
        else { return [] }
        return turns
    }

    /// Append one turn to the project's log (run truth).
    @discardableResult
    public func append(_ turn: ProjectManagerTurn) throws -> ProjectManagerTurn {
        try ensureRoot()
        var turns = load(projectId: turn.projectId)
        turns.append(turn)
        try CoreJSON.encode(turns).write(to: fileURL(projectId: turn.projectId), options: .atomic)
        return turn
    }
}
