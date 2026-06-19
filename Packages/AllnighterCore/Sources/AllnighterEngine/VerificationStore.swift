import Foundation
import AllnighterCore

/// PRJ-S12: durable per-project verification records. "Done" requires a record with
/// outcome `verified` or `waived`; a worker's claim never marks done on its own.
/// One JSON file per project.
public final class VerificationStore: @unchecked Sendable {
    public let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL = AllnighterPaths.projectVerifications, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    private func fileURL(projectId: String) -> URL {
        rootDirectory.appendingPathComponent("\(projectId).json")
    }

    private func ensureRoot() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    public func load(projectId: String) -> [VerificationRecord] {
        let url = fileURL(projectId: projectId)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let records = try? CoreJSON.decode([VerificationRecord].self, from: data)
        else { return [] }
        return records
    }

    @discardableResult
    public func append(_ record: VerificationRecord) throws -> VerificationRecord {
        try ensureRoot()
        var all = load(projectId: record.projectId)
        all.append(record)
        try CoreJSON.encode(all).write(to: fileURL(projectId: record.projectId), options: .atomic)
        return record
    }
}
