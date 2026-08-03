import XCTest
@testable import AllnighterCore
import AllnighterEngine

final class CapacityFetchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_753_833_600)

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
            probeExecutor: FailingExecutor()
        )
        let claude = snap.windows.first { $0.source == "claude_code" }
        XCTAssertNil(claude?.usedPercent)
        XCTAssertNotNil(claude?.unknownReason)
    }

    func testDisabledSnapshotReturnsSixDisabledRows() {
        let snap = CapacityFetch.disabledSnapshot(now: now)
        XCTAssertEqual(snap.windows.count, CapacityAcquisition.benchSourceOrder.count)
        XCTAssertTrue(snap.windows.allSatisfy { $0.unknownReason == .disabled })
        XCTAssertEqual(snap.rows.count, CapacityAcquisition.benchSourceOrder.count)
        XCTAssertTrue(snap.rows.allSatisfy { $0.unknownReason == .disabled })
    }

    func testLiveSnapshotWithSourceTargetsOneSeatAndReturnsSixRows() {
        final class ReturningExecutor: CapacityProbeExecuting, @unchecked Sendable {
            func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
                [
                    CapacityWindow(
                        used: 30,
                        source: request.source,
                        scope: .weekly,
                        resetAt: request.now.addingTimeInterval(24 * 3600),
                        resetPrecision: .exact,
                        observedAt: request.now,
                        sourceTier: .tuiProbe
                    ),
                ]
            }
        }

        let snap = CapacityFetch.liveSnapshot(
            now: now,
            refreshSource: "claude_code",
            probeExecutor: ReturningExecutor()
        )
        XCTAssertEqual(snap.windows.count, CapacityAcquisition.benchSourceOrder.count)
        let claude = snap.windows.filter { $0.source == "claude_code" }
        XCTAssertEqual(claude.count, 1)
        XCTAssertEqual(claude.first?.usedPercent, 30)
        let codex = snap.windows.filter { $0.source == "codex" }
        XCTAssertEqual(codex.count, 1)
        XCTAssertEqual(codex.first?.unknownReason, .neverSampled)
    }
}
