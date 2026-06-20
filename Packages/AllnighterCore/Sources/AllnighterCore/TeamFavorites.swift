import Foundation

/// User-chosen favorite teams. Replaces the old single "default per lane" flag with
/// a flat, multi-select set: any team (built-in or custom) can be favorited, and
/// favorites are featured first on the Teams card view and in the composer's team
/// picker. Persisted as config (not catalog content) under
/// `Config/team_favorites.json`. Built-ins are never mutated — favoriting a built-in
/// just records its id here.
public enum TeamFavorites {
    public struct State: Codable, Sendable, Equatable {
        public var teamIds: [TeamID]
        public var updatedAt: Date?
        public init(teamIds: [TeamID] = [], updatedAt: Date? = nil) {
            self.teamIds = teamIds
            self.updatedAt = updatedAt
        }
    }

    nonisolated(unsafe) private static var fileOverride: URL?

    private static var fileURL: URL {
        fileOverride ?? ModelCatalogPaths.config.appendingPathComponent("team_favorites.json")
    }

    /// Test seam: point the store at a scratch file.
    public static func overrideForTesting(file: URL?) { fileOverride = file }

    private static func loadState() -> State {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? CoreJSON.decode(State.self, from: data) else { return State() }
        return state
    }

    private static func write(_ ids: [TeamID]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // De-dupe while preserving order (favorite order is the display order).
        var seen = Set<TeamID>()
        let ordered = ids.filter { seen.insert($0).inserted }
        let state = State(teamIds: ordered, updatedAt: Date())
        try CoreJSON.encode(state).write(to: fileURL, options: .atomic)
    }

    /// Favorite team ids in user-chosen order.
    public static func ids() -> [TeamID] { loadState().teamIds }

    public static func isFavorite(_ id: TeamID) -> Bool { loadState().teamIds.contains(id) }

    /// Add (append) or remove a favorite. Returns the new favorite state for the id.
    @discardableResult
    public static func set(_ id: TeamID, _ on: Bool) throws -> Bool {
        var ids = loadState().teamIds
        if on {
            if !ids.contains(id) { ids.append(id) }
        } else {
            ids.removeAll { $0 == id }
        }
        try write(ids)
        return on
    }

    @discardableResult
    public static func toggle(_ id: TeamID) throws -> Bool {
        try set(id, !isFavorite(id))
    }
}
