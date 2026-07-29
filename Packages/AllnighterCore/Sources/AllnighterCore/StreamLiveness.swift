import Foundation

/// Stream-primary liveness contract (CLP-S01 / PLS-S01). PRIMARY progress is
/// `TeamRun.lastActivityAt` on the in-flight dev journal — never relay heartbeat
/// or pgid CPU sampling.
public enum StreamLiveness {
    public static let waitHintSeconds: Double = 45
    public static let warningMultiplier: Double = 6

    /// PRIMARY stream timestamp for a relay's in-flight dev turn.
    public static func relayStreamLastActivityAt(
        state: RelayState,
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
}

/// Minimal run-store read surface for stream liveness (tests inject fakes).
public protocol RunStoreReading: Sendable {
    func load(runId: String) -> TeamRun?
}
