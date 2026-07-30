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
        /// CLIs the user has parked (ignored) — not probed, not seated, quiet in Needs attention.
        /// Sorted unique driver ids. Code SSOT for park intent; GUI/CLI both mutate this.
        public var parkedDriverIds: [String]

        public init(
            records: [ToolProbeRecord] = [],
            setupCompletedAt: Date? = nil,
            assembledTeam: TeamAssembler.Assembled? = nil,
            parkedDriverIds: [String] = []
        ) {
            self.records = records
            self.setupCompletedAt = setupCompletedAt
            self.assembledTeam = assembledTeam
            self.parkedDriverIds = Array(Set(parkedDriverIds)).sorted()
        }

        public var parkedSet: Set<String> { Set(parkedDriverIds) }

        public mutating func park(_ driverId: String) {
            parkedDriverIds = Array(Set(parkedDriverIds).union([driverId])).sorted()
        }

        public mutating func unpark(_ driverId: String) {
            parkedDriverIds = parkedDriverIds.filter { $0 != driverId }
        }

        public func isParked(_ driverId: String) -> Bool {
            parkedDriverIds.contains(driverId)
        }

        enum CodingKeys: String, CodingKey {
            case records, setupCompletedAt, assembledTeam, parkedDriverIds
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            records = try c.decodeIfPresent([ToolProbeRecord].self, forKey: .records) ?? []
            setupCompletedAt = try c.decodeIfPresent(Date.self, forKey: .setupCompletedAt)
            assembledTeam = try c.decodeIfPresent(TeamAssembler.Assembled.self, forKey: .assembledTeam)
            parkedDriverIds = Array(Set(try c.decodeIfPresent([String].self, forKey: .parkedDriverIds) ?? [])).sorted()
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(records, forKey: .records)
            try c.encodeIfPresent(setupCompletedAt, forKey: .setupCompletedAt)
            try c.encodeIfPresent(assembledTeam, forKey: .assembledTeam)
            try c.encode(parkedDriverIds, forKey: .parkedDriverIds)
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
