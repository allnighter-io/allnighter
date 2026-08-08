import Foundation

/// Single place to add or remove Boost CLIs.
///
/// A seat is **seedable** here (we know the driver id + where capacity speaks).
/// It becomes **eligible** only when capacity has recorded a short rolling
/// window (`.fiveHour` or Claude's `.session`) for one of its capacity sources.
/// Dashboard-only meters (e.g. `opencode_go`) map to the seedable CLI driver.
public enum BoostSeatCatalog {
    public struct Seat: Sendable, Equatable, Hashable {
        /// Driver id passed to `UtilizationSeedExecutor` / `appliesTo`.
        public let seedDriverId: String
        /// Capacity source ids that can prove a short rolling window for this seat.
        public let capacitySourceIds: [String]

        public init(seedDriverId: String, capacitySourceIds: [String]) {
            self.seedDriverId = seedDriverId
            self.capacitySourceIds = capacitySourceIds
        }
    }

    /// Product chip order. Add a seat with one entry — nothing else hardcodes ids.
    public static let seats: [Seat] = [
        Seat(seedDriverId: "claude_code", capacitySourceIds: ["claude_code"]),
        Seat(seedDriverId: "codex", capacitySourceIds: ["codex"]),
        Seat(seedDriverId: "kimi", capacitySourceIds: ["kimi"]),
        Seat(seedDriverId: "opencode", capacitySourceIds: ["opencode_go", "opencode"]),
        Seat(seedDriverId: "antigravity", capacitySourceIds: ["agy", "antigravity"]),
    ]

    public static var seedDriverIds: [String] { seats.map(\.seedDriverId) }

    public static var capacitySourceIds: [String] {
        Array(Set(seats.flatMap(\.capacitySourceIds))).sorted()
    }

    public static func seat(seedDriverId: String) -> Seat? {
        seats.first { $0.seedDriverId == seedDriverId }
    }

    public static func seedDriverId(forCapacitySource capacitySourceId: String) -> String? {
        seats.first { $0.capacitySourceIds.contains(capacitySourceId) }?.seedDriverId
    }

    public static func knowsSeedDriver(_ id: String) -> Bool {
        seat(seedDriverId: id) != nil
    }
}

/// Pure eligibility: capacity evidence → seed driver ids.
public enum BoostSeatEligibility {
    /// Scopes that prove a Boost-placeable rolling bucket.
    /// Claude records `.session` for the ~5h "Current session" bar; others use `.fiveHour`.
    public static func isBoostWindowScope(_ scope: CapacityWindowScope) -> Bool {
        switch scope {
        case .fiveHour, .session: return true
        case .weekly, .monthly, .planClass: return false
        }
    }

    /// From capacity source → scopes seen (known samples only).
    public static func eligibleSeedDriverIds(
        evidencedScopesByCapacitySource: [String: Set<CapacityWindowScope>]
    ) -> Set<String> {
        var out = Set<String>()
        for (capacityId, scopes) in evidencedScopesByCapacitySource {
            guard scopes.contains(where: isBoostWindowScope) else { continue }
            if let seed = BoostSeatCatalog.seedDriverId(forCapacitySource: capacityId) {
                out.insert(seed)
            }
        }
        return out
    }

    /// Convenience over live/history `CapacityWindow` samples (skips unknown).
    public static func eligibleSeedDriverIds(windows: [CapacityWindow]) -> Set<String> {
        var map: [String: Set<CapacityWindowScope>] = [:]
        for window in windows {
            guard window.unknownReason == nil else { continue }
            map[window.source, default: []].insert(window.scope)
        }
        return eligibleSeedDriverIds(evidencedScopesByCapacitySource: map)
    }
}
