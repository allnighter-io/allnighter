import Foundation

/// Persists Bench membership in `Config/model_roster.json` (config, not catalog content).
public struct ModelRosterPersistence {
  private let fileURL: URL

  public init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? ModelCatalogPaths.config.appendingPathComponent("model_roster.json")
  }

  public func load() -> ModelRosterState? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? CoreJSON.decode(ModelRosterState.self, from: data)
  }

  public func save(_ state: ModelRosterState) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    var state = state
    state.updatedAt = Date()
    try CoreJSON.encode(state).write(to: fileURL, options: .atomic)
  }
}
