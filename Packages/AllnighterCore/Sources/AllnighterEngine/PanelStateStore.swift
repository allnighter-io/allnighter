import Foundation
import AllnighterCore

/// Persists `PanelState` to disk as one folder per panel — `panels/<id>/panel.json` —
/// mirroring `RelayStateStore`'s per-id folder + atomic-write pattern
/// (`docs/phases/Pilot_Panel.md` PN-S01).
///
/// `owner.pid` is written ONLY while `status == .running`. `awaitingPM` is parked/
/// unowned — orphan reconcile must skip it (mirror the relay guard exactly).
public struct PanelStateStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AllnighterPaths.panels
    }

    private func panelDirectory(id: String) throws -> URL {
        let directory = rootDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Atomic write (temp + rename) so a concurrent reader never sees a torn file.
    /// Records/clears an `owner.pid` liveness marker — written FIRST for a non-terminal
    /// `.running` state so a reader can never see `panel.json` without it; removed on
    /// any non-running save. `awaitingPM` is parked/unowned and never writes owner.pid.
    @discardableResult
    public func save(_ state: PanelState) throws -> URL {
        let directory = try panelDirectory(id: state.id)
        let ownerURL = directory.appendingPathComponent("owner.pid")
        if state.status == .running {
            try Data("\(PanelStateStore.currentPID)".utf8).write(to: ownerURL, options: .atomic)
        }
        try CoreJSON.encode(state).write(to: directory.appendingPathComponent("panel.json"), options: .atomic)
        if state.status != .running {
            try? FileManager.default.removeItem(at: ownerURL)
        }
        return directory
    }

    public func load(id: String) -> PanelState? {
        let url = rootDirectory.appendingPathComponent(id, isDirectory: true).appendingPathComponent("panel.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? CoreJSON.decode(PanelState.self, from: data)
    }

    /// True when `id`'s `owner.pid` marker is missing/unparsable, or names a process
    /// that is no longer alive. Missing counts as dead — never assume alive without
    /// proof, matching `RunStore` / `RelayStateStore`. Pure read, no side effects.
    public func isOwnerDead(id: String) -> Bool {
        let ownerURL = rootDirectory
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("owner.pid")
        guard let raw = try? String(contentsOf: ownerURL, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return true
        }
        return !RunStore.processAlive(pid)
    }

    private static var currentPID: Int32 { ProcessInfo.processInfo.processIdentifier }

    /// Stable note for the narrow case where durable per-seat truth says every
    /// seat is terminal but the coordinator never wrote the round's terminal
    /// transition. This is not an owner-death inference: a live coordinator PID
    /// cannot make an all-terminal round "alive".
    public static let terminalSeatReconciledNote = "all seats reached a terminal state without round completion (reconciled)"

    /// All panels, newest first. Skips folders whose `panel.json` fails to decode.
    public func list() -> [PanelState] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return entries
            .compactMap { load(id: $0.lastPathComponent) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Reconciles a `.running` panel whose owner process died mid-round into a settled
    /// partial round parked at `awaitingPM`. The `.running`-only guard makes
    /// `awaitingPM` immune (parked for days with no process is by design).
    ///
    /// Settles the open round (if any) with `finishedAt` so the session sees honest
    /// partial seat results, stamps `note` with `PanelState.orphanReconciledNote`, and
    /// persists. No-op for live `.running`, already-parked, or terminal panels.
    @discardableResult
    public func reconcileIfOrphaned(
        _ state: PanelState,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> PanelState {
        guard state.status == .running, isOwnerDead(id: state.id) else { return state }
        var reconciled = state
        if let lastIndex = reconciled.rounds.indices.last,
           reconciled.rounds[lastIndex].finishedAt == nil {
            // Mark any seat that never produced a report as timed-out so the partial
            // round is honest about what arrived vs what was cut short.
            var seats = reconciled.rounds[lastIndex].seatResults
            for i in seats.indices {
                let unfinished =
                    seats[i].status == .running
                    || seats[i].status == .empty
                    || (seats[i].status == .done
                        && seats[i].report.isEmpty
                        && seats[i].findings == nil)
                if unfinished {
                    seats[i].status = .timedOut
                    seats[i].reason = seats[i].reason ?? PanelState.orphanReconciledNote
                }
            }
            reconciled.rounds[lastIndex].seatResults = seats
            reconciled.rounds[lastIndex].finishedAt = now()
        }
        reconciled.status = .awaitingPM
        reconciled.note = PanelState.orphanReconciledNote
        try? save(reconciled)
        // Best-effort: drop any leaked seat clones from a mid-round death (PN-S06).
        PanelSeatIsolation.sweepPanelClones(panelId: state.id, panelsRoot: rootDirectory)
        return reconciled
    }

    /// Settles an open round once its durable seat rows are all terminal, even
    /// if the coordinator process is still alive. This closes the failure mode
    /// where a worker collector records empty/failed rows then stalls before
    /// parking the panel, leaving `panel status` to claim `roundAlive` forever.
    ///
    /// An empty report is not a valid review result. It is promoted to a
    /// per-seat failure with a retryable, actionable reason. Valid `.done`
    /// reports and already classified failures remain untouched.
    @discardableResult
    public func settleIfAllSeatsTerminal(
        _ state: PanelState,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> PanelState {
        guard state.status == .running,
              let lastIndex = state.rounds.indices.last,
              state.rounds[lastIndex].finishedAt == nil,
              !state.rounds[lastIndex].seatResults.isEmpty,
              !state.rounds[lastIndex].seatResults.contains(where: { $0.status == .running }) else {
            return state
        }

        var reconciled = state
        for index in reconciled.rounds[lastIndex].seatResults.indices {
            guard reconciled.rounds[lastIndex].seatResults[index].status == .empty else { continue }
            reconciled.rounds[lastIndex].seatResults[index].status = .failed
            let existing = reconciled.rounds[lastIndex].seatResults[index].reason
            if existing == nil || existing == "empty seat report" {
                reconciled.rounds[lastIndex].seatResults[index].reason =
                    "worker exited without a report; check source readiness and rerun this seat"
            }
        }
        reconciled.rounds[lastIndex].finishedAt = now()
        reconciled.status = .awaitingPM
        reconciled.note = Self.terminalSeatReconciledNote
        try? save(reconciled)
        PanelSeatIsolation.sweepPanelClones(panelId: state.id, panelsRoot: rootDirectory)
        return reconciled
    }
}
