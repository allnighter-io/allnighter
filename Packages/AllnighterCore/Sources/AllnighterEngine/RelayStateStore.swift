import Foundation
import AllnighterCore

/// Persists `RelayState` to disk as one folder per relay — `relays/<id>/relay.json` —
/// mirroring `RunStore`'s per-id folder + atomic-write pattern (PM_Relay.md §6 R-S04).
/// `RelayCoordinator` saves after every round-level state change, so a relay is resumable
/// from disk at any point mid-round, never only in memory.
public struct RelayStateStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AllnighterPaths.relays
    }

    private func relayDirectory(id: String) throws -> URL {
        let directory = rootDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Atomic write (temp + rename) so a concurrent reader never sees a torn file.
    @discardableResult
    public func save(_ state: RelayState) throws -> URL {
        let directory = try relayDirectory(id: state.id)
        try CoreJSON.encode(state).write(to: directory.appendingPathComponent("relay.json"), options: .atomic)
        return directory
    }

    public func load(id: String) -> RelayState? {
        let url = rootDirectory.appendingPathComponent(id, isDirectory: true).appendingPathComponent("relay.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? CoreJSON.decode(RelayState.self, from: data)
    }

    /// All relays, newest first. Skips any folder whose `relay.json` fails to decode rather
    /// than failing the whole listing.
    public func list() -> [RelayState] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return entries
            .compactMap { load(id: $0.lastPathComponent) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
