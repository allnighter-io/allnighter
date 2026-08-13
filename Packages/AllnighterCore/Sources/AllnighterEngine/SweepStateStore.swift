import Foundation
import AllnighterCore

/// Persists one sweep folder: `Sweeps/<id>/sweep.json` plus the one artifact.
/// `owner.pid` follows `LoopStateStore` so a dead owner reconciles to interrupted
/// rather than remaining falsely `running`.
public struct SweepStateStore: SweepPersisting, Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AllnighterPaths.sweeps
    }

    private func directory(id: String) throws -> URL {
        let directory = rootDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func save(_ state: SweepState) throws {
        let directory = try directory(id: state.id)
        let ownerURL = directory.appendingPathComponent("owner.pid")
        if state.status == .running {
            try Data("\(ProcessInfo.processInfo.processIdentifier)".utf8).write(to: ownerURL, options: .atomic)
        }
        try CoreJSON.encode(state).write(
            to: directory.appendingPathComponent("sweep.json"),
            options: .atomic
        )
        if state.status != .running {
            try? FileManager.default.removeItem(at: ownerURL)
        }
    }

    public func load(id: String) throws -> SweepState? {
        let url = rootDirectory.appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("sweep.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try CoreJSON.decode(SweepState.self, from: data)
    }

    public func writeArtifact(_ state: SweepState, json: Data, markdown: String) throws -> String {
        let directory = try directory(id: state.id)
        let jsonURL = directory.appendingPathComponent("artifact.json")
        let mdURL = directory.appendingPathComponent("artifact.md")
        try json.write(to: jsonURL, options: .atomic)
        try Data(markdown.utf8).write(to: mdURL, options: .atomic)
        return jsonURL.path
    }

    /// Missing or dead `owner.pid` counts as dead — never assume alive without proof.
    public func isOwnerDead(id: String) -> Bool {
        let ownerURL = rootDirectory.appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("owner.pid")
        guard let raw = try? String(contentsOf: ownerURL, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return true
        }
        return !RunStore.processAlive(pid)
    }
}
