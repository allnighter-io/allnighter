import XCTest
@testable import AllnighterEngine
@testable import AllnighterCore

/// CAP-S05 — durable per-window capacity history. Temp root only; never touches
/// real Application Support.
final class CapacityHistoryStoreTests: XCTestCase {

    private var tempRoot: URL!
    private var store: CapacityHistoryStore!

    private let t0 = Date(timeIntervalSince1970: 1_720_000_000)
    private let resetBase = Date(timeIntervalSince1970: 1_720_500_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("capacity-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = CapacityHistoryStore(rootDirectory: tempRoot)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        store = nil
        try super.tearDownWithError()
    }

    // MARK: 1 — Round-trip

    func testRoundTripRecordThenLoadReturnsEqualRecords() throws {
        let window = known(
            source: "codex",
            used: 42,
            resetAt: resetBase,
            observedAt: t0,
            planTier: "plus"
        )
        try store.record([window], now: t0)
        let loaded = store.load(sourceId: "codex")
        XCTAssertEqual(loaded.count, 1)
        let record = try XCTUnwrap(loaded.first)
        XCTAssertEqual(record.sourceId, "codex")
        XCTAssertEqual(record.scope, .weekly)
        XCTAssertEqual(record.resetAt, resetBase)
        XCTAssertEqual(record.resetPrecision, .exact)
        XCTAssertEqual(record.peakUsedPercent, 42)
        XCTAssertEqual(record.firstObservedAt, t0)
        XCTAssertEqual(record.lastObservedAt, t0)
        XCTAssertEqual(record.observationCount, 1)
        XCTAssertEqual(record.planTier, "plus")
        XCTAssertNil(record.poolLabel)
    }

    // MARK: 2 — Codex re-base merge (40s drift → one record)

    func testCodexRebaseMergeWithinTolerance() throws {
        let first = known(source: "codex", used: 30, resetAt: resetBase, observedAt: t0)
        let rebased = known(
            source: "codex",
            used: 55,
            resetAt: resetBase.addingTimeInterval(40),
            observedAt: t0.addingTimeInterval(60)
        )
        try store.record([first], now: t0)
        try store.record([rebased], now: t0.addingTimeInterval(60))

        let loaded = store.load(sourceId: "codex")
        XCTAssertEqual(loaded.count, 1, "40s re-base must merge into one window")
        let record = try XCTUnwrap(loaded.first)
        XCTAssertEqual(record.peakUsedPercent, 55)
        XCTAssertEqual(record.observationCount, 2)
        XCTAssertEqual(record.resetAt, resetBase, "first-seen reset anchors identity")
        XCTAssertEqual(record.lastObservedAt, t0.addingTimeInterval(60))
    }

    // MARK: 3 — Distinct cycles stay distinct

    func testDistinctCyclesStayDistinct() throws {
        let cycle1 = known(source: "codex", used: 40, resetAt: resetBase, observedAt: t0)
        let cycle2 = known(
            source: "codex",
            used: 10,
            resetAt: resetBase.addingTimeInterval(2 * 24 * 60 * 60),
            observedAt: t0.addingTimeInterval(2 * 24 * 60 * 60)
        )
        try store.record([cycle1, cycle2], now: t0)

        let loaded = store.load(sourceId: "codex")
        XCTAssertEqual(loaded.count, 2)
        // Newest-first
        XCTAssertEqual(loaded[0].resetAt, cycle2.resetAt)
        XCTAssertEqual(loaded[1].resetAt, cycle1.resetAt)
    }

    // MARK: 4 — Tolerance boundary (just inside / just outside 15 min)

    func testToleranceBoundary() throws {
        let tolerance = CapacityHistoryStore.resetAtMergeTolerance
        XCTAssertEqual(tolerance, 15 * 60)

        let base = known(source: "codex", used: 20, resetAt: resetBase, observedAt: t0)
        try store.record([base], now: t0)

        // Just inside → merge
        let inside = known(
            source: "codex",
            used: 25,
            resetAt: resetBase.addingTimeInterval(tolerance - 1),
            observedAt: t0.addingTimeInterval(10)
        )
        try store.record([inside], now: t0.addingTimeInterval(10))
        XCTAssertEqual(store.load(sourceId: "codex").count, 1)
        XCTAssertEqual(store.load(sourceId: "codex").first?.observationCount, 2)

        // Just outside → new record (use a fresh store root for a clean pair)
        let root2 = tempRoot.appendingPathComponent("boundary-out", isDirectory: true)
        try FileManager.default.createDirectory(at: root2, withIntermediateDirectories: true)
        let store2 = CapacityHistoryStore(rootDirectory: root2)
        try store2.record([base], now: t0)
        let outside = known(
            source: "codex",
            used: 25,
            resetAt: resetBase.addingTimeInterval(tolerance + 1),
            observedAt: t0.addingTimeInterval(10)
        )
        try store2.record([outside], now: t0.addingTimeInterval(10))
        XCTAssertEqual(store2.load(sourceId: "codex").count, 2)
    }

    // MARK: 5 — Monotonicity

    func testMonotonicityLowerUsedDoesNotLowerPeak() throws {
        let high = known(source: "grok", used: 80, resetAt: resetBase, observedAt: t0)
        let low = known(
            source: "grok",
            used: 50,
            resetAt: resetBase,
            observedAt: t0.addingTimeInterval(120)
        )
        try store.record([high], now: t0)
        try store.record([low], now: t0.addingTimeInterval(120))

        let record = try XCTUnwrap(store.load(sourceId: "grok").first)
        XCTAssertEqual(record.peakUsedPercent, 80)
        XCTAssertEqual(record.observationCount, 2)
        XCTAssertEqual(record.lastObservedAt, t0.addingTimeInterval(120))
        XCTAssertEqual(record.firstObservedAt, t0)
    }

    // MARK: 6 — Unknown windows are not recorded

    func testUnknownWindowsAreNotRecorded() throws {
        let unknown = CapacityWindow.unknown(
            reason: .neverSampled,
            source: "claude",
            scope: .weekly,
            observedAt: t0,
            sourceTier: .tuiProbe
        )
        let knownWindow = known(source: "claude", used: 12, resetAt: resetBase, observedAt: t0)
        try store.record([unknown, knownWindow], now: t0)

        let loaded = store.load(sourceId: "claude")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.peakUsedPercent, 12)
        // Pure unknown batch leaves no file / empty load
        let root2 = tempRoot.appendingPathComponent("unknown-only", isDirectory: true)
        try FileManager.default.createDirectory(at: root2, withIntermediateDirectories: true)
        let store2 = CapacityHistoryStore(rootDirectory: root2)
        try store2.record([unknown], now: t0)
        XCTAssertTrue(store2.load(sourceId: "claude").isEmpty)
    }

