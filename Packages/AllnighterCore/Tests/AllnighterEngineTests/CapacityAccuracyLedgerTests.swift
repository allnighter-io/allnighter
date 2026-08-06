import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// The trust gate's "accuracy dogfood ledger" row needs evidence that is
/// honest about absence — a ledger that quietly writes 0% for an unknown seat
/// would manufacture the very confidence the gate exists to withhold.
final class CapacityAccuracyLedgerTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_754_000_000)

    func testUnknownSeatRecordsNilPercentAndAReason() {
        let unknown = CapacityWindow.unknown(
            reason: .neverSampled, source: "grok", scope: .weekly,
            observedAt: now, sourceTier: .tuiProbe
        )
        let entry = CapacityAccuracyLedger.entries(from: [unknown], trigger: "schedule").first
        XCTAssertNil(entry?.remainingPercent, "an unknown seat must never record a number")
        XCTAssertNotNil(entry?.unknownReason, "absence must be explained, not blank")
    }

    func testKnownSeatRecordsItsRemainingPercent() {
        let known = CapacityWindow(
            used: 25, source: "opencode_go", scope: .weekly,
            resetAt: now.addingTimeInterval(3600), resetPrecision: .minute,
            observedAt: now, sourceTier: .dashboardScrape
        )
        let entry = CapacityAccuracyLedger.entries(from: [known], trigger: "manual").first
        XCTAssertEqual(entry?.remainingPercent, 75)
        XCTAssertNil(entry?.unknownReason)
        XCTAssertEqual(entry?.trigger, "manual")
    }

    /// The backstop that protects the founder's real evidence file.
    func testFileSinkWritesNothingUnderTestRunner() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cap-acc-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent("accuracy.jsonl")
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertTrue(
            CapacityAccuracyLedger.isRunningUnderTestRunner,
            "this test is meaningless if the runner is not detected"
        )
        CapacityAccuracyLedger.FileSink(url: url).append(
            CapacityAccuracyLedger.entries(
                from: [CapacityWindow.unknown(
                    reason: .neverSampled, source: "grok", scope: .weekly,
                    observedAt: now, sourceTier: .tuiProbe)],
                trigger: "schedule")
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "the file sink must not write while under a test runner"
        )
    }

    /// Writing is explicit: an empty acquisition must not create a file or a
    /// blank line that later reads as an observation.
    func testEmptyAcquisitionWritesNothing() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cap-acc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("accuracy.jsonl")
        defer { try? FileManager.default.removeItem(at: dir) }
        CapacityAccuracyLedger.write([], to: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
