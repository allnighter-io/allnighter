import Foundation
import AllnighterCore

// MARK: - CapacityActivityController (CWB-S01b)

/// App Nap guard held around scheduler waits. Injectable so tests can spy
/// begin/end. The default holds
/// `ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)` for the
/// duration of each deadline wait: App Nap must never delay the one deadline
/// timer by hours, while idle **system** sleep stays allowed on purpose —
/// a real sleep is reported as `.wake` on resume (one refresh, no catch-up
/// burst), so the scheduler must not pin the machine awake for 30-minute waits.
public struct CapacityActivityController: Sendable {

    /// Opaque lease for one held activity. The platform token
    /// (`NSObjectProtocol`, not `Sendable`) travels boxed so the lease can
    /// cross actor hops back to `end`.
    public struct Lease: Sendable {
        public let reason: String
        fileprivate let box: LeaseBox
    }

    fileprivate final class LeaseBox: @unchecked Sendable {
        let token: AnyObject?
        init(_ token: AnyObject?) { self.token = token }
    }

    private let _begin: @Sendable (String) -> Lease
    private let _end: @Sendable (Lease) -> Void

    /// Token-based init: `begin` returns any opaque object it wants handed back
    /// to `end` (nil OK — e.g. a test spy's entry). Boxed internally so the
    /// token can cross actor hops without being `Sendable`.
    public init(
        begin: @escaping @Sendable (String) -> AnyObject?,
        end: @escaping @Sendable (AnyObject?) -> Void
    ) {
        self._begin = { reason in Lease(reason: reason, box: LeaseBox(begin(reason))) }
        self._end = { lease in end(lease.box.token) }
    }

    public func begin(reason: String) -> Lease { _begin(reason) }
    public func end(_ lease: Lease) { _end(lease) }

    /// No-op controller (tests that do not spy, platforms without App Nap).
    public static let disabled = CapacityActivityController(
        begin: { _ in nil },
        end: { _ in }
    )

    #if os(macOS)
    /// Production controller: one `ProcessInfo` activity per deadline wait.
    public static let processInfo = CapacityActivityController(
        begin: { reason in
            ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: reason
            ) as AnyObject
        },
        end: { token in
            if let token {
                // swiftlint:disable:next force_cast
                ProcessInfo.processInfo.endActivity(token as! NSObjectProtocol)
            }
        }
    )
    #else
    public static let processInfo = CapacityActivityController.disabled
    #endif
}

