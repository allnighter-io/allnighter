import Foundation

/// Stream-primary liveness contract (CLP-S01 / PLS-S01). PRIMARY progress is
/// `TeamRun.lastActivityAt` on the in-flight dev journal — never relay heartbeat
/// or pgid CPU sampling.
///
/// CD-S01a also owns the **dev-leg projection** (running / settling / parked) from
/// the same journal — one arbiter, no parallel liveness path.
public enum StreamLiveness {
    public static let waitHintSeconds: Double = 45
    public static let warningMultiplier: Double = 6

    /// PRIMARY stream timestamp for a relay's in-flight dev turn.
    public static func relayStreamLastActivityAt(
        state: LoopState,
        runStore: some RunStoreReading
    ) -> Date? {
        guard let runId = state.rounds.last?.devRunId else { return nil }
        return runStore.load(runId: runId)?.lastActivityAt
    }

    public static func silenceAgeSeconds(lastActivityAt: Date?, now: Date) -> Int? {
        lastActivityAt.map { max(0, Int(now.timeIntervalSince($0))) }
    }

    public static func streamSilenceWarning(lastActivityAt: Date?, now: Date) -> Bool {
        let threshold = Int(waitHintSeconds * warningMultiplier)
        guard let age = silenceAgeSeconds(lastActivityAt: lastActivityAt, now: now) else { return false }
        return age > threshold
    }

    /// Shared dev-leg facts for `pilot status` and `relay-status` (CD-S01a).
    /// Reconcile-on-read against the linked `devRunId` journal — not a second clock.
    public static func devLegProjection(
        state: LoopState,
        runStore: some RunStoreReading
    ) -> RelayDevLegProjection {
        RelayDevLegProjection.project(state: state, runStore: runStore)
    }
}

/// Linked-dev facts on pilot/relay status. Distinguishes three states so agents
/// never treat aggregate relay `running` as proof the dev worker is still live.
public struct RelayDevLegProjection: Codable, Equatable, Sendable {
    /// Operational phase of the **linked dev leg**, not a re-encoding of `LoopState.status`.
    public enum Phase: String, Codable, Sendable, CaseIterable {
        /// No `devRunId` on the last round.
        case none
        /// Worker journal is non-terminal (or not yet observed).
        case running
        /// Worker journal is terminal while the relay is still `.running` (proof / settle).
        case settling
        /// Relay is parked/terminal and the linked dev facts are terminal when present.
        case parked
    }

    public var phase: Phase
    public var devRunId: String?
    /// `TeamRun.status` raw value when the journal loads; absent if missing.
    public var devRunStatus: String?
    /// Prefer journal `endReason`; fall back to round `devTurnEndReason`.
    public var devEndReason: String?
    /// `headAfterDev` when the coordinator pinned it.
    public var commit: String?

    public init(
        phase: Phase,
        devRunId: String? = nil,
        devRunStatus: String? = nil,
        devEndReason: String? = nil,
        commit: String? = nil
    ) {
        self.phase = phase
        self.devRunId = devRunId
        self.devRunStatus = devRunStatus
        self.devEndReason = devEndReason
        self.commit = commit
    }

    public static func project(
        state: LoopState,
        runStore: some RunStoreReading
    ) -> RelayDevLegProjection {
        guard let round = state.rounds.last, let devRunId = round.devRunId else {
            if isRelayParked(state.status) {
                return RelayDevLegProjection(phase: .parked)
            }
            return RelayDevLegProjection(phase: .none)
        }

        let run = runStore.load(runId: devRunId)
        let journalStatus = run?.status
        let journalEnd = run?.endReason?.rawValue
        let roundEnd = round.devTurnEndReason?.rawValue
        let commit = round.headAfterDev
        let parked = isRelayParked(state.status)

        let workerTerminal: Bool = {
            if let journalStatus { return journalStatus.isTerminal }
            // Journal missing but round already stamped a turn end — treat as terminal facts.
            return round.devTurnEndReason != nil
        }()

        let statusRaw = journalStatus?.rawValue
        let endRaw = journalEnd ?? roundEnd

        if parked {
            return RelayDevLegProjection(
                phase: .parked,
                devRunId: devRunId,
                devRunStatus: statusRaw,
                devEndReason: endRaw,
                commit: commit
            )
        }

        // Relay still `.running`.
        if workerTerminal {
            return RelayDevLegProjection(
                phase: .settling,
                devRunId: devRunId,
                devRunStatus: statusRaw,
                devEndReason: endRaw,
                commit: commit
            )
        }

        return RelayDevLegProjection(
            phase: .running,
            devRunId: devRunId,
            devRunStatus: statusRaw,
            devEndReason: endRaw,
            commit: commit
        )
    }

    private static func isRelayParked(_ status: LoopState.Status) -> Bool {
        switch status {
        case .awaitingPM, .escalated, .done, .stopped:
            return true
        case .running:
            return false
        }
    }
}

/// Minimal run-store read surface for stream liveness (tests inject fakes).
public protocol RunStoreReading: Sendable {
    func load(runId: String) -> TeamRun?
}
