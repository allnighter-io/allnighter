import XCTest
@testable import AllnighterEngine
@testable import AllnighterCore

/// Serve-hosted capacity refresh (Probe_Freshness §0.2 founder ruling).
///
/// Works Test: with the Mac app not running and `alln serve` up, capacity
/// records refresh on their own; with serve stopped, surfaces report staleness
/// rather than a fresh lie.
final class CapacityRefreshSchedulerTests: XCTestCase {

    private var tempRoot: URL!
    private var store: CapacityHistoryStore!

    private let t0 = Date(timeIntervalSince1970: 1_720_000_000)
    private var resetBase: Date { t0.addingTimeInterval(7 * 24 * 3600) }

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("capacity-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = CapacityHistoryStore(rootDirectory: tempRoot)
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        tempRoot = nil
        store = nil
        try super.tearDownWithError()
    }

    private func scheduler(
        enabled: Bool = true,
        makeScope: @escaping @Sendable () -> CapacityProbeScope = { CapacityProbeScope() },
        refresh: @escaping @Sendable (CapacityProbeScope) async -> CapacityRefreshAttempt = { _ in .durableSuccess }
    ) -> CapacityRefreshScheduler {
        CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: store,
            makeScope: makeScope,
            refresh: refresh,
            now: { [t0] in t0 },
            tickJitterSeconds: 0
        )
    }

    private func record(used: Double, observedAt: Date) throws {
        try store.record(
            [CapacityWindow(
                used: used,
                source: "grok",
                scope: .weekly,
                resetAt: resetBase,
                resetPrecision: .exact,
                observedAt: observedAt,
                sourceTier: .tuiProbe
            )],
            now: observedAt
        )
    }

    /// Nothing has ever observed capacity — refresh. This is the cold case that
    /// makes a freshly installed, app-less machine work at all.
    func testRefreshesWhenHistoryIsEmpty() {
        XCTAssertTrue(scheduler().shouldRefresh(at: t0))
    }

    /// The app is open and refreshing, so history is fresh. Serve must stay out
    /// of the way — two processes probing at once means two waves of vendor TUIs
    /// competing for the machine, and probes are measurably load-sensitive.
    func testDoesNotRefreshWhileHistoryIsFresh() throws {
        try record(used: 40, observedAt: t0.addingTimeInterval(-60))
        XCTAssertFalse(scheduler().shouldRefresh(at: t0))
    }

    /// The app quit (or never opened) and the reading aged past the serve
    /// freshness window (gateInterval + margin) — this is the whole point of
    /// the slice.
    func testRefreshesOnceHistoryAgesPastTheFreshnessWindow() throws {
        try record(
            used: 40,
            observedAt: t0.addingTimeInterval(
                -CapacityPaintGate.gateInterval - CapacityRefreshScheduler.serveFreshnessMargin - 60))
        XCTAssertTrue(scheduler().shouldRefresh(at: t0))
    }

    /// Boundary, both sides — serve uses gateInterval + margin (invariant 3).
    ///
    /// Each case needs its OWN store: history merges and `newestObservation`
    /// takes the max, so recording both samples into one store leaves the
    /// just-inside sample newest and the second assertion silently tests
    /// nothing. (It did, and failed loudly — which is the correct outcome for a
    /// test that was measuring the wrong thing.)
    func testFreshnessBoundaryIsExactAndShared() throws {
        let gate = CapacityPaintGate.gateInterval
        let margin = CapacityRefreshScheduler.serveFreshnessMargin

        let justInside = try isolatedScheduler(
            observedAt: t0.addingTimeInterval(-gate - margin + 1))
        XCTAssertFalse(justInside.shouldRefresh(at: t0), "just inside gate+margin must not refresh")

        let exactlyAt = try isolatedScheduler(
            observedAt: t0.addingTimeInterval(-gate - margin))
        XCTAssertTrue(exactlyAt.shouldRefresh(at: t0), "exactly at gate+margin must refresh")
    }

    /// Age is past bare gateInterval but still inside the serveFreshnessMargin
    /// — serve must NOT refresh because the app's in-flight probe may still be
    /// committing history.
    func testDoesNotRefreshWhenAgeIsWithinMargin() throws {
        let gate = CapacityPaintGate.gateInterval
        try record(used: 40, observedAt: t0.addingTimeInterval(-gate - 30))
        // 30s past gate but well within the 2m margin.
        XCTAssertFalse(scheduler().shouldRefresh(at: t0))
    }

    /// A scheduler over a private store holding exactly one observation.
    private func isolatedScheduler(observedAt: Date) throws -> CapacityRefreshScheduler {
        let root = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let isolated = CapacityHistoryStore(rootDirectory: root)
        try isolated.record(
            [CapacityWindow(
                used: 40, source: "grok", scope: .weekly, resetAt: resetBase,
                resetPrecision: .exact, observedAt: observedAt, sourceTier: .tuiProbe
            )],
            now: observedAt
        )
        return CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(
                fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: isolated,
            refresh: { _ in .durableSuccess },
            now: { [t0] in t0 },
            tickJitterSeconds: 0
        )
    }

    /// Feature OFF means zero probes from every trigger (CWB-S01b). A background
    /// scheduler is not an exception — it must never spend quota the user
    /// switched off, and it is the one trigger the user cannot see happening.
    func testFeatureOffNeverRefreshesEvenWhenStale() throws {
        let settings = CapacityFeatureSettingsPersistence(
            fileURL: tempRoot.appendingPathComponent("capacity_feature.json"))
        try settings.saveEnabled(false)
        try record(used: 40, observedAt: t0.addingTimeInterval(-48 * 3600))

        let off = CapacityRefreshScheduler(
            featureSettings: settings,
            historyStore: store,
            refresh: { _ in XCTFail("must not probe while the capacity feature is off"); return .durableSuccess },
            now: { [t0] in t0 }
        )
        XCTAssertFalse(off.shouldRefresh(at: t0))
    }

    /// Recency is taken across ALL sources, not the first one found: one seat
    /// refreshed recently means the bench as a whole was refreshed recently, and
    /// re-probing on the strength of a single stale seat would spend quota on
    /// every other seat too.
    func testRecencyIsTheNewestObservationAcrossSources() throws {
        try store.record(
            [
                CapacityWindow(used: 10, source: "grok", scope: .weekly, resetAt: resetBase,
                               resetPrecision: .exact,
                               observedAt: t0.addingTimeInterval(-48 * 3600),
                               sourceTier: .tuiProbe),
                CapacityWindow(used: 20, source: "codex", scope: .weekly, resetAt: resetBase,
                               resetPrecision: .exact,
                               observedAt: t0.addingTimeInterval(-60),
                               sourceTier: .tuiProbe),
            ],
            now: t0
        )
        XCTAssertEqual(scheduler().newestObservation(at: t0), t0.addingTimeInterval(-60))
        XCTAssertFalse(scheduler().shouldRefresh(at: t0))
    }

    /// The loop actually calls through when stale, and actually does not when
    /// fresh — the predicate being right is not proof the loop consults it.
    func testRunInvokesRefreshExactlyWhenStale() async throws {
        let calls = Counter()
        let stale = CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: store,
            refresh: { _ in calls.increment(); return .durableSuccess },
            now: { [t0] in t0 },
            sleeper: ImmediateSleeper()
        )
        let ticks = Counter()
        await stale.run { ticks.increment(); return ticks.value > 4 }
        XCTAssertEqual(calls.value, 1, "empty history is stale — must refresh once")

        try record(used: 40, observedAt: t0.addingTimeInterval(-60))
        let fresh = CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: store,
            refresh: { _ in XCTFail("fresh history must not trigger a probe"); return .durableSuccess },
            now: { [t0] in t0 },
            sleeper: ImmediateSleeper()
        )
        let freshTicks = Counter()
        await fresh.run { freshTicks.increment(); return freshTicks.value > 1 }
    }

    /// `run` passes the configured `tickJitterSeconds` to the sleeper, not a
    /// hardcoded 0. A spy records the last jitter value.
    func testRunPassesConfiguredTickJitterToSleeper() async throws {
        let jitterStore = JitterStore()
        let sleeper = CallbackSleeper { _, jitter in
            jitterStore.lastJitter = jitter
        }
        let s = CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(
                fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: store,
            refresh: { _ in .durableSuccess },
            now: { [t0] in t0 },
            sleeper: sleeper,
            tickJitterSeconds: 42
        )
        XCTAssertTrue(s.shouldRefresh(at: t0), "empty history must trigger refresh")
        let ticks = Counter()
        await s.run { ticks.increment(); return ticks.value > 4 }
        XCTAssertEqual(jitterStore.lastJitter, 42, "sleeper must receive configured tickJitterSeconds")
    }

    /// Production default is 60s positive-only jitter — same semantics as
    /// `DefaultPendingWakeSleeper`'s `0...Int(jitterSeconds)`.
    func testProductionDefaultTickJitterIs60() {
        XCTAssertEqual(CapacityRefreshScheduler().tickJitterSeconds, 60)
    }

    // MARK: - CRS-S01: Probe scope wiring

    /// CRS-S01 wiring: a per-refresh `CapacityProbeScope` is created, passed to
    /// `refresh`, and `terminate()` is invoked at least once (after sync refresh
    /// returns = drain, empty PID set).  The cancel-path's in-flight terminate is
    /// also wired but a no-op today — mid-probe kill is unlocked by CRS-S04 async.
    func testProbeScopeIsCreatedPerRefreshAndTerminated() async {
        let terminateCount = Counter()
        let scopePassedCount = Counter()

        let s = CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(
                fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: store,
            makeScope: {
                CapacityProbeScope { _ in terminateCount.increment() }
            },
            refresh: { scope in
                scopePassedCount.increment()
                scope.track(42)
                return .durableSuccess
            },
            now: { [t0] in t0 },
            sleeper: ImmediateSleeper(),
            tickJitterSeconds: 0
        )
        let ticks = Counter()
        await s.run { ticks.increment(); return ticks.value > 4 }

        XCTAssertGreaterThanOrEqual(scopePassedCount.value, 1, "scope must be passed to refresh")
        XCTAssertGreaterThanOrEqual(terminateCount.value, 1, "terminate() must be invoked at least once — drain after sync refresh")
    }

    // MARK: - CRS-S04: Backoff

    /// After one bench-level failure, the next sleep uses 5m backoff instead of
    /// the normal tickInterval.
    func testBackoffFirstFailureSleeps5Minutes() async throws {
        let localT0 = t0
        let deltaStore = DeltaStore()
        let sleeper = CallbackSleeper { until, _ in
            let delta = until.timeIntervalSince(localT0)
            deltaStore.lastDelta = delta
            deltaStore.deltas.append(delta)
        }
        let refreshCount = Counter()
        let s = CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(
                fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: store,
            refresh: { _ in refreshCount.increment(); return .benchFailure },
            now: { [t0] in t0 },
            sleeper: sleeper,
            tickJitterSeconds: 0
        )
        XCTAssertTrue(s.shouldRefresh(at: t0), "empty history must trigger refresh")
        let ticks = Counter()
        await s.run { ticks.increment(); return ticks.value > 4 }
        XCTAssertGreaterThan(refreshCount.value, 0, "refresh must be called when store is empty")
        XCTAssertEqual(deltaStore.lastDelta, Double(5 * 60), "first failure must sleep 5m backoff")
    }

    /// Two consecutive bench-level failures → 10m backoff.
    func testBackoffSecondFailureSleeps10Minutes() async throws {
        let localT0 = t0
        let deltaStore = DeltaStore()
        let sleeper = CallbackSleeper { until, _ in
            deltaStore.deltas.append(until.timeIntervalSince(localT0))
        }
        let s = CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(
                fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: store,
            refresh: { _ in .benchFailure },
            now: { [t0] in t0 },
            sleeper: sleeper,
            tickJitterSeconds: 0
        )
        let ticks = Counter()
        // CRS-S04: 4 isCancelled checks per refresh iteration (while + pre + post1 + post2)
        // → 2 iterations = 8 ticks + 1 exit = need > 8
        await s.run { ticks.increment(); return ticks.value > 8 }
        XCTAssertEqual(deltaStore.deltas, [Double(5 * 60), Double(10 * 60)], "second failure must sleep 10m backoff")
    }

    /// A durable success resets backoff to tickInterval.
    func testDurableSuccessResetsBackoff() async throws {
        let localT0 = t0
        let deltaStore = DeltaStore()
        let sleeper = CallbackSleeper { until, _ in
            deltaStore.deltas.append(until.timeIntervalSince(localT0))
        }
        let callCount = Counter()
        let s = CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(
                fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: store,
            refresh: { _ in
                callCount.increment()
                return callCount.value == 1 ? .benchFailure : .durableSuccess
            },
            now: { [t0] in t0 },
            sleeper: sleeper,
            tickJitterSeconds: 0
        )
        let ticks = Counter()
        await s.run { ticks.increment(); return ticks.value > 8 }
        XCTAssertEqual(deltaStore.deltas, [Double(5 * 60), CapacityRefreshScheduler.tickInterval],
                       "after durableSuccess, backoff must reset to tickInterval")
    }

    /// Partial durable success (≥1 source unknownReason == nil) resets backoff
    /// even if other seats failed. The return value alone is proof (invariant 7).
    func testRefreshVerdictIsDurableSuccess() {
        // .durableSuccess resets backoff regardless of window composition
        // — the refresh closure return value IS the verdict.
        XCTAssertEqual(CapacityRefreshAttempt.durableSuccess, .durableSuccess)
    }

    // MARK: - CRS-S04: Cancel during async refresh

    /// Cancel before refresh: the loop checks `isCancelled()` before `await
    /// refresh`, terminates scope, and breaks without calling refresh.
    func testCancelBeforeAsyncRefreshSkipsRefresh() async throws {
        let refreshCalled = Counter()
        let s = CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(
                fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: store,
            refresh: { _ in refreshCalled.increment(); return .durableSuccess },
            now: { [t0] in t0 },
            sleeper: ImmediateSleeper(),
            tickJitterSeconds: 0
        )
        await s.run { true }
        XCTAssertEqual(refreshCalled.value, 0, "refresh must not be called when immediately cancelled")
    }

    /// Cancel after refresh: the loop checks `isCancelled()` post-await,
    /// calls `inFlight.terminateIfHeld()`, then breaks before sleep.
    func testCancelAfterAsyncRefreshTerminatesAndBreaks() async throws {
        let terminateCount = Counter()
        let s = CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(
                fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: store,
            makeScope: {
                CapacityProbeScope { _ in terminateCount.increment() }
            },
            refresh: { scope in
                scope.track(42)
                return .durableSuccess
            },
            now: { [t0] in t0 },
            sleeper: ImmediateSleeper(),
            tickJitterSeconds: 0
        )
        let tickCount = Counter()
        await s.run {
            tickCount.increment()
            return tickCount.value > 3
        }
        XCTAssertGreaterThanOrEqual(terminateCount.value, 1,
                                    "scope must be terminated when cancelled after refresh")
    }

    /// Cancel mid-probe: refresh awaits a latch; cancel fires while suspended;
    /// sibling poller terminates the scope (spy sees tracked PID) and refresh
    /// returns promptly without waiting forever.
    func testCancelMidProbeTerminatesInFlightScope() async throws {
        let terminateCount = Counter()
        let refreshEntered = Flag()
        let cancel = Flag()
        let refreshReturned = Flag()

        let s = CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(
                fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: store,
            makeScope: {
                CapacityProbeScope { _ in terminateCount.increment() }
            },
            refresh: { scope in
                scope.track(99)
                refreshEntered.set()
                // Stay suspended until cancelled path terminates us — or a
                // safety timeout so a broken poller cannot hang the suite.
                let deadline = Date().addingTimeInterval(2)
                while !cancel.value && Date() < deadline {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                refreshReturned.set()
                return .benchFailure
            },
            now: { [t0] in t0 },
            sleeper: ImmediateSleeper(),
            tickJitterSeconds: 0
        )

        let runTask = Task {
            await s.run {
                // Start uncancelled; flip after refresh has entered.
                cancel.value
            }
        }

        // Wait until refresh is in flight, then cancel.
        let enterDeadline = Date().addingTimeInterval(2)
        while !refreshEntered.value && Date() < enterDeadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(refreshEntered.value, "refresh must have started")
        cancel.set()

        let finished = await runTask.result
        _ = finished
        XCTAssertTrue(refreshReturned.value, "refresh must return after cancel")
        XCTAssertGreaterThanOrEqual(
            terminateCount.value, 1,
            "mid-probe cancel must terminate the in-flight scope")
    }

    // MARK: - CRS-S04: History write failure

    func testSnapshotHistoryWriteFailedDefaultsFalse() {
        let snap = CapacityFetch.Snapshot(now: t0, windows: [], rows: [])
        XCTAssertFalse(snap.historyWriteFailed)
    }

    func testSnapshotDurableSuccessCount() {
        let windows: [CapacityWindow] = [
            CapacityWindow(used: 10, source: "grok", scope: .weekly, resetAt: resetBase,
                          resetPrecision: .exact, observedAt: t0, sourceTier: .tuiProbe),
            CapacityWindow.unknown(reason: .parserFailed(observedAt: t0), source: "codex",
                                   scope: .weekly, observedAt: t0, sourceTier: .tuiProbe),
            CapacityWindow(used: 20, source: "cursor", scope: .weekly, resetAt: resetBase,
                          resetPrecision: .exact, observedAt: t0, sourceTier: .tuiProbe),
        ]
        let snap = CapacityFetch.Snapshot(now: t0, windows: windows, rows: [])
        XCTAssertEqual(snap.durableSuccessCount, 2)
    }

    // MARK: - CRS-S04: Backoff duration math

    func testBackoffDurationMath() {
        let t: (Int) -> TimeInterval = CapacityRefreshScheduler.backoffDuration
        let gate = CapacityPaintGate.gateInterval
        XCTAssertEqual(t(1), 5 * 60, "n=1 → 5m")
        XCTAssertEqual(t(2), 10 * 60, "n=2 → 10m")
        XCTAssertEqual(t(3), 20 * 60, "n=3 → 20m")
        XCTAssertEqual(t(4), min(gate, 40 * 60), "n=4 → capped at gate")
        XCTAssertEqual(t(10), gate, "n=10 → capped at gate")
    }
}

// MARK: - Helpers

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private struct ImmediateSleeper: PendingWakeSleeper {
    func sleep(until: Date, jitterSeconds: Double) async throws {}
}

/// Minimal sleeper that calls a closure on each sleep call.
private struct CallbackSleeper: PendingWakeSleeper {
    let onSleep: @Sendable (Date, TimeInterval) -> Void
    func sleep(until: Date, jitterSeconds: TimeInterval) async throws {
        onSleep(until, jitterSeconds)
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

private final class JitterStore: @unchecked Sendable {
    var lastJitter: TimeInterval?
}

private final class DeltaStore: @unchecked Sendable {
    var lastDelta: TimeInterval = 0
    var deltas: [TimeInterval] = []
}

