import Foundation

/// LR-S05c — one persisted default body for the next local enable.
///
/// Applies to the next mint only. Does not remint in-flight or already-seated
/// ids (`seatedID` encodes the body). No "switch every enabled seat" verb.
public struct LocalRuntimeDefaultBody: Sendable {
    public static var defaultFileURL: URL {
        AllnighterSupportRoot.config.appendingPathComponent("local_runtime.json")
    }

    private struct File: Codable {
        var defaultBody: String
    }

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    public static func resolved(fileURL: URL? = nil) -> String {
        Self(fileURL: fileURL).resolved()
    }

    public static func save(_ driverId: String, fileURL: URL? = nil) throws {
        try Self(fileURL: fileURL).save(driverId)
    }

    public func resolved() -> String {
        load() ?? OllamaLocalModelDiscoveryProvider.defaultEnableBodyDriverId
    }

    public func load() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data),
              OllamaLocalSeatEnablePolicy.allowedBodies.contains(file.defaultBody)
        else { return nil }
        return file.defaultBody
    }

    public func save(_ driverId: String) throws {
        guard OllamaLocalSeatEnablePolicy.allowedBodies.contains(driverId) else {
            throw ModelCatalogError.invalid(
                "unknown agent body '\(driverId)' — choose claude_code or opencode")
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(File(defaultBody: driverId))
        try data.write(to: fileURL, options: .atomic)
    }
}
