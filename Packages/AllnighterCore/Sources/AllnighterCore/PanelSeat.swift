import Foundation

/// One independent slot in the panel. A worker can fill several seats — that is
/// *self-fusion* (the same model run multiple times explores different reasoning
/// paths). A normal six-model panel is six seats, each `seatIndex == 0`.
public struct PanelSeat: Codable, Sendable, Equatable, Identifiable {
    /// Stable seat id, e.g. `worker_opus#0`, `worker_opus#1`.
    public var id: String
    /// Which configured worker runs this seat.
    public var workerId: String
    /// 0-based index among seats sharing a `workerId`.
    public var seatIndex: Int
    /// Optional perspective framing (RB1 stance id). Drives a prompt prefix.
    public var stance: String?
    /// Display override, e.g. `Opus (A)`.
    public var label: String?

    public init(
        id: String,
        workerId: String,
        seatIndex: Int,
        stance: String? = nil,
        label: String? = nil
    ) {
        self.id = id
        self.workerId = workerId
        self.seatIndex = seatIndex
        self.stance = stance
        self.label = label
    }

    /// Canonical seat id for a worker + index.
    public static func makeID(workerId: String, seatIndex: Int) -> String {
        "\(workerId)#\(seatIndex)"
    }

    /// Display name: the explicit label, else worker + an A/B/C suffix when
    /// multiple seats share a worker.
    public func displayName(workerName: String, sharesWorker: Bool) -> String {
        if let label { return label }
        guard sharesWorker else { return workerName }
        let suffix = String(UnicodeScalar(65 + (seatIndex % 26))!) // A, B, C…
        return "\(workerName) (\(suffix))"
    }
}

/// A preset's request for seats. Expanded into concrete `PanelSeat`s at run
/// start. `count > 1` is self-fusion (one worker, several seats); `stance`
/// (RB1) frames each seat differently.
public struct PanelSeatSpec: Codable, Sendable, Equatable {
    public var workerId: String
    public var count: Int
    public var stance: String?

    public init(workerId: String, count: Int = 1, stance: String? = nil) {
        self.workerId = workerId
        self.count = count
        self.stance = stance
    }

    /// Expands this spec into concrete seats, numbering `seatIndex` from `start`
    /// among seats that share this `workerId`.
    public func expand(startingIndex start: Int) -> [PanelSeat] {
        (0..<max(1, count)).map { offset in
            let index = start + offset
            return PanelSeat(
                id: PanelSeat.makeID(workerId: workerId, seatIndex: index),
                workerId: workerId,
                seatIndex: index,
                stance: stance
            )
        }
    }
}

public extension Array where Element == PanelSeatSpec {
    /// Expands a list of seat specs into concrete seats, assigning per-worker
    /// `seatIndex` so repeated workers get `#0`, `#1`, … in order.
    func expandedSeats() -> [PanelSeat] {
        var nextIndex: [String: Int] = [:]
        var seats: [PanelSeat] = []
        for spec in self {
            let start = nextIndex[spec.workerId, default: 0]
            let expanded = spec.expand(startingIndex: start)
            seats.append(contentsOf: expanded)
            nextIndex[spec.workerId] = start + expanded.count
        }
        return seats
    }
}
