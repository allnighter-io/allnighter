import Foundation

/// Resolves a dev-seat alias for `pilot start --dev-worker` (Pilot_DX.md §DX4).
/// Case-insensitive substring or suffix match over model id + displayName.
///
/// When several models match (e.g. `opus` → Claude Opus 4.8 and Antigravity Opus
/// 4.6), prefer the highest catalog `strengthRank` so the preferred seat wins
/// without forcing the user to disambiguate when a clear flagship exists.
public enum PilotSeatResolver {
    public enum Error: Swift.Error, Equatable, Sendable {
        case ambiguous(alias: String, candidates: [Model])
        case noMatch(alias: String, readySeats: [Model])
        case noReadySeats
    }

    /// Returns the resolved model id when the alias matches exactly one model, or
    /// when multiple matches share a single clear strength-rank winner.
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
            // Prefer the strongest catalog match (Opus 4.8 over Opus 4.6 fallback).
            // Still ambiguous only when two+ models tie on strengthRank.
            let ranked = matches.sorted { a, b in
                let ra = ModelCatalog.capabilities(a.id).strengthRank
                let rb = ModelCatalog.capabilities(b.id).strengthRank
                return ra != rb ? ra > rb : a.id < b.id
            }
            let top = ranked[0]
            let topRank = ModelCatalog.capabilities(top.id).strengthRank
            let tied = ranked.filter { ModelCatalog.capabilities($0.id).strengthRank == topRank }
            if tied.count == 1 {
                return .success(top.id)
            }
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
