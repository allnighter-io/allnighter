import Foundation

/// LR-S05c — hosting-body pointer (ruling 5 / packet §2.4).
///
/// A pointer is a cross-reference, not a seat. Consume `drivers --json`
/// `localRuntimeSeats` — do not recompute from `/api/tags`.
public enum LocalRuntimePointerPresenter {
    public struct Row: Equatable, Sendable {
        public var driverId: String
        public var label: String
        public var seatCount: Int
        /// Pointers are never a roster pick.
        public var selectable: Bool { false }
        /// Never counted with the body's paid roster chips.
        public var countsTowardRoster: Bool { false }
        /// Never a `models[]` entry.
        public var isModelsEntry: Bool { false }

        public init(driverId: String, label: String, seatCount: Int) {
            self.driverId = driverId
            self.label = label
            self.seatCount = seatCount
        }
    }

    /// Nil when the body hosts zero enabled seated local rows — no zero, no
    /// disabled row.
    public static func row(driverId: String, localRuntimeSeats: Int?) -> Row? {
        guard let count = localRuntimeSeats, count > 0 else { return nil }
        return Row(
            driverId: driverId,
            label: ChromeCopy.localRuntimePointerLabel(count: count),
            seatCount: count
        )
    }

    public static func rows(from drivers: DriverListJSON) -> [Row] {
        drivers.drivers.compactMap { entry in
            row(driverId: entry.driverId, localRuntimeSeats: entry.localRuntimeSeats)
        }
    }

    public static func isLocalRuntimeSeat(driverId: String, modelLabel: String) -> Bool {
        OpenCodeLocalSeatReadiness.isLocalOpenCodeSeat(
            driverId: driverId, modelLabel: modelLabel)
            || ClaudeLocalIsolation.isLocalSeat(
                driverId: driverId, modelLabel: modelLabel)
    }

    public static func isLocalRuntimeSeat(_ model: Model) -> Bool {
        isLocalRuntimeSeat(driverId: model.driverId, modelLabel: model.modelLabel)
    }

    public static func isLocalRuntimeSeat(_ def: ModelDefinition) -> Bool {
        isLocalRuntimeSeat(driverId: def.driverId, modelLabel: def.modelLabel)
    }

    /// Enabled paid (non-local) roster names for a body card.
    public static func rosterDisplayNames(models: [Model], driverId: String) -> [String] {
        models
            .filter { $0.enabled && $0.driverId == driverId && !isLocalRuntimeSeat($0) }
            .map(\.displayName)
    }
}
