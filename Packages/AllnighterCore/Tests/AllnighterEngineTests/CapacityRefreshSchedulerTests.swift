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
        refresh: @escaping @Sendable (CapacityProbeScope) -> Void = { _ in }
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
            refresh: { _ in },
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
            refresh: { _ in XCTFail("must not probe while the capacity feature is off") },
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
            refresh: { _ in calls.increment() },
            now: { [t0] in t0 },
            sleeper: ImmediateSleeper()
        )
        let ticks = Counter()
        await stale.run { ticks.increment(); return ticks.value > 1 }
        XCTAssertEqual(calls.value, 1, "empty history is stale — must refresh once")

        try record(used: 40, observedAt: t0.addingTimeInterval(-60))
        let fresh = CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: store,
            refresh: { _ in XCTFail("fresh history must not trigger a probe") },
            now: { [t0] in t0 },
            sleeper: ImmediateSleeper()
        )
        let freshTicks = Counter()
        await fresh.run { freshTicks.increment(); return freshTicks.value > 1 }
    }

    /// `run` passes the configured `tickJitterSeconds` to the sleeper, not a
    /// hardcoded 0. A spy records the last jitter value.
    func testRunPassesConfiguredTickJitterToSleeper() async throws {
        let spy = JitterSpySleeper()
        let s = CapacityRefreshScheduler(
            featureSettings: CapacityFeatureSettingsPersistence(
                fileURL: tempRoot.appendingPathComponent("capacity_feature.json")),
            historyStore: store,
            refresh: { _ in },
            now: { [t0] in t0 },
            sleeper: spy,
            tickJitterSeconds: 42
        )
        let ticks = Counter()
        // >2 not >1: the CRS-S01 post-refresh isCancelled check also
        // increments ticks without reaching sleep.
        await s.run { ticks.increment(); return ticks.value > 2 }
        XCTAssertEqual(spy.lastJitter, 42, "sleeper must receive configured tickJitterSeconds")
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
            },
            now: { [t0] in t0 },
            sleeper: ImmediateSleeper(),
            tickJitterSeconds: 0
        )
        let ticks = Counter()
        await s.run { ticks.increment(); return ticks.value > 1 }

        XCTAssertGreaterThanOrEqual(scopePassedCount.value, 1, "scope must be passed to refresh")
        XCTAssertGreaterThanOrEqual(terminateCount.value, 1, "terminate() must be invoked at least once — drain after sync refresh")
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

private final class JitterSpySleeper: PendingWakeSleeper, @unchecked Sendable {
    var lastJitter: TimeInterval?
    func sleep(until: Date, jitterSeconds: TimeInterval) async throws {
        lastJitter = jitterSeconds
    }
}
