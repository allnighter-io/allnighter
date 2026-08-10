import XCTest
@testable import AllnighterCore
@testable import AllnighterMac
import AllnighterEngine

@MainActor
final class CapacityStripModelTests: XCTestCase {

    private final class CountingProbeExecutor: CapacityProbeExecuting, @unchecked Sendable {
        private let lock = NSLock()
        private var _callCount = 0
        var callCount: Int {
            lock.lock(); defer { lock.unlock() }
            return _callCount
        }
        func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
            lock.lock(); _callCount += 1; lock.unlock()
            return [
                CapacityWindow.unknown(
                    reason: .parserFailed(observedAt: request.now),
                    source: request.source,
                    scope: .weekly,
                    observedAt: request.now,
                    sourceTier: .tuiProbe
                ),
            ]
        }
    }

    private struct FixtureProbeExecutor: CapacityProbeExecuting {
        let results: [String: [CapacityWindow]]
        func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
            results[request.source] ?? [
                CapacityWindow.unknown(
                    reason: .parserFailed(observedAt: request.now),
                    source: request.source,
                    scope: .weekly,
                    observedAt: request.now,
                    sourceTier: .tuiProbe
                ),
            ]
        }
    }

    /// Resident backed by a probe executor — no real PTYs, no 2-minute acquire
    /// floor (acquireFloor: 0 — the injected no-op sleep would otherwise spin
    /// the floor forever), history recorded into a temp store.
    private func makeResident(
        historyStore: CapacityHistoryStore,
        probeExecutor: (any CapacityProbeExecuting)?,
        killRecorder: KillRecorder? = nil
    ) -> CapacityResidentService {
        CapacityResidentService(
            sleep: { _ in },
            makeScope: {
                if let killRecorder {
                    return CapacityProbeScope { pid in killRecorder.record(pid) }
                }
                return CapacityProbeScope()
            },
            acquireFloor: 0,
            fetch: { source, scope in
                CapacityFetch.liveSnapshot(
                    refreshSource: source,
                    historyStore: historyStore,
                    probeExecutor: probeExecutor,
                    probeScope: scope
                )
            }
        )
    }

    private func makeModel(
        historyStore: CapacityHistoryStore,
        probeExecutor: (any CapacityProbeExecuting)?,
        killRecorder: KillRecorder? = nil
    ) -> CapacityStripModel {
        CapacityStripModel(
            resident: makeResident(
                historyStore: historyStore,
                probeExecutor: probeExecutor,
                killRecorder: killRecorder
            )
        )
    }

    private func makeTempStore() throws -> (URL, CapacityHistoryStore) {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let historyRoot = tempRoot.appendingPathComponent("capacity", isDirectory: true)
        return (tempRoot, CapacityHistoryStore(rootDirectory: historyRoot))
    }

    func testLoadLiveShowsPlaceholdersNotHistory() async throws {
        let clock = Date()
        let resetAt = clock.addingTimeInterval(32 * 3600)
        let staleObserved = clock.addingTimeInterval(-7_200)

        let (tempRoot, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try store.record([
            CapacityWindow(
                used: 18,
                source: "claude_code",
                scope: .weekly,
                resetAt: resetAt,
                resetPrecision: .exact,
                observedAt: staleObserved,
                sourceTier: .tuiProbe,
                planTier: "Max"
            ),
        ], now: clock)

        let executor = CountingProbeExecutor()
        let model = makeModel(historyStore: store, probeExecutor: executor)
        await model.loadLive()

        XCTAssertTrue(model.needsLiveRefresh)
        XCTAssertEqual(executor.callCount, 0, "launch must not probe")
        let claude = try XCTUnwrap(model.windows.first { $0.source == "claude_code" })
        XCTAssertEqual(claude.unknownReason, .neverSampled)
        XCTAssertNil(claude.usedPercent, "must not paint history on launch")
    }

    func testLoadLiveDoesNotProbe() async throws {
        let (tempRoot, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let executor = CountingProbeExecutor()
        let model = makeModel(historyStore: store, probeExecutor: executor)
        await model.loadLive()
        XCTAssertEqual(executor.callCount, 0)
        for _ in 0..<40 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(model.isRefreshingAll)
        // Cold launch paints placeholders only — no silent acquire, no Refresh
        // coalesce. Live numbers require explicit Refresh / Enable.
        XCTAssertTrue(model.needsLiveRefresh)
        XCTAssertEqual(executor.callCount, 0, "loadLive must stay process-quiet")
    }

    func testLoadLivePaintsResidentSnapshotWhenPresent() async throws {
        let clock = Date()
        let (tempRoot, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let probeExecutor = FixtureProbeExecutor(results: [
            "claude_code": [
                CapacityWindow(
                    used: 96,
                    source: "claude_code",
                    scope: .weekly,
                    resetAt: clock.addingTimeInterval(32 * 3600),
                    resetPrecision: .exact,
                    observedAt: clock,
                    sourceTier: .tuiProbe,
                    planTier: "Max"
                ),
            ],
        ])
        let resident = makeResident(historyStore: store, probeExecutor: probeExecutor)
        let model = CapacityStripModel(resident: resident)
        model.refreshAll()
        for _ in 0..<400 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        // A second launch surface over the same resident paints its snapshot —
        // the resident, not a process memo, owns launch truth (CWB-S01a).
        let second = CapacityStripModel(resident: resident)
        await second.loadLive()
        XCTAssertFalse(second.needsLiveRefresh)
        let claude = try XCTUnwrap(second.windows.first { $0.source == "claude_code" })
        XCTAssertEqual(try XCTUnwrap(claude.usedPercent), 96, accuracy: 0.5)
    }

    func testRefreshAllReplacesWithLiveProbe() async throws {
        let clock = Date()
        let resetAt = clock.addingTimeInterval(32 * 3600)

        let (tempRoot, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let probeExecutor = FixtureProbeExecutor(results: [
            "claude_code": [
                CapacityWindow(
                    used: 96,
                    source: "claude_code",
                    scope: .weekly,
                    resetAt: resetAt,
                    resetPrecision: .exact,
                    observedAt: clock,
                    sourceTier: .tuiProbe,
                    planTier: "Max"
                ),
            ],
        ])

        let model = makeModel(historyStore: store, probeExecutor: probeExecutor)
        await model.loadLive()
        model.refreshAll()

        for _ in 0..<400 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let refreshed = try XCTUnwrap(model.windows.first { $0.source == "claude_code" })
        let used = try XCTUnwrap(refreshed.usedPercent)
        XCTAssertEqual(used, 96, accuracy: 0.5)
        XCTAssertFalse(model.needsLiveRefresh)
    }

    func testFailedLiveProbeDoesNotHydrateHistory() async throws {
        let clock = Date()
        let resetAt = clock.addingTimeInterval(32 * 3600)

        let (tempRoot, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try store.record([
            CapacityWindow(
                used: 18,
                source: "claude_code",
                scope: .weekly,
                resetAt: resetAt,
                resetPrecision: .exact,
                observedAt: clock.addingTimeInterval(-7_200),
                sourceTier: .tuiProbe,
                planTier: "Max"
            ),
        ], now: clock)

        let model = makeModel(historyStore: store, probeExecutor: CountingProbeExecutor())
        model.refreshAll()

        for _ in 0..<400 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let claude = try XCTUnwrap(model.windows.first { $0.source == "claude_code" })
        XCTAssertNil(claude.usedPercent, "failed probe must show unknown, never history %")
        XCTAssertNotNil(claude.unknownReason)
    }

    func testCapacityFetchMatchesSixRowBench() {
        let clock = Date()
        let bench = CapacityFetch.launchSnapshot(now: clock)
        XCTAssertEqual(bench.rows.count, CapacityAcquisition.benchSourceOrder.count)
        XCTAssertEqual(bench.now, clock)
    }

    // MARK: - Header band: on-bench count, parked footer, freshness line

    func testParkedSeatsLeaveTheTableAndAreNamedInstead() {
        let model = CapacityStripModel()
        model.seedFixture(
            windows: CapacityStripFixtures.mixedWindows(),
            now: CapacityStripFixtures.now,
            notReadyOrParked: ["grok"]
        )
        XCTAssertFalse(
            model.benchRows.contains { $0.source == "grok" },
            "a parked seat cannot take work — it must not hold a table row"
        )
        XCTAssertEqual(model.onBenchCount, model.rows.count - 1)
        XCTAssertEqual(
            model.parkedDisplayNames,
            [CapacityStripRenderer.displayName(for: "grok")],
            "the footer names who is parked; a bare count sends the reader hunting"
        )
    }

    // MARK: - Hero: the slot is never empty

    func testCalmBenchStillGetsAHero() {
        let model = CapacityStripModel()
        model.seedFixture(
            windows: CapacityStripFixtures.calmWindows(),
            now: CapacityStripFixtures.now
        )
        XCTAssertEqual(
            model.hero?.mood, .mostRoom,
            "nothing expiring must still name a seat — an empty slot leaves the "
            + "launch surface opening on a bare table"
        )
    }

    func testExpiringSeatOutranksMostRoom() {
        let model = CapacityStripModel()
        model.seedFixture(
            windows: CapacityStripFixtures.mixedWindows(),
            now: CapacityStripFixtures.now
        )
        XCTAssertEqual(model.hero?.mood, .expiring)
    }

    func testMostRoomIsBoundByASeatsScarcestPool() {
        let model = CapacityStripModel()
        model.seedFixture(
            windows: CapacityStripFixtures.calmWindows(),
            now: CapacityStripFixtures.now
        )
        // Antigravity's Gemini pool is the highest single number on the bench,
        // but its Claude/GPT pool is lower than Cursor's — a seat is only as
        // free as its scarcest bucket, so it must not win on the flattering one.
        XCTAssertNotEqual(model.hero?.source, "agy")
    }

    // MARK: - Age chips: silence must mean verified, never unchecked

    func testRowWithNoDeterminableAgeShowsItsOwnChip() {
        let model = CapacityStripModel()
        model.seedFixture(
            windows: CapacityStripFixtures.mixedWindows(),
            now: CapacityStripFixtures.now
        )
        // A row the header cannot vouch for must print, so an absent chip can
        // only ever mean "sampled with the rest of the bench".
        let stale = model.benchRows.first { CapacityStripRenderer.observedAt(for: $0) == nil }
        if let stale {
            XCTAssertTrue(model.showsOwnAge(stale))
        }
        XCTAssertNotNil(model.benchObservedAt, "a sampled bench has a wave time")
    }

    func testStragglerDoesNotForceEveryRowToPrint() {
        let model = CapacityStripModel()
        model.seedFixture(
            windows: CapacityStripFixtures.mixedWindows(),
            now: CapacityStripFixtures.now
        )
        let printing = model.benchRows.filter { model.showsOwnAge($0) }
        XCTAssertLessThan(
            printing.count, model.benchRows.count,
            "one stale seat must not push a timestamp back onto every row — that "
            + "is the duplication the header replaced"
        )
    }

    func testBareAgeLabelDropsTheAgoSuffix() {
        XCTAssertEqual(
            CapacityStripRenderer.elapsedLabel(
                from: CapacityStripFixtures.now,
                to: CapacityStripFixtures.now.addingTimeInterval(14 * 60)
            ),
            "14m ago"
        )
        let model = CapacityStripModel()
        model.seedFixture(
            windows: CapacityStripFixtures.mixedWindows(),
            now: CapacityStripFixtures.now.addingTimeInterval(14 * 60)
        )
        for row in model.benchRows {
            XCTAssertFalse(
                CapacityStripRenderer.bareAgeLabel(for: row, now: model.now).contains("ago"),
                "a column of eight \"ago\"s is a stutter; the header says it once"
            )
        }
    }

    func testFreshnessLineSaysStoppedWhenNothingIsScheduling() {
        let model = CapacityStripModel()
        model.seedFixture(windows: [], now: CapacityStripFixtures.now)
        model.disableFeature()
        // Freshness must come from the resident's armed flag, never from data
        // age — a long legitimate deadline wait looks identical to a dead loop.
        XCTAssertEqual(
            CapacityStripModel.freshnessLine(
                freshness: .init(armed: false, lastSettledAt: CapacityStripFixtures.now),
                isRefreshingAll: false,
                benchObservedAt: nil,
                now: CapacityStripFixtures.now
            ),
            "Auto-checks stopped"
        )
    }

    func testFreshnessLineReportsAgeWhileArmed() {
        let settled = CapacityStripFixtures.now
        XCTAssertEqual(
            CapacityStripModel.freshnessLine(
                freshness: .init(armed: true, lastSettledAt: settled),
                isRefreshingAll: false,
                benchObservedAt: nil,
                now: settled.addingTimeInterval(4 * 60)
            ),
            "Checked 4m ago"
        )
        XCTAssertEqual(
            CapacityStripModel.freshnessLine(
                freshness: .init(armed: true, lastSettledAt: nil),
                isRefreshingAll: false,
                benchObservedAt: nil,
                now: settled
            ),
            "Checking…",
            "armed with nothing settled yet is warming, not stale"
        )
        XCTAssertEqual(
            CapacityStripModel.freshnessLine(
                freshness: .init(armed: false, lastSettledAt: settled),
                isRefreshingAll: true,
                benchObservedAt: nil,
                now: settled
            ),
            "Checking…",
            "an in-flight manual refresh outranks a stopped scheduler"
        )
    }

    // MARK: - Refresh elevation (never sampled / stale → amber)

    func testRefreshElevatesWhenAnySeatIsNeverSampled() {
        let model = CapacityStripModel()
        model.seedFixture(
            windows: CapacityStripFixtures.mixedWindows(),
            now: CapacityStripFixtures.now
        )
        XCTAssertTrue(
            model.refreshIsElevated,
            "Claude and Qwen are neverSampled in the mixed fixture — Refresh is the strip primary"
        )
    }

    func testRefreshElevatesWhenNewestSampleIsOlderThanOneHour() {
        let now = CapacityStripFixtures.now
        let windows = [
            CapacityWindow(
                used: 40,
                source: "codex",
                scope: .weekly,
                resetAt: now.addingTimeInterval(5 * 86400),
                resetPrecision: .exact,
                observedAt: now.addingTimeInterval(-(CapacityStripModel.staleAge + 60)),
                sourceTier: .tuiProbe,
                planTier: "Plus"
            ),
        ]
        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        XCTAssertTrue(
            CapacityStripModel.refreshIsElevated(
                benchRows: rows,
                benchObservedAt: now.addingTimeInterval(-(CapacityStripModel.staleAge + 60)),
                now: now
            ),
            "a sample older than one hour is stale — elevate Refresh"
        )
    }

    func testRefreshStaysQuietWhenEverySeatIsFreshlySampled() {
        let now = CapacityStripFixtures.now
        let windows = [
            CapacityWindow(
                used: 40,
                source: "codex",
                scope: .weekly,
                resetAt: now.addingTimeInterval(5 * 86400),
                resetPrecision: .exact,
                observedAt: now.addingTimeInterval(-45),
                sourceTier: .tuiProbe,
                planTier: "Plus"
            ),
        ]
        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        XCTAssertFalse(
            CapacityStripModel.refreshIsElevated(
                benchRows: rows,
                benchObservedAt: now.addingTimeInterval(-45),
                now: now
            ),
            "fresh, fully sampled board — Refresh is chrome, not the primary"
        )
    }

    func testMeterLinesKeepSeatCountAsCLICountNotPoolCount() {
        let model = CapacityStripModel()
        model.seedFixture(
            windows: CapacityStripFixtures.mixedWindows(),
            now: CapacityStripFixtures.now
        )
        XCTAssertGreaterThan(
            model.meterLines.count,
            model.onBenchCount,
            "Antigravity's two pools must add meter lines without inflating seat count"
        )
        XCTAssertTrue(
            model.meterLines.contains { $0.title == "Antigravity · Gemini" }
        )
        XCTAssertTrue(
            model.meterLines.contains { $0.title == "Antigravity · Claude/GPT" }
        )
        XCTAssertTrue(
            model.meterLines.contains { $0.title == "OpenCode" },
            "OpenCode is the CLI name; Go stays the plan tier"
        )
        XCTAssertTrue(
            model.meterLines.contains { $0.title == "Cursor · Auto" }
        )
        XCTAssertTrue(
            model.meterLines.contains { $0.title == "Cursor · API" },
            "Cursor Auto and API are separate meters"
        )
    }

    // MARK: - CWB-S01a: strip runs through the resident funnel

    /// Resident single-flight: a second full refresh coalesces on the in-flight
    /// generation — it must NOT kill the in-flight scope or start a second wave.
    func testRefreshAllCoalescesInFlightFull() async throws {
        let (tempRoot, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let recorder = KillRecorder()
        let gate = ExecutorGate()
        let blocker = GatedScopeExecutor(fakePID: 7_000_001, gate: gate, recorder: recorder)

        let model = makeModel(historyStore: store, probeExecutor: blocker, killRecorder: recorder)
        model.refreshAll()
        for _ in 0..<200 where !blocker.executed {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(blocker.executed, "first acquire must start")

        // Double-tap: coalesces onto the same generation.
        model.refreshAll()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(recorder.killed.isEmpty, "coalesced full refresh must not kill the in-flight scope")
        XCTAssertTrue(model.isRefreshingAll, "still one in-flight generation")

        gate.open()
        for _ in 0..<200 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(model.isRefreshingAll, "coalesced refresh must settle")
        XCTAssertEqual(
            // The injected executor is the PTY executor — CapacityFetch routes
            // the dashboard wave (opencode_go, bailian_token_plan) through
            // OpenCodeGoCapacityExecutor directly, so only PTY seats reach it.
            blocker.executionCount, CapacityAcquisition.ptySourceOrder.count,
            "exactly one probe wave — no second acquire behind the first"
        )
    }

    /// Full refresh supersedes an in-flight targeted seat refresh with a scoped
    /// terminate (resident-owned, CWB-S00a scoped kill).
    func testRefreshAllSupersedesTargetedScope() async throws {
        let (tempRoot, store) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let recorder = KillRecorder()
        let blocker = BlockingScopeExecutor(
            fakePID: 7_000_002,
            mode: .untilKilled(recorder, source: "claude_code")
        )

        let model = makeModel(historyStore: store, probeExecutor: blocker, killRecorder: recorder)
        model.refreshSource("claude_code")
        for _ in 0..<200 where !blocker.executed {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(blocker.executed, "targeted acquire must start")
        XCTAssertTrue(model.isRefreshing("claude_code"))

        // Full refresh supersedes the targeted one (blocking executor's
        // untilKilled returns after the kill; non-claude seats fail fast).
        model.refreshAll()

        for _ in 0..<200 where !recorder.killed.contains(7_000_002) {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(
            recorder.killed.contains(7_000_002),
            "full refresh must terminate the targeted scope"
        )

        for _ in 0..<400 where model.isRefreshingAll {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(model.isRefreshingAll)
        XCTAssertFalse(model.isRefreshing("claude_code"), "targeted spinner must stop")
    }
}

// MARK: - Test helpers

private final class KillRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _killed: [pid_t] = []

    var killed: [pid_t] {
        lock.lock(); defer { lock.unlock() }
        return _killed
    }

    func record(_ pid: pid_t) {
        lock.lock(); _killed.append(pid); lock.unlock()
    }

    func waitForKill(of pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock(); let hit = _killed.contains(pid); lock.unlock()
            if hit { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        lock.lock(); defer { lock.unlock() }
        return _killed.contains(pid)
    }
}

private final class ExecutorGate: @unchecked Sendable {
    private let lock = NSLock()
    private var _open = false

    var isOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        return _open
    }

    func open() {
        lock.lock(); _open = true; lock.unlock()
    }
}

/// Registers a fake pid into the generation scope, then blocks until the test
/// opens the gate (or the scope is killed). Used to prove coalesce vs kill.
private final class GatedScopeExecutor: CapacityProbeExecuting, @unchecked Sendable {
    let fakePID: pid_t
    let gate: ExecutorGate
    let recorder: KillRecorder
    private let lock = NSLock()
    private var _executions = 0

    var executed: Bool {
        lock.lock(); defer { lock.unlock() }
        return _executions > 0
    }

    var executionCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _executions
    }

    init(fakePID: pid_t, gate: ExecutorGate, recorder: KillRecorder) {
        self.fakePID = fakePID
        self.gate = gate
        self.recorder = recorder
    }

    func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
        lock.lock(); _executions += 1; lock.unlock()
        request.scope?.track(fakePID)
        while !gate.isOpen {
            if recorder.killed.contains(fakePID) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return [
            CapacityWindow.unknown(
                reason: .parserFailed(observedAt: request.now),
                source: request.source,
                scope: .weekly,
                observedAt: request.now,
                sourceTier: .tuiProbe
            ),
        ]
    }
}

private final class BlockingScopeExecutor: CapacityProbeExecuting, @unchecked Sendable {
    enum Mode {
        case untilKilled(KillRecorder, source: String? = nil)
    }

    let fakePID: pid_t
    let mode: Mode
    private let lock = NSLock()
    private var _executed = false

    var executed: Bool {
        lock.lock(); defer { lock.unlock() }
        return _executed
    }

    init(fakePID: pid_t, mode: Mode) {
        self.fakePID = fakePID
        self.mode = mode
    }

    func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
        lock.lock(); _executed = true; lock.unlock()
        request.scope?.track(fakePID)
        switch mode {
        case .untilKilled(let recorder, let sourceFilter):
            if let sourceFilter, request.source != sourceFilter { break }
            _ = recorder.waitForKill(of: fakePID, timeout: 15)
        }
        return [
            CapacityWindow.unknown(
                reason: .parserFailed(observedAt: request.now),
                source: request.source,
                scope: .weekly,
                observedAt: request.now,
                sourceTier: .tuiProbe
            ),
        ]
    }
}