    // MARK: 7 — Missing / corrupt file → empty, no throw

    func testMissingAndCorruptFileLoadEmpty() throws {
        XCTAssertEqual(store.load(sourceId: "missing"), [])

        let url = store.fileURL(sourceId: "codex")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try Data("not-json{{{".utf8).write(to: url)
        XCTAssertEqual(store.load(sourceId: "codex"), [])
    }

    // MARK: 8 — Per-source isolation

    func testPerSourceIsolation() throws {
        try store.record(
            [known(source: "grok", used: 10, resetAt: resetBase, observedAt: t0)],
            now: t0
        )
        try store.record(
            [known(source: "codex", used: 90, resetAt: resetBase, observedAt: t0)],
            now: t0
        )

        XCTAssertEqual(store.load(sourceId: "grok").count, 1)
        XCTAssertEqual(store.load(sourceId: "grok").first?.peakUsedPercent, 10)
        XCTAssertEqual(store.load(sourceId: "codex").count, 1)
        XCTAssertEqual(store.load(sourceId: "codex").first?.peakUsedPercent, 90)

        let grokURL = store.fileURL(sourceId: "grok")
        let codexURL = store.fileURL(sourceId: "codex")
        XCTAssertNotEqual(grokURL.path, codexURL.path)
        let grokData = try Data(contentsOf: grokURL)
        let grokText = String(decoding: grokData, as: UTF8.self)
        XCTAssertFalse(grokText.contains("codex"))
        XCTAssertFalse(grokText.contains("90"))
    }

    // MARK: 9 — Plan change timeline survives

