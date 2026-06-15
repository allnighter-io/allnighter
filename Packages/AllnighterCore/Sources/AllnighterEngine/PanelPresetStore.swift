import Foundation
import AllnighterCore

/// File-backed registry of panel presets under `Config/PanelPresets/`. The
/// built-in six-worker default is injected by the app from the bundled panel
/// (its worker ids must match the live panel), so this store persists only what
/// the user saves. Newest-first by creation order via filename sort is not
/// meaningful for presets, so they are returned id-sorted for stable display.
public struct PanelPresetStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory
            ?? AllnighterPaths.config.appendingPathComponent("PanelPresets", isDirectory: true)
    }

    /// User-saved presets, id-sorted for stable display.
    public func load() -> [PanelPreset] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil
        ) else { return [] }
        return entries
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? CoreJSON.decode(PanelPreset.self, from: Data(contentsOf: $0)) }
    }

    @discardableResult
    public func save(_ preset: PanelPreset) throws -> URL {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let url = rootDirectory.appendingPathComponent("\(preset.id).json")
        try CoreJSON.encode(preset).write(to: url)
        return url
    }

    public func delete(id: String) throws {
        let url = rootDirectory.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
