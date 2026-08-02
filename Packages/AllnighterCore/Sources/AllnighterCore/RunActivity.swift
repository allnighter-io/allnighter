import Foundation

/// The kind of the last durable activity a run recorded (RLR-L6). This is the
/// **activity** axis, distinct from lifecycle/phase: it advances only on
/// post-spawn work and never on spawn, heartbeats, or per-tick timers.
///
/// `tool` is vendor-reported tool activity (warm ACP `tool_call` **or** cold
/// streaming-json `tool_call` title via the stream parser). The cold path also
/// produces `message` (reasoning/answer), `stdout`/`stderr` (bounded metadata),
/// `child` (stage/worker transition), and `exit` (worker/run terminal). Never
/// fabricate `tool` from byte counts, timing, or output heuristics.
public enum RunActivityKind: String, Codable, Sendable, CaseIterable {
    case tool, message, stdout, stderr, child, exit
}

/// Pure projection + read-time derivations for durable run activity (RLR-L6).
///
/// The one classifier `activityKind(for:)` decides which `RunEvent`s advance
/// `lastActivityAt`; spawn / queued / `spawningWorker` transitions map to `nil`
/// (the RLR-L6 negative proof — spawn advances `startedAt`/ownership, never
/// activity). Staleness / heartbeat age are derived at read time from
/// `lastActivityAt` (the `heldSinceSeconds` pattern), never stored booleans and
/// never per-tick journal writes.
public enum RunActivity {
    /// Upper bound on durable activity writes: at most one `run.json` activity
    /// flush per run per this interval (always flushed on kind-change + terminal).
    /// Mirrors PERF-S01's coalesced stream cadence and `ProgressTracker`'s 0.5s
    /// disk throttle — a chatty token stream never thrashes the journal.
    public static let coalesceIntervalSeconds: TimeInterval = 1.0

    /// Default rolling idle budget for the `progressStale` derivation when no
    /// per-run `--idle-timeout` override is threaded through (matches the prior
    /// `ProcessOwnership.progressStaleAfterSeconds` status-surface default). The
    /// tolerated ~1s coalescing staleness is three orders of magnitude under
    /// this, so `progressStale` never false-trips.
    public static let defaultIdleBudgetSeconds: TimeInterval = 60

    /// THE one activity classifier (RLR-L6). Returns the kind of activity an
    /// event represents, or `nil` when the event must NOT advance `lastActivityAt`.
    ///
    /// Negative proof (RLR-L6 inference ban "Heartbeat → progress" + spawn rule):
    /// - run-level `runStatusChanged` to any non-terminal state (queued /
    ///   spawningWorker / running / working / …) → `nil` (spawn/admission, not activity);
    /// - worker `workerStatusChanged` to `running` (worker spawn) → `nil`;
    /// - only terminal transitions map to `.exit`, structured message deltas to
    ///   `.message`, output to `.stdout`, and stage transitions to `.child`.
    public static func activityKind(for event: RunEvent) -> RunActivityKind? {
        switch event.kind {
        case RunEventKind.workerTool:
            return .tool
        case RunEventKind.workerAnswerDelta, RunEventKind.workerReasoningDelta:
            return .message
        case RunEventKind.workerOutput, RunEventKind.stageOutput:
            return .stdout
        case RunEventKind.stageStarted, RunEventKind.stageCompleted, RunEventKind.stageReused:
            return .child
        case RunEventKind.stageFailed:
            return .exit
        case RunEventKind.workerStatusChanged:
            guard let to = event.payload["to"]?.stringValue,
                  let status = WorkerAnswerStatus(rawValue: to) else { return nil }
            switch status {
            case .running, .queued, .skipped:
                // Agent spawn / admission — advances startedAt/ownership, never activity.
                return nil
            case .done, .failed, .timedOut, .cancelled:
                return .exit
            }
        case RunEventKind.runStatusChanged:
            guard let to = event.payload["to"]?.stringValue,
                  let status = RunStatus(rawValue: to) else { return nil }
            // Only the run-terminal transition is activity (.exit). Every
            // non-terminal run transition (spawn/queued/running/stage names) is nil.
            return status.isTerminal ? .exit : nil
        default:
            return nil
        }
    }

    /// Read-time `progressStale` derivation (RLR-L6). `nil` (absent) before the
    /// first post-spawn activity — the spec forbids reporting stale for a run
    /// that has not yet had a chance to be active.
    public static func progressStale(
        lastActivityAt: Date?,
        now: Date,
        idleBudget: TimeInterval = defaultIdleBudgetSeconds
    ) -> Bool? {
        guard let last = lastActivityAt else { return nil }
        return now.timeIntervalSince(last) > idleBudget
    }

    /// Read-time `ownerHeartbeatAge` / seconds-since-activity derivation. `nil`
    /// before first activity (no synthetic clock — RLR-L6).
    public static func heartbeatAgeSeconds(lastActivityAt: Date?, now: Date) -> Double? {
        guard let last = lastActivityAt else { return nil }
        return max(0, now.timeIntervalSince(last))
    }
}

/// In-memory activity clock with coalesced journal-flush decisions (RLR-L6 /
/// S03a). Pure bookkeeping — no I/O. Callers update the in-memory truth on every
/// L6 event (which feeds the persist stamp + live detectors immediately) and
/// perform a durable `run.json` write only when `note` returns `true`.
///
/// Flush policy: always on the first activity, on any **kind-change**, and on a
/// terminal `.exit`; otherwise at most once per `coalesceInterval`. This bounds
/// activity-driven `run.json` writes to **≤ 1 / second / run** while the
/// in-memory clock still reflects the latest event for the persist stamp.
public final class RunActivityRecorder: @unchecked Sendable {
    private struct State {
        var kind: RunActivityKind
        var at: Date
        var lastFlushAt: Date
    }

    private let lock = NSLock()
    private var states: [String: State] = [:]
    private let coalesceInterval: TimeInterval

    public init(coalesceInterval: TimeInterval = RunActivity.coalesceIntervalSeconds) {
        self.coalesceInterval = coalesceInterval
    }

    /// Record an L6 event's activity. Updates the in-memory clock and returns
    /// whether the durable journal should be flushed now.
    @discardableResult
    public func note(runId: String, kind: RunActivityKind, at: Date) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let previous = states[runId]
        let kindChanged = previous?.kind != kind
        let terminal = (kind == .exit)
        let sinceFlush = previous.map { at.timeIntervalSince($0.lastFlushAt) } ?? .greatestFiniteMagnitude
        let shouldFlush = kindChanged || terminal || sinceFlush >= coalesceInterval
        states[runId] = State(
            kind: kind,
            at: at,
            lastFlushAt: shouldFlush ? at : (previous?.lastFlushAt ?? at)
        )
        return shouldFlush
    }

    /// The latest in-memory activity for a run (feeds the persist stamp). `nil`
    /// before any post-spawn activity — so spawn-only saves stamp nothing.
    public func current(runId: String) -> (at: Date, kind: RunActivityKind)? {
        lock.lock(); defer { lock.unlock() }
        guard let state = states[runId] else { return nil }
        return (state.at, state.kind)
    }

    /// Stamp the current in-memory activity onto a run about to be persisted, so
    /// transition saves carry activity truth for free (no separate write).
    public func stamp(_ run: inout TeamRun) {
        guard let latest = current(runId: run.id) else { return }
        run.lastActivityAt = latest.at
        run.lastActivityKind = latest.kind
    }

    /// Drop a run's in-memory state once it is terminal / no longer tracked.
    public func forget(runId: String) {
        lock.lock(); defer { lock.unlock() }
        states[runId] = nil
    }
}
