import Foundation

/// Which teams are hidden from the Teams page + composer picker. Default: every team shows.
/// Turning a team OFF records its id here (config, NOT catalog content) under
/// `Config/team_disabled.json`; it stays reachable in Settings (Team Studio) to switch back on.
///
/// Works for built-ins too — the shipped seed is never mutated, just hidden — so ON/OFF is fully
/// reversible. (Deleting, which only customs allow, is the permanent removal — see
/// `TeamCatalog.deleteCustom`.) Resolution by id (`TeamCatalog.get`, default-run team, a thread's
/// chosen team) is unaffected: hiding only removes the card, never breaks a run.
public enum TeamVisibility {
    public struct State: Codable, Sendable, Equatable {
        public var disabledTeamIds: [TeamID]
        public var updatedAt: Date?
        public init(disabledTeamIds: [TeamID] = [], updatedAt: Date? = nil) {
            self.disabledTeamIds = disabledTeamIds
            self.updatedAt = updatedAt
        }
    }

    nonisolated(unsafe) private static var fileOverride: URL?

    private static var fileURL: URL {
        fileOverride ?? ModelCatalogPaths.config.appendingPathComponent("team_disabled.json")
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
        var seen = Set<TeamID>()
        let ordered = ids.filter { seen.insert($0).inserted }
        try CoreJSON.encode(State(disabledTeamIds: ordered, updatedAt: Date())).write(to: fileURL, options: .atomic)
    }

    /// Ids the user has switched OFF.
    public static func disabledIds() -> [TeamID] { loadState().disabledTeamIds }

    /// Default true — a team shows on the Teams page unless explicitly switched off.
    public static func isEnabled(_ id: TeamID) -> Bool { !loadState().disabledTeamIds.contains(id) }

    /// Switch a team on/off for the Teams page + picker. Returns the new enabled state.
    @discardableResult
    public static func setEnabled(_ id: TeamID, _ on: Bool) throws -> Bool {
        var ids = loadState().disabledTeamIds
        if on {
            ids.removeAll { $0 == id }
        } else if !ids.contains(id) {
            ids.append(id)
        }
        try write(ids)
        return on
    }
}
