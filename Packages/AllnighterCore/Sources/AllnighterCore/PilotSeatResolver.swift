import Foundation

/// Resolves a dev-seat alias for `pilot start --dev-worker` (Pilot_DX.md §DX4).
/// Case-insensitive substring or suffix match over model id + displayName.
public enum PilotSeatResolver {
    public enum Error: Swift.Error, Equatable, Sendable {
        case ambiguous(alias: String, candidates: [Model])
        case noMatch(alias: String, readySeats: [Model])
        case noReadySeats
    }

    /// Returns the resolved model id when the alias matches exactly one model in the catalog.
    public static func resolve(alias raw: String, models: [Model]) -> Result<String, Error> {
        let alias = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !alias.isEmpty else {
            return .failure(.noMatch(alias: raw, readySeats: readySeats(from: models.filter(\.enabled))))
        }
        let matches = models.filter { matchesAlias(alias, model: $0) }
        switch matches.count {
        case 0:
            return .failure(.noMatch(alias: raw, readySeats: readySeats(from: models.filter(\.enabled))))
        case 1:
            return .success(matches[0].id)
        default:
            return .failure(.ambiguous(alias: raw, candidates: matches.sorted { $0.id < $1.id }))
        }
    }

    /// Models whose driver has a global `ready` probe — the seats `pilot start` can use.
    public static func readySeats(from models: [Model], probeRecords: [ToolProbeRecord]) -> [Model] {
        let recordsByDriver = Dictionary(uniqueKeysWithValues: probeRecords.map { ($0.driverId, $0) })
        return models.filter { m in
            m.enabled && (recordsByDriver[m.driverId]?.status.isReady ?? false)
        }.sorted { $0.id < $1.id }
    }

    private static func readySeats(from models: [Model]) -> [Model] {
        models.sorted { $0.id < $1.id }
    }

    private static func matchesAlias(_ alias: String, model: Model) -> Bool {
        let id = model.id.lowercased()
        let name = model.displayName.lowercased()
        if id == alias || name == alias { return true }
        if id.contains(alias) || name.contains(alias) { return true }
        if id.hasSuffix(alias) || name.hasSuffix(alias) { return true }
        return false
    }

    public static func formatCandidates(_ models: [Model]) -> String {
        models.map(\.id).joined(separator: ", ")
    }

    public static func formatReadySeats(_ models: [Model]) -> String {
        let ready = models.map { "\($0.id) (\($0.displayName))" }
        return ready.isEmpty ? "(none — run `alln doctor --full`)" : ready.joined(separator: ", ")
    }
}
