import Foundation
import AllnighterCore

/// Holds the driver manifests workers are invoked through. Manifests are data,
/// not code — load bundled defaults plus user overrides (overrides win by id).
public struct DriverRegistry: Sendable {
    private var manifests: [String: DriverManifest]

    public init(_ manifests: [DriverManifest] = []) {
        self.manifests = Dictionary(manifests.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func manifest(id: String) -> DriverManifest? {
        manifests[id]
    }

    public func manifest(for worker: Model) -> DriverManifest? {
        manifests[worker.driverId]
    }

    public var all: [DriverManifest] {
        Array(manifests.values)
    }

    public mutating func register(_ manifest: DriverManifest) {
        manifests[manifest.id] = manifest
    }

    /// Loads every `*.json` manifest in a directory, later files overriding by id.
    public static func loadDirectory(_ url: URL) throws -> DriverRegistry {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else {
            return DriverRegistry()
        }
        let loaded = try entries
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try CoreJSON.decode(DriverManifest.self, from: Data(contentsOf: $0)) }
        return DriverRegistry(loaded)
    }
}
