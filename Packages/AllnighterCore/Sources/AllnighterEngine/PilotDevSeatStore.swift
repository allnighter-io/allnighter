import Foundation
import AllnighterCore

/// Per-project remembered dev seat for Pilot (`Pilot_DX.md §DX4`). Lives beside the
/// project readiness cache — same `ProjectReadiness/` tree, separate file.
public struct PilotDevSeatPreference: Codable, Sendable, Equatable {
    public var devWorkerId: String
    public var updatedAt: Date

    public init(devWorkerId: String, updatedAt: Date) {
        self.devWorkerId = devWorkerId
        self.updatedAt = updatedAt
    }
}

public final class PilotDevSeatStore: @unchecked Sendable {
    public let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL = AllnighterPaths.projectReadiness, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    private func fileURL(projectId: String) -> URL {
        rootDirectory.appendingPathComponent("\(projectId)-pilot-dev-seat.json")
    }

    public func load(projectId: String) -> PilotDevSeatPreference? {
        let url = fileURL(projectId: projectId)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let pref = try? CoreJSON.decode(PilotDevSeatPreference.self, from: data)
        else { return nil }
        return pref
    }

    public func save(projectId: String, devWorkerId: String, now: Date = Date()) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let pref = PilotDevSeatPreference(devWorkerId: devWorkerId, updatedAt: now)
        try CoreJSON.encode(pref).write(to: fileURL(projectId: projectId), options: .atomic)
    }
}
