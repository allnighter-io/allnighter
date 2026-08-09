import Foundation

/// User switch for model-assisted pane reading.
///
/// Founder: *"users can turn it off."* On by default, because the measured
/// alternative is a seat silently disappearing when a vendor changes its screen
/// — but it spends a small amount of the user's own quota, so it must be theirs
/// to decline, and declining must degrade to the deterministic parser rather
/// than to nothing.
public struct CapacityPaneSettings: Sendable {
    private struct File: Codable { var enabled: Bool }

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AllnighterSupportRoot.config
            .appendingPathComponent("capacity_pane_reader.json")
    }

    /// Defaults to ON. A user who has never expressed a preference is better
    /// served by a bench that keeps working through a vendor UI change.
    public func loadEnabled() -> Bool {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return true }
        return file.enabled
    }

    public func saveEnabled(_ enabled: Bool) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(File(enabled: enabled)).write(to: fileURL, options: .atomic)
    }
}
