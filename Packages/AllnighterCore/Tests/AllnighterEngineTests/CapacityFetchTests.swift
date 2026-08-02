import XCTest
@testable import AllnighterCore
import AllnighterEngine

final class CapacityFetchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_753_833_600)

    override func tearDown() {
        CapacityFetch.clearMemo()
        super.tearDown()
    }

    func testLaunchPlaceholdersAreNeverSampled() {
        let windows = CapacityFetch.launchPlaceholders(now: now)
        XCTAssertEqual(windows.count, CapacityAcquisition.benchSourceOrder.count)
        XCTAssertTrue(windows.allSatisfy { $0.unknownReason == .neverSampled })
    }

    func testLiveSnapshotDoesNotHydrateHistory() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let historyRoot = tempRoot.appendingPathComponent("capacity", isDirectory: true)
        let store = CapacityHistoryStore(rootDirectory: historyRoot)
        try store.record([
            CapacityWindow(
                used: 18,
                source: "claude_code",
                scope: .weekly,
                resetAt: now.addingTimeInterval(32 * 3600),
                resetPrecision: .exact,
                observedAt: now.addingTimeInterval(-7_200),
                sourceTier: .tuiProbe,
                planTier: "Max"
            ),
        ], now: now)

        final class FailingExecutor: CapacityProbeExecuting, @unchecked Sendable {
            func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
                [
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

        let snap = CapacityFetch.liveSnapshot(
            historyStore: store,
            probeExecutor: FailingExecutor(),
            updateMemo: false
        )
        let claude = snap.windows.first { $0.source == "claude_code" }
        XCTAssertNil(claude?.usedPercent)
        XCTAssertNotNil(claude?.unknownReason)
    }

    func testMemoSurvivesWithinTTL() {
        let live = [
            CapacityWindow(
                used: 50,
                source: "grok",
                scope: .weekly,
                resetAt: now.addingTimeInterval(40 * 3600),
                resetPrecision: .exact,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
        ]
        CapacityFetch.clearMemo()
        _ = CapacityFetch.liveSnapshot(
            now: now,
            probeExecutor: FixtureExecutor(windows: live),
            updateMemo: true
        )
        let memo = CapacityFetch.memoIfFresh(now: now.addingTimeInterval(60))
        XCTAssertEqual(memo?.first(where: { $0.source == "grok" })?.usedPercent, 50)
    }

    private struct FixtureExecutor: CapacityProbeExecuting {
        let windows: [CapacityWindow]
        func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
            windows.filter { $0.source == request.source }
        }
    }
}
