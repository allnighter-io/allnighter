import Foundation
import AllnighterCore

/// PRJ-S11b: durable per-project work returns — the captured output of a dispatched
/// work order. A return is NOT proof by itself (S12 verification decides done). One
/// JSON file per project.
public final class WorkReturnStore: @unchecked Sendable {
    public let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL = AllnighterPaths.projectWorkReturns, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    private func fileURL(projectId: String) -> URL {
        rootDirectory.appendingPathComponent("\(projectId).json")
    }

    private func ensureRoot() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    public func load(projectId: String) -> [WorkReturn] {
        let url = fileURL(projectId: projectId)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let returns = try? CoreJSON.decode([WorkReturn].self, from: data)
        else { return [] }
        return returns
    }

    @discardableResult
    public func append(_ ret: WorkReturn) throws -> WorkReturn {
        try ensureRoot()
        var all = load(projectId: ret.projectId)
        all.append(ret)
        try CoreJSON.encode(all).write(to: fileURL(projectId: ret.projectId), options: .atomic)
        return ret
    }
}