    func testPlanChangeProducesSeparateRecordsWithTiers() throws {
        let pro = known(
            source: "codex",
            used: 60,
            resetAt: resetBase,
            observedAt: t0,
            planTier: "pro"
        )
        let plus = known(
            source: "codex",
            used: 20,
            resetAt: resetBase.addingTimeInterval(7 * 24 * 60 * 60),
            observedAt: t0.addingTimeInterval(7 * 24 * 60 * 60),
            planTier: "plus"
        )
        try store.record([pro, plus], now: t0)

        let loaded = store.load(sourceId: "codex")
        XCTAssertEqual(loaded.count, 2)
        let tiers = Set(loaded.compactMap(\.planTier))
        XCTAssertEqual(tiers, ["pro", "plus"])
    }

    // MARK: 10 — No PII in stored JSON

    func testNoPIIInStoredJSON() throws {
        // Intermediate vendor type may carry account; CapacityWindow drops it.
        // Ensure the durable history never reintroduces account strings.
        let account = "emailmike@gmail.com"
        let pool = AgyPoolCapacity(
            account: account,
            name: "GEMINI MODELS",
            memberModels: ["Gemini Flash"],
            windows: [
                AgyCapacityWindow(
                    kind: .weekly,
                    remainingPercent: 61,
                    observedAt: t0,
                    resetAt: resetBase
                )
            ]
        )
        XCTAssertEqual(pool.account, account)
        try store.record(pool.asCapacityWindows(), now: t0)

        let data = try Data(contentsOf: store.fileURL(sourceId: "agy"))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains(account))
        XCTAssertFalse(text.contains("\"account\""))
        XCTAssertTrue(text.contains("GEMINI MODELS"))
        XCTAssertFalse(text.contains("rawSnippet"))
    }

    // MARK: - isClosed derivation

    func testIsClosedDerivedAtReadTime() throws {
        let openReset = t0.addingTimeInterval(3_600)
        let closedReset = t0.addingTimeInterval(-60)
        try store.record(
            [
                known(source: "codex", used: 1, resetAt: openReset, observedAt: t0),
                known(source: "codex", used: 2, resetAt: closedReset, observedAt: t0)
            ],
            now: t0
        )
        let loaded = store.load(sourceId: "codex")
        let open = try XCTUnwrap(loaded.first { $0.resetAt == openReset })
        let closed = try XCTUnwrap(loaded.first { $0.resetAt == closedReset })
        XCTAssertFalse(open.isClosed(at: t0))
        XCTAssertTrue(closed.isClosed(at: t0))
    }

    // MARK: CAP-S07 — record never acquires

    /// Standing founder ruling: recording must never trigger acquisition.
    /// No probe, no spawn, no vendor-directory scan, no fan-out. Events record
    /// from what is already known; they never go and ask.
    func testRecordCallPerformsNoAcquisition() throws {
        // Canary vendor tree that WOULD yield different facts if scanned.
        // CapacityHistoryStore.record has no homeRoot and must not touch it.
        let canaryHome = tempRoot.appendingPathComponent("canary-home", isDirectory: true)
        let canarySessions = canaryHome
            .appendingPathComponent(".codex/sessions/2026/07/30", isDirectory: true)
        try FileManager.default.createDirectory(at: canarySessions, withIntermediateDirectories: true)
        let canaryRollout = canarySessions.appendingPathComponent("rollout-canary.jsonl")
        let canaryLine = #"""
        {"timestamp":"2026-07-30T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400},"rate_limits":{"limit_id":"codex","primary":{"used_percent":99.0,"window_minutes":10080,"resets_at":1785904336},"plan_type":"plus"}}}
        """#.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        try canaryLine.write(to: canaryRollout, atomically: true, encoding: .utf8)
        let canaryAttrsBefore = try FileManager.default.attributesOfItem(atPath: canaryRollout.path)
        let canaryMtimeBefore = canaryAttrsBefore[.modificationDate] as? Date

        // Fabricated known windows — distinctive values, no live sample.
        let fabricatedUsed: Double = 17
        let window = known(
            source: "codex",
            used: fabricatedUsed,
            resetAt: resetBase,
            observedAt: t0,
            planTier: "plus"
        )
        try store.record([window], now: t0)

        // Stored facts match the caller-supplied window, not the canary 99%.
        let loaded = store.load(sourceId: "codex")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.peakUsedPercent, fabricatedUsed)
        XCTAssertNotEqual(loaded.first?.peakUsedPercent, 99)

        // Only the store root gained a file — canary vendor tree untouched.
        let storeFiles = try FileManager.default.contentsOfDirectory(
            at: tempRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let names = Set(storeFiles.map(\.lastPathComponent))
        XCTAssertTrue(names.contains("codex.json"))
        XCTAssertTrue(names.contains("canary-home"))
        XCTAssertEqual(names.count, 2, "record must not create vendor-side artifacts outside store files")

        let canaryAttrsAfter = try FileManager.default.attributesOfItem(atPath: canaryRollout.path)
        let canaryMtimeAfter = canaryAttrsAfter[.modificationDate] as? Date
        XCTAssertEqual(canaryMtimeBefore, canaryMtimeAfter, "record must not open/scan vendor logs")

        // Empty / unknown-only batch still performs no acquisition and writes nothing new.
        let unknown = CapacityWindow.unknown(
            reason: .neverSampled,
            source: "grok",
            scope: .weekly,
            observedAt: t0,
            sourceTier: .onDisk
        )
        try store.record([unknown], now: t0)
        XCTAssertTrue(store.load(sourceId: "grok").isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.fileURL(sourceId: "grok").path),
            "unknown-only record must not invent history files"
        )
    }

    // MARK: CAP-HF-00 — last-known projection

    func testLastKnownWindowsProjectsOpenRecordsWithRealAge() throws {
        let observed = t0.addingTimeInterval(-3_600)
        let openReset = t0.addingTimeInterval(86_400)
        let closedReset = t0.addingTimeInterval(-86_400)
        try store.record([
            known(source: "cursor_agent", used: 28, resetAt: openReset, observedAt: observed, planTier: "Ultra"),
            known(source: "cursor_agent", used: 90, resetAt: closedReset, observedAt: observed.addingTimeInterval(-10_000)),
            known(source: "kimi", used: 100, resetAt: openReset, observedAt: observed),
        ], now: t0)

        let windows = store.lastKnownWindows(sourceIds: ["cursor_agent", "kimi"], now: t0)
        let cursor = windows.filter { $0.source == "cursor_agent" }
        XCTAssertEqual(cursor.count, 1, "closed cycle must drop")
        XCTAssertEqual(cursor.first?.usedPercent, 28)
        XCTAssertEqual(cursor.first?.planTier, "Ultra")
        XCTAssertEqual(cursor.first?.observedAt, observed)
        XCTAssertNil(cursor.first?.unknownReason)

        let kimi = windows.filter { $0.source == "kimi" }
        XCTAssertEqual(kimi.first?.remainingPercent, 0)
        XCTAssertEqual(kimi.first?.observedAt, observed)
    }

    func testDisplayAcquisitionHydratesBareTier3FromHistory() throws {
        let observed = t0.addingTimeInterval(-1_800)
        let openReset = t0.addingTimeInterval(86_400)
        try store.record([
            known(
                source: "agy",
                used: 10,
                resetAt: openReset,
                observedAt: observed,
                poolLabel: "GEMINI MODELS"
            ),
        ], now: t0)

        let home = tempRoot.appendingPathComponent("empty-home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let windows = CapacityDisplayAcquisition.windows(
            homeRoot: home,
            now: t0,
            refresh: false,
            historyStore: store
        )
        let agy = windows.filter { $0.source == "agy" }
        XCTAssertEqual(agy.count, 1)
        XCTAssertEqual(agy.first?.usedPercent, 10)
        XCTAssertEqual(agy.first?.observedAt, observed)
        XCTAssertEqual(agy.first?.poolLabel, "GEMINI MODELS")
        XCTAssertNil(agy.first?.unknownReason)
    }

    // MARK: - Helpers

    private func known(
        source: String,
        used: Double,
        resetAt: Date,
        observedAt: Date,
        planTier: String? = nil,
        poolLabel: String? = nil,
        scope: CapacityWindowScope = .weekly
    ) -> CapacityWindow {
        CapacityWindow(
            used: used,
            source: source,
            scope: scope,
            resetAt: resetAt,
            resetPrecision: .exact,
            observedAt: observedAt,
            sourceTier: .onDisk,
            poolLabel: poolLabel,
            planTier: planTier
        )
    }
}
