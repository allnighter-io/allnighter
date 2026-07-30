import AllnighterCore

/// Read-side PM Turn truth for a status/result envelope.
///
/// A terminal or parked subject without its receipt is the expected crash window
/// between the subject write and `pm-turn.json`; callers must surface that fact
/// instead of deriving a report from other artifacts.
public struct PMTurnStatusProjection: Sendable, Equatable {
    public var pmTurn: PMTurnJSON?
    public var notes: [String]
    public var pmTurnDelivery: PMTurnDeliveryJSON?

    public init(
        pmTurn: PMTurnJSON?, notes: [String] = [], pmTurnDelivery: PMTurnDeliveryJSON? = nil
    ) {
        self.pmTurn = pmTurn
        self.notes = notes
        self.pmTurnDelivery = pmTurnDelivery
    }

    /// Relay boundaries are exactly its park and terminal states, never merely
    /// "anything not running" — new lifecycle states must opt in deliberately.
    public static func isRelayPMBoundary(_ status: RelayState.Status) -> Bool {
        switch status {
        case .awaitingPM, .escalated, .stopped, .done:
            true
        case .running:
            false
        }
    }

    public static func load(
        kind: PMTurnJSON.Kind,
        subjectId: String,
        atPMBoundary: Bool,
        store: PMTurnStore,
        wakeLedgerStore: PMTurnWakeReceiptLedgerStore = PMTurnWakeReceiptLedgerStore()
    ) -> PMTurnStatusProjection {
        guard atPMBoundary else { return .init(pmTurn: nil) }
        do {
            guard let pmTurn = try store.load(kind: kind, subjectId: subjectId) else {
                return .init(pmTurn: nil, notes: ["pm_turn_missing"])
            }
            return .init(pmTurn: pmTurn, pmTurnDelivery: wakeLedgerStore.delivery(for: pmTurn))
        } catch {
            // Never synthesize a report when the durable receipt is unreadable.
            return .init(pmTurn: nil, notes: ["pm_turn_unavailable"])
        }
    }
}
