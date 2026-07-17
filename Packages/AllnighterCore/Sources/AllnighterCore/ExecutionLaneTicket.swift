import Foundation

/// FIFO lane ticket surfaced when the per-root execution lane is held
/// (`docs/phases/Process_Ownership.md` PO-S03).
///
/// Agents must **not** busy-loop on this — the harness owns the wait and
/// projects `laneBlocked` on relay/pilot status. A raw retry cadence is a
/// queue without fairness.
public struct ExecutionLaneTicket: Codable, Sendable, Equatable, Error {
    /// 1-based position among blocked waiters (head of queue = 1).
    public var position: Int
    public var holder: Holder
    /// Seconds the current holder has held the lane (monotonic wall clock).
    public var heldSinceSeconds: Double

    public struct Holder: Codable, Sendable, Equatable {
        /// Process identity of the holder (`ProcessOwnerRecord` wire form).
        public var identity: ProcessOwnerRecord
        /// Claim kind: `relayDevTurn` | `pilotDevTurn` | `harnessProof` | `mutatingRun` | …
        public var kind: String
        /// Stable id of the holding work (relay id, run id, proof id).
        public var id: String

        public init(identity: ProcessOwnerRecord, kind: String, id: String) {
            self.identity = identity
            self.kind = kind
            self.id = id
        }
    }

    public init(position: Int, holder: Holder, heldSinceSeconds: Double) {
        self.position = position
        self.holder = holder
        self.heldSinceSeconds = heldSinceSeconds
    }
}

/// Where a spawn/dispatch site sits relative to the build-class execution lane.
/// Recorded next to the registry so every future site must choose explicitly
/// (`docs/phases/Process_Ownership.md` PO-S03 build-lane scope).
public enum ExecutionLaneSite: String, Codable, Sendable, CaseIterable {
    /// Relay-spawned dev turn (agent builds inside the turn).
    case relayDevTurn
    /// Pilot-driven dev turn (same build class as relay).
    case pilotDevTurn
    /// Harness-owned proof / build / test of record.
    case harnessProof
    /// Ordinary mutating `RunService` run (repo write + possible in-turn builds).
    case mutatingRun
    /// Panel seat — read-only by mechanism; **never** takes the lane.
    case panelSeat
    /// Answer / judgment team run — read-only; never takes the lane.
    case answerRun
}

/// Build vs non-build classification for `ExecutionLaneSite`.
public enum ExecutionLaneScope: String, Codable, Sendable {
    /// Takes the per-root execution lane for its duration.
    case build
    /// Explicitly non-build; must not acquire the lane.
    case nonBuild
}

/// Single place that records which sites take the build lane.
public enum ExecutionLaneClassification {
    public static func scope(for site: ExecutionLaneSite) -> ExecutionLaneScope {
        switch site {
        case .relayDevTurn, .pilotDevTurn, .harnessProof, .mutatingRun:
            return .build
        case .panelSeat, .answerRun:
            return .nonBuild
        }
    }

    public static func mustAcquire(_ site: ExecutionLaneSite) -> Bool {
        scope(for: site) == .build
    }
}
