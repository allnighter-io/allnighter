import Foundation

/// Resolves `--dev-worker` / panel `--seat` to a canonical model id (MR-S04).
/// Exact ids only — display names and fuzzy aliases never authorize dispatch.
/// Unknown values fail with same-kind candidates via `ExactIdResolver`.
public enum PilotSeatResolver {
    public enum Error: Swift.Error, Equatable, Sendable {
        case ambiguous(alias: String, candidates: [Model])
        case noMatch(alias: String, readySeats: [Model])
        case noReadySeats
        /// Structured exact-id failure (preferred path).
        case exactId(ExactIdResolver.Failure)
    }

    /// Honor an exact model id, or fail closed. Never matches display names.
    public static func resolve(alias raw: String, models: [Model]) -> Result<String, Error> {
        switch ExactIdResolver.resolveWorker(raw, flag: "--dev-worker", models: models) {
        case .success(let model):
            return .success(model.id)
        case .failure(let failure):
            return .failure(.exactId(failure))
        }
    }

    /// Models whose driver has a global `ready` probe — the seats `pilot start` can use.
    public static func readySeats(from models: [Model], probeRecords: [ToolProbeRecord]) -> [Model] {
        // SR-14 (Sol F28): `Dictionary(uniqueKeysWithValues:)` traps at runtime on a
        // duplicate driver id. No current path produces duplicates, but a hand-edited or
        // migrated `cli_setup.json` with two records for one driver would crash `pilot start`
        // (and every other readySeats caller) instead of degrading — keep the latest record.
        let recordsByDriver = Dictionary(
            probeRecords.map { ($0.driverId, $0) },
            uniquingKeysWith: { _, latest in latest })
        return models.filter { m in
            m.enabled && (recordsByDriver[m.driverId]?.status.isSmokeReady ?? false)
        }.sorted { $0.id < $1.id }
    }

    public static func formatCandidates(_ models: [Model]) -> String {
        models.map(\.id).joined(separator: ", ")
    }

    public static func formatReadySeats(_ models: [Model]) -> String {
        let ready = models.map { "\($0.id) (\($0.displayName))" }
        return ready.isEmpty ? "(none — run `alln doctor --full`)" : ready.joined(separator: ", ")
    }
}
