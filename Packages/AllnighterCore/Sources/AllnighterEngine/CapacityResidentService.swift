import Foundation
import AllnighterCore

// MARK: - CapacityResidentService (CWB-S01a)

/// Resident owner of capacity freshness in the Dock app (scheduler contract:
/// `docs/phases/Capacity_Warm_Bench.md`).
///
/// - **One funnel:** every acquire goes through `requestRefresh(reason:)`.
/// - **Single-flight:** at most one in-flight `CapacityFetch` generation;
///   concurrent compatible requests coalesce on that generation's result.
/// - **Full supersedes targeted:** a full-bench request cancels an in-flight
///   targeted generation with a **scoped** `CapacityProbeScope.terminate()`
///   (never a global kill — CWB-S00a).
/// - **2-minute floor** between acquire **starts** (all reasons).
/// - Holds one in-memory `ResidentCapacitySnapshot` after settle — the painted
///   truth the S02 socket will serve. Age is measured from settle time.
///
/// S01a ships no timer, no wake observer, no socket: `.deadline` / `.wake` are
/// accepted reasons (S01b will fire them); nothing schedules them yet.
public actor CapacityResidentService {

    /// Shared instance for the Dock app host. Tests always inject their own.
    public static let shared = CapacityResidentService()

    // MARK: Reasons

    /// Exhaustive trigger vocabulary (scheduler contract). `.deadline` / `.wake`
    /// are reserved for S01b — accepted now, fired by nothing in S01a.
    public enum RefreshReason: Sendable, Equatable {
        /// App up + feature ON → immediate silent acquire.
        case launch
        /// Strip Refresh control (full bench).
        case userRefresh
        /// Strip per-row Refresh control (targeted seat).
        case userRefreshSeat(String)
        /// In-process run settlement for that driver (S03 boolean gate).
        case postRun(source: String)
        /// Monotonic deadline fired — S01b.
        case deadline
        /// NSWorkspace wake / clock jump — S01b.
        case wake

        /// Targeted seat when the reason refreshes one seat, else nil (full bench).
        var targetedSource: String? {
            switch self {
            case .userRefreshSeat(let source), .postRun(let source): return source
            case .launch, .userRefresh, .deadline, .wake: return nil
            }
        }
    }

    // MARK: Snapshot

    /// In-memory painted truth after a settle. Age is `now − settledAt`.
    public struct ResidentCapacitySnapshot: Sendable, Equatable {
        public let settledAt: Date
        public let windows: [CapacityWindow]

        public init(settledAt: Date, windows: [CapacityWindow]) {
            self.settledAt = settledAt
            self.windows = windows
        }
    }

    // MARK: Injection seams

    /// One acquire: targeted seat id (nil = full bench) + the generation's
    /// scoped probe registry. Always runs off the resident actor.
    public typealias Fetch = @Sendable (String?, CapacityProbeScope) async -> CapacityFetch.Snapshot

    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let makeScope: @Sendable () -> CapacityProbeScope
    private let fetch: Fetch
    /// Floor between acquire **starts** (all reasons). Default 2 minutes.
    private let acquireFloor: TimeInterval

    public init(
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { interval in
            try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
        },
        makeScope: @escaping @Sendable () -> CapacityProbeScope = { CapacityProbeScope() },
        acquireFloor: TimeInterval = 120,
        fetch: @escaping Fetch = { source, scope in
            CapacityFetch.liveSnapshot(refreshSource: source, probeScope: scope)
        }
    ) {
        self.now = now
        self.sleep = sleep
        self.makeScope = makeScope
        self.acquireFloor = acquireFloor
        self.fetch = fetch
    }

    // MARK: State

    private struct InFlight {
        let generation: Int
        let targetedSource: String?
        let scope: CapacityProbeScope
        let task: Task<CapacityFetch.Snapshot, Never>
    }

    private var snapshot: ResidentCapacitySnapshot?
    /// Latest settled generation's merged snapshot — what waiters paint.
    private var lastSettled: CapacityFetch.Snapshot?
    private var settledGeneration = 0
    private var generationCounter = 0
    private var lastAcquireStart: Date?
    private var inFlight: InFlight?

    /// Current painted truth for read-only consumers (strip launch, S02 socket).
    /// Never starts an acquire.
    public func currentSnapshot() -> ResidentCapacitySnapshot? {
        snapshot
    }

    // MARK: Funnel

    /// The only way anything in the Dock app acquires capacity.
    ///
    /// Coalesce / supersede matrix (in-flight → request):
    /// - full → full, seat X → seat X, full → seat X: **coalesce** on the
    ///   in-flight generation (a full bench covers every seat).
    /// - seat X → full: **supersede** — scoped terminate, then a new generation.
    /// - seat X → seat Y: wait for X to settle, then take our turn (single-flight
    ///   forbids a concurrent second generation; we never kill a healthy seat
    ///   refresh for a sibling seat).
    ///
    /// Callers awaiting a generation that gets superseded are redirected to the
    /// newer truth — never handed the killed generation's partial result.
    public func requestRefresh(reason: RefreshReason) async -> CapacityFetch.Snapshot {
        let target = reason.targetedSource
        var supersededGeneration: Int?
        while true {
            // A newer generation settled while we were waiting: paint its truth.
            if let old = supersededGeneration, inFlight == nil,
               settledGeneration > old, let settled = lastSettled {
                return settled
            }
            if let flight = inFlight {
                let compatible = flight.targetedSource == nil || flight.targetedSource == target
                if compatible {
                    let generation = flight.generation
                    _ = await flight.task.value
                    // Settle runs inside the generation task (before it completes),
                    // so by the time the await returns the outcome is decided.
                    if settledGeneration == generation, let settled = lastSettled {
                        return settled
                    }
                    // Superseded mid-wait — join the newer generation.
                    supersededGeneration = generation
                    continue
                }
                if target == nil {
                    // Full supersedes targeted — scoped kill only (CWB-S00a).
                    flight.scope.terminate()
                    flight.task.cancel()
                    inFlight = nil
                    continue
                }
                // Different targeted seat: take our turn after it settles.
                _ = await flight.task.value
                continue
            }
            // 2-minute floor between acquire starts (all reasons).
            if let lastStart = lastAcquireStart {
                let remaining = acquireFloor - now().timeIntervalSince(lastStart)
                if remaining > 0 {
                    await sleep(remaining)
                    continue
                }
            }
            // Start the next generation. The fetch runs off-actor; the task
            // settles itself before completing so no waiter can observe a
            // completed-but-unsettled generation.
            generationCounter += 1
            let generation = generationCounter
            let scope = makeScope()
            let fetch = self.fetch
            let task = Task.detached { [self] in
                let result = await fetch(target, scope)
                await self.settle(generation: generation, targetedSource: target, result: result)
                return result
            }
            inFlight = InFlight(generation: generation, targetedSource: target, scope: scope, task: task)
            lastAcquireStart = now()
            _ = await task.value
            if let settled = lastSettled, settledGeneration == generation {
                return settled
            }
            // We were superseded by a full bench while acquiring.
            supersededGeneration = generation
        }
    }

    /// Settle a completed generation. Runs inside the generation task before it
    /// completes; a superseded generation settles nothing (killed partials are
    /// never painted).
    private func settle(generation: Int, targetedSource: String?, result: CapacityFetch.Snapshot) {
        guard inFlight?.generation == generation else { return }
        inFlight = nil
        settledGeneration = generation
        let settledAt = now()
        let merged: [CapacityWindow]
        if let source = targetedSource {
            let base = snapshot?.windows ?? CapacityFetch.launchPlaceholders(now: settledAt)
            merged = base.filter { $0.source != source } + result.windows.filter { $0.source == source }
        } else {
            merged = result.windows
        }
        snapshot = ResidentCapacitySnapshot(settledAt: settledAt, windows: merged)
        lastSettled = CapacityFetch.Snapshot(
            now: settledAt,
            windows: merged,
            rows: CapacityBenchProjection.rows(from: merged, now: settledAt)
        )
    }
}

