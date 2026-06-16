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

    /// The built-in judge profiles: structured analysis, then the plan writer.
    public static var builtInAnalysis: SynthesisInstructionPreset {
        SynthesisInstructionPreset(
            id: SynthesisInstructions.analysisID,
            displayName: "Plan — Analysis",
            template: SynthesisInstructions.analysisText,
            builtIn: true
        )
    }

    public static var builtInPlan: SynthesisInstructionPreset {
        SynthesisInstructionPreset(
            id: SynthesisInstructions.planID,
            displayName: "Plan — Writer",
            template: SynthesisInstructions.planText,
            builtIn: true
        )
    }

    /// The canonical built-in default (the plan profile), for callers that want one.
    public static var builtInDefault: SynthesisInstructionPreset { builtInPlan }

    public static var builtInProfiles: [SynthesisInstructionPreset] { [builtInAnalysis, builtInPlan] }

    /// All profiles: the built-ins first, then user presets, with a user preset
    /// overriding a built-in if it reuses the id.
    public func load() -> [SynthesisInstructionPreset] {
        var byID: [String: SynthesisInstructionPreset] = [:]
        var order: [String] = []
        for profile in Self.builtInProfiles {
            byID[profile.id] = profile
            order.append(profile.id)
        }
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
