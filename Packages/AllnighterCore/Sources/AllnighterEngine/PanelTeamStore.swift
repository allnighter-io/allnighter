import Foundation
import AllnighterCore

/// Per-project remembered last-used panel team (`docs/phases/Pilot_Panel.md`
/// decision 4 / PN-S04). Lives beside `PilotDevSeatStore` under ProjectReadiness.
public struct PanelTeamPreference: Codable, Sendable, Equatable {
    public var teamId: String
    public var updatedAt: Date

    public init(teamId: String, updatedAt: Date) {
        self.teamId = teamId
        self.updatedAt = updatedAt
    }
}

public final class PanelTeamStore: @unchecked Sendable {
    public let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL = AllnighterPaths.projectReadiness, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    private func fileURL(projectId: String) -> URL {
        rootDirectory.appendingPathComponent("\(projectId)-panel-team.json")
    }

    public func load(projectId: String) -> PanelTeamPreference? {
        let url = fileURL(projectId: projectId)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let pref = try? CoreJSON.decode(PanelTeamPreference.self, from: data)
        else { return nil }
        return pref
    }

    public func save(projectId: String, teamId: String, now: Date = Date()) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let pref = PanelTeamPreference(teamId: teamId, updatedAt: now)
        try CoreJSON.encode(pref).write(to: fileURL(projectId: projectId), options: .atomic)
    }
}