// MARK: - CapacityPaintGate (CWB-S01a)

/// One freshness constant: paint gate = schedule interval = **30 min** fixed.
/// Past the gate, successful seats paint as `.expired` unknowns; seats whose
/// latest attempt already failed keep their honest failure reason.
public enum CapacityPaintGate {

    /// Fixed 30-minute gate (same constant the S01b schedule will use).
    public static let gateInterval: TimeInterval = 30 * 60

    /// Windows as they may be painted at `now`. Pure — no IO, no clocks.
    ///
    /// - Age < 30m: windows pass through unchanged (failed seats stay unknown —
    ///   latest attempt wins per seat).
    /// - Age ≥ 30m: known seats become `.expired` unknowns (original `observedAt`
    ///   preserved so age labels stay honest); already-unknown seats keep their
    ///   original reason.
    public static func paintedWindows(
        _ windows: [CapacityWindow],
        settledAt: Date,
        now: Date
    ) -> [CapacityWindow] {
        guard now.timeIntervalSince(settledAt) < gateInterval else {
            return windows.map { window in
                guard window.unknownReason == nil else { return window }
                return CapacityWindow.unknown(
                    reason: .expired(observedAt: window.observedAt),
                    source: window.source,
                    scope: window.scope,
                    observedAt: window.observedAt,
                    sourceTier: window.sourceTier,
                    poolLabel: window.poolLabel,
                    planTier: window.planTier
                )
            }
        }
        return windows
    }
}
