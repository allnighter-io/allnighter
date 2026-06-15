import Foundation
import AllnighterCore

/// File-backed registry of synthesis instruction presets. The built-in default
/// is always present; user-authored presets are persisted one JSON file each
/// under `Config/InstructionPresets/`. Flat files now (Core models are
/// `Codable`); GRDB is the documented growth path if this ever needs queries.
public struct SynthesisInstructionStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory
            ?? AllnighterPaths.config.appendingPathComponent("InstructionPresets", isDirectory: true)
    }

    /// The canonical built-in default, derived from `SynthesisInstructions` so
    /// there is a single source of truth for the default master-plan prompt.
    public static var builtInDefault: SynthesisInstructionPreset {
        SynthesisInstructionPreset(
            id: SynthesisInstructions.defaultID,
            displayName: "Master Plan (default)",
            template: SynthesisInstructions.defaultText,
            builtIn: true
        )
    }

    /// All presets: the built-in default first, then user presets (newest by id
    /// sort), with a user preset overriding the built-in if it reuses the id.
    public func load() -> [SynthesisInstructionPreset] {
        var byID: [String: SynthesisInstructionPreset] = [
            Self.builtInDefault.id: Self.builtInDefault
        ]
        var order: [String] = [Self.builtInDefault.id]
        for preset in userPresets() {
            if byID[preset.id] == nil { order.append(preset.id) }
            byID[preset.id] = preset
        }
        return order.compactMap { byID[$0] }
    }

    public func preset(id: String) -> SynthesisInstructionPreset? {
        load().first { $0.id == id }
    }

    /// Persists a user preset (built-in presets are not written to disk).
    @discardableResult
    public func save(_ preset: SynthesisInstructionPreset) throws -> URL {
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

    private func userPresets() -> [SynthesisInstructionPreset] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil
        ) else { return [] }
        return entries
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? CoreJSON.decode(SynthesisInstructionPreset.self, from: Data(contentsOf: $0)) }
    }
}
