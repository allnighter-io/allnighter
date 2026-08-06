import Foundation

/// CWB-S01b: capacity feature ON/OFF — the only v1 setting (no interval picker,
/// founder lock). One tiny JSON file at `Config/capacity_feature.json`.
///
/// Missing file → **ON** (shipped default: Dock open + ON → silent 30m
/// one-shots). A present-but-unreadable file is NOT silently discarded — it is
/// backed up to `<file>.corrupt` and the default applies, same rule as
/// `DefaultModelSettingsPersistence`.
public struct CapacityFeatureSettingsPersistence: Sendable {

    private struct File: Codable {
        var enabled: Bool
    }

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AllnighterSupportRoot.config
            .appendingPathComponent("capacity_feature.json")
    }

    public func loadEnabled() -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return true }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            try? data.write(to: fileURL.appendingPathExtension("corrupt"), options: .atomic)
            return true
        }
        return file.enabled
    }

    public func saveEnabled(_ enabled: Bool) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(File(enabled: enabled)).write(to: fileURL, options: .atomic)
    }
}
