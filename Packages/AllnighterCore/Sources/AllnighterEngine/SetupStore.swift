import Foundation
import AllnighterCore

/// Persists the first-run CLI-detection cache and the setup-completed flag under
/// `AllnighterPaths.config` (docs/phases/setup/01 §7, §9). One small JSON file so
/// the badge/roster can populate instantly on launch from cache, then refresh in
/// the background. The canonical source of truth shared by Doctor and Setup.
public struct SetupStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AllnighterPaths.config.appendingPathComponent("cli_setup.json")
    }

    public struct State: Codable, Sendable, Equatable {
        public var records: [ToolProbeRecord]
        public var setupCompletedAt: Date?
        /// The Bench/default Team assembled from ready sources (docs/phases/setup/01 §8).
        public var assembledTeam: TeamAssembler.Assembled?

        public init(records: [ToolProbeRecord] = [], setupCompletedAt: Date? = nil, assembledTeam: TeamAssembler.Assembled? = nil) {
            self.records = records
            self.setupCompletedAt = setupCompletedAt
            self.assembledTeam = assembledTeam
        }
    }

    public func load() -> State {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? CoreJSON.decode(State.self, from: data) else {
            return State()
        }
        return state
    }

    @discardableResult
    public func save(_ state: State) throws -> URL {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try CoreJSON.encode(state).write(to: fileURL)
        return fileURL
    }

    /// Marks first-run setup complete, preserving the latest records.
    public func markCompleted(records: [ToolProbeRecord], at date: Date) throws {
        try save(State(records: records, setupCompletedAt: date))
    }
}
