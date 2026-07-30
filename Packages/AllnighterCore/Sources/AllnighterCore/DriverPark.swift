import Foundation

/// User intent: a CLI/source is **parked** (ignored) until explicitly put back on the bench.
///
/// Truth lives in `cli_setup.json` (`parkedDriverIds`) alongside probe records — same file
/// `SetupStore` owns in Engine. Core can read without importing Engine so projectors
/// (`BenchReadiness`, `ModelListProjector`, future `alln capacity` / status) share one rule:
///
/// - Parked ⇒ not ready, not seated, not probed on re-check-all, quiet in Needs attention.
/// - Unpark does not delete the CLI; last probe cache is kept until the next check.
public enum DriverPark {
    public static var defaultFileURL: URL {
        AllnighterSupportRoot.config.appendingPathComponent("cli_setup.json")
    }

    /// Sorted unique parked driver ids (stable for JSON + list ordering).
    public static func parkedDriverIds(fileURL: URL = defaultFileURL) -> [String] {
        Array(parkedSet(fileURL: fileURL)).sorted()
    }

    public static func parkedSet(fileURL: URL = defaultFileURL) -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? CoreJSON.decode(ParkSlice.self, from: data) else {
            return []
        }
        return Set(state.parkedDriverIds ?? [])
    }

    public static func isParked(_ driverId: String, fileURL: URL = defaultFileURL) -> Bool {
        parkedSet(fileURL: fileURL).contains(driverId)
    }

    /// Decode-only slice so Core can read park state without the Engine `SetupStore` type.
    struct ParkSlice: Codable, Sendable {
        var parkedDriverIds: [String]?
    }
}