// MARK: - CapacityResidentService (CWB-S01a + S01b)

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
/// S01b adds the one deadline scheduler:
/// - **Monotonic next-deadline** rearmed after every **settle** (success or
///   fail), never after fire alone. Waits via the injected `sleep` until the
///   deadline, holding a `CapacityActivityController` lease (App Nap).
/// - **Wake:** `notifyWake()` (NSWorkspace, wired by the app) or a wall-clock
///   jump past the deadline fires `.wake` **once** — no catch-up burst.
/// - **Feature ON/OFF:** OFF scoped-cancels the in-flight generation, stops
///   the scheduler, zeroes probes from every trigger, and drops the snapshot
///   (no memo-as-live). Enabling starts the scheduler with an immediate
///   silent `.launch` acquire.
public actor CapacityResidentService {

    /// Shared instance for the Dock app host. Tests always inject their own.
    public static let shared = CapacityResidentService()

    // MARK: Reasons

    /// Exhaustive trigger vocabulary (scheduler contract). `.deadline` / `.wake`
    /// are fired only by the S01b scheduler; the rest come from UI / app wiring.
    public enum RefreshReason: Sendable, Equatable {
        /// App up + feature ON → immediate silent acquire.
        case launch
        /// Strip Refresh control (full bench).
        case userRefresh
        /// Strip per-row Refresh control (targeted seat).
        case userRefreshSeat(String)
        /// In-process run settlement for that driver (S03 boolean gate).
        case postRun(source: String)
        /// Monotonic deadline fired (S01b scheduler).
        case deadline
        /// NSWorkspace wake / clock jump (S01b scheduler).
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
    /// Monotonic clock for the deadline (never wall time — S01b).
    private let monotonicNow: @Sendable () -> TimeInterval
    /// App Nap guard held around each deadline wait (spy-able in tests).
    private let activities: CapacityActivityController
    private let makeScope: @Sendable () -> CapacityProbeScope
    private let fetch: Fetch
    /// Floor between acquire **starts** (all reasons). Default 2 minutes.
    private let acquireFloor: TimeInterval
    /// Schedule interval = paint gate = one freshness constant (30m fixed).
    private let scheduleInterval: TimeInterval
    /// Persisted ON/OFF write-through (tiny settings file in production).
    private let persistEnabled: @Sendable (Bool) -> Void
    /// Instrumentation hook for scheduler fires (tests assert reasons).
    private let onSchedulerFire: @Sendable (RefreshReason) -> Void

    public init(
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { interval in
            try? await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
        },
        monotonicNow: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        activities: CapacityActivityController = .processInfo,
        makeScope: @escaping @Sendable () -> CapacityProbeScope = { CapacityProbeScope() },
        acquireFloor: TimeInterval = 120,
        scheduleInterval: TimeInterval = CapacityPaintGate.gateInterval,
        initiallyEnabled: Bool = true,
        persistEnabled: @escaping @Sendable (Bool) -> Void = { enabled in
            CapacityFeatureSettingsPersistence().saveEnabled(enabled)
        },
        onSchedulerFire: @escaping @Sendable (RefreshReason) -> Void = { _ in },
        fetch: @escaping Fetch = { source, scope in
            CapacityFetch.liveSnapshot(refreshSource: source, probeScope: scope)
        }
    ) {
        self.now = now
        self.sleep = sleep
        self.monotonicNow = monotonicNow
        self.activities = activities
        self.makeScope = makeScope
        self.acquireFloor = acquireFloor
        self.scheduleInterval = scheduleInterval
        self.enabled = initiallyEnabled
        self.persistEnabled = persistEnabled
        self.onSchedulerFire = onSchedulerFire
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

    // MARK: S01b — feature ON/OFF + scheduler state

    /// Feature flag. OFF: zero probes from every trigger, no scheduler, no
    /// memo-as-live snapshot. This is also the S02 socket's `disabled` flag.
    private var enabled: Bool
    private struct Scheduler {
        let task: Task<Void, Never>
        let startWall: Date
        let startMonotonic: TimeInterval
    }
    private var scheduler: Scheduler?
    /// Coalescing flag: rapid wake signals collapse to one `.wake` fire.
    private var wakePending = false
    /// True from wake fire until that refresh settles — wake signals arriving
    /// in this window are coalesced into the in-flight resume refresh.
    private var wakeInFlight = false
    /// Monotonic time of the last settle — the deadline rearm anchor.
    private var lastSettleMonotonic: TimeInterval?
    /// The wait currently inside `sleep` — cancelled by wake / OFF / quit.
    private var activeWait: Task<Void, Never>?
    /// Wall-clock jump beyond this tolerance past the deadline counts as wake.
    private static let wakeJumpTolerance: TimeInterval = 90

    /// Current painted truth for read-only consumers (strip launch, S02 socket).
    /// Never starts an acquire. OFF returns nil (socket-disabled, no memo-as-live).
    public func currentSnapshot() -> ResidentCapacitySnapshot? {
        snapshot
    }

    /// Feature flag read (strip CTA, S02 socket disabled answer).
    public var isEnabled: Bool { enabled }

    /// The only ON/OFF write path. Persisted write-through by injection.
    public func setEnabled(_ newValue: Bool) {
        if newValue == enabled {
            // Idempotent re-arm: startup when ON wires the scheduler if needed.
            if newValue { startSchedulerIfNeeded() }
            return
        }
        enabled = newValue
        persistEnabled(newValue)
        if newValue {
            startSchedulerIfNeeded()
        } else {
            stopForFeatureOff()
        }
    }

    /// NSWorkspace wake / detected resume. Coalesces: signals arriving while a
    /// wake is already pending, or while a wake refresh is in flight, collapse
    /// into that one `.wake` fire.
    public func notifyWake() {
        guard enabled, scheduler != nil, !wakePending, !wakeInFlight else { return }
        wakePending = true
        activeWait?.cancel()
    }

    // MARK: Scheduler (S01b)

    /// Startup when ON: wire the one deadline scheduler and fire the immediate
    /// silent `.launch` acquire. Idempotent — never a second timer.
    private func startSchedulerIfNeeded() {
        guard enabled, scheduler == nil else { return }
        let startWall = now()
        let startMonotonic = monotonicNow()
        let task = Task { [self] in
            await self.schedulerLoop(startWall: startWall, startMonotonic: startMonotonic)
        }
        scheduler = Scheduler(task: task, startWall: startWall, startMonotonic: startMonotonic)
        Task { [self] in _ = await self.requestRefresh(reason: .launch) }
    }

    /// Feature OFF: stop the scheduler, scoped-cancel the in-flight generation
    /// (CWB-S00a — never a global kill), and drop painted truth so nothing
    /// reads a stale snapshot as live.
    private func stopForFeatureOff() {
        if let scheduler {
            scheduler.task.cancel()
            self.scheduler = nil
        }
        wakePending = false
        wakeInFlight = false
        activeWait?.cancel()
        activeWait = nil
        lastSettleMonotonic = nil
        if let flight = inFlight {
            flight.scope.terminate()
            flight.task.cancel()
            inFlight = nil
        }
        snapshot = nil
        lastSettled = nil
    }

    /// One rearmed-deadline loop. The next deadline is always computed from the
    /// last **settle** (any reason), never from the previous fire.
    private func schedulerLoop(startWall: Date, startMonotonic: TimeInterval) async {
        while !Task.isCancelled, enabled {
            let deadline = (lastSettleMonotonic ?? startMonotonic) + scheduleInterval
            switch await waitForFire(deadline: deadline) {
            case .stopped:
                return
            case .wake:
                wakePending = false
                wakeInFlight = true
                await fireFromScheduler(.wake)
                wakeInFlight = false
            case .deadline:
                // Large wall-clock jump since the last settle = the machine
                // slept through the deadline: classify as wake — one refresh,
                // no catch-up burst.
                let wallAnchor = snapshot?.settledAt ?? startWall
                let jumped = now().timeIntervalSince(wallAnchor)
                    > scheduleInterval + Self.wakeJumpTolerance
                await fireFromScheduler(jumped ? .wake : .deadline)
            }
        }
    }

    /// Every scheduler fire goes through the same funnel — single-flight,
    /// supersede, and the 2-minute floor all apply to timer ticks too.
    private func fireFromScheduler(_ reason: RefreshReason) async {
        onSchedulerFire(reason)
        _ = await requestRefresh(reason: reason)
    }

    private enum WaitOutcome { case deadline, wake, stopped }

    /// Wait until the monotonic deadline (or wake / OFF / quit), holding the
    /// App Nap activity for the whole wait. The wait is an unstructured child
    /// task so `notifyWake()` / OFF can cancel it while the scheduler task
    /// itself stays alive (OFF cancels the scheduler task too).
    private func waitForFire(deadline: TimeInterval) async -> WaitOutcome {
        let lease = activities.begin(reason: "Allnighter capacity deadline wait")
        defer { activities.end(lease) }
        while !Task.isCancelled {
            if wakePending { return .wake }
            let remaining = deadline - monotonicNow()
            guard remaining > 0 else { return .deadline }
            let wait = Task { [sleep] in await sleep(remaining) }
            activeWait = wait
            await wait.value
            activeWait = nil
            if Task.isCancelled { return .stopped }
            if wakePending { return .wake }
            // Sleep completed naturally — re-evaluate the remaining time.
        }
        return .stopped
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
            // Feature OFF: zero probes from every trigger, no painted truth.
            guard enabled else {
                return CapacityFetch.Snapshot(now: now(), windows: [], rows: [])
            }
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
    /// never painted). Every settle (success or fail, any reason) rearms the
    /// deadline — the scheduler never rearms from fire alone.
    private func settle(generation: Int, targetedSource: String?, result: CapacityFetch.Snapshot) {
        guard inFlight?.generation == generation else { return }
        inFlight = nil
        settledGeneration = generation
        let settledAt = now()
        lastSettleMonotonic = monotonicNow()
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
