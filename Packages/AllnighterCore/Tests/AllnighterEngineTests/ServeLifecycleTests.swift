import XCTest
@testable import AllnighterEngine

/// SC-S01 — orphan/wedge LaunchAgent removal. All runners injected; no live
/// `launchctl bootout` or real plist delete ever runs against the host.
final class ServeLifecycleTests: XCTestCase {

    /// Records bootout attempts and plist deletions; failures injectable.
    private final class Harness: @unchecked Sendable {
        var bootoutCalls: [String] = []
        var deletedURLs: [URL] = []
        var bootoutError: Error?
        var deleteError: Error?
        var plistPresent: Bool
        let plistURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).plist")

        init(plistPresent: Bool) { self.plistPresent = plistPresent }

        var lifecycle: ServeLifecycle {
            ServeLifecycle(
                plistURL: plistURL,
                bootout: { [self] label in
                    bootoutCalls.append(label)
                    if let bootoutError { throw bootoutError }
                },
                plistExists: { [self] _ in plistPresent },
                removePlist: { [self] url in
                    if let deleteError { throw deleteError }
                    deletedURLs.append(url)
                }
            )
        }
    }

    private let wedgedObservation = ServeLaunchAgentStatus.Observation(
        state: .wedged, lastExitCode: 78,
        detail: "com.allnighter.resident-coordinator wedged: spawn scheduled, last exit 78, no live job pid")

    // MARK: - remove()

    /// Dogfood fixture: wedged agent + installed plist → bootout attempted on
    /// the same label SC-S00 observes, plist deleted, outcome removed.
    func testRemoveBootsOutLabelAndDeletesPlist() {
        let h = Harness(plistPresent: true)
        let result = h.lifecycle.remove()
        XCTAssertEqual(h.bootoutCalls, [ServeLaunchAgentStatus.label])
        XCTAssertEqual(h.deletedURLs, [h.plistURL])
        XCTAssertEqual(result.outcome, .removed)
        XCTAssertTrue(result.bootoutAttempted)
        XCTAssertTrue(result.plistDeleted)
    }

    /// A real bootout failure (not not-loaded) is never painted as removed.
    func testBootoutFailureReadsFailedAndStillDeletesPlist() {
        let h = Harness(plistPresent: true)
        h.bootoutError = ServeLifecycle.BootoutError(terminationStatus: 1, message: "Boot-out failed: 5: Input/output error")
        let result = h.lifecycle.remove()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.bootoutAttempted)
        XCTAssertTrue(result.plistDeleted, "bootout failure must not skip the plist delete")
    }

    /// A plist delete failure is failed, never removed.
    func testPlistDeleteFailureReadsFailed() {
        let h = Harness(plistPresent: true)
        h.deleteError = CocoaError(.fileWriteNoPermission)
        let result = h.lifecycle.remove()
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertFalse(result.plistDeleted)
    }

    // MARK: - repair(observation:)

    /// Absent observation: no-op success — no bootout, no delete.
    func testRepairAbsentIsNoOpSuccess() {
        let h = Harness(plistPresent: false)
        let report = h.lifecycle.repair(observation: .init(state: .absent, detail: "no plist installed"))
        XCTAssertEqual(report.outcome, .absent)
        XCTAssertNil(report.removal)
        XCTAssertTrue(h.bootoutCalls.isEmpty)
        XCTAssertTrue(h.deletedURLs.isEmpty)
    }

    /// Wedged observation: removal runs and the report carries both truths.
    func testRepairWedgedRemoves() {
        let h = Harness(plistPresent: true)
        let report = h.lifecycle.repair(observation: wedgedObservation)
        XCTAssertEqual(report.outcome, .removed)
        XCTAssertEqual(report.observedState, .wedged)
        XCTAssertEqual(report.removal?.plistDeleted, true)
        XCTAssertEqual(h.bootoutCalls, [ServeLaunchAgentStatus.label])
    }

    /// Unknown (plist present, launchctl print failed) is still an installed
    /// orphan — repair removes it rather than walking away.
    func testRepairUnknownWithPlistRemoves() {
        let h = Harness(plistPresent: true)
        let report = h.lifecycle.repair(observation: .init(state: .unknown, detail: "plist present but print failed"))
        XCTAssertEqual(report.outcome, .removed)
        XCTAssertEqual(h.deletedURLs, [h.plistURL])
    }

    /// A failed removal surfaces through the report as failed (exit non-zero
    /// is the CLI's job on this outcome).
    func testRepairPropagatesFailure() {
        let h = Harness(plistPresent: true)
        h.bootoutError = ServeLifecycle.BootoutError(terminationStatus: 1, message: "Boot-out failed")
        let report = h.lifecycle.repair(observation: wedgedObservation)
        XCTAssertEqual(report.outcome, .failed)
        XCTAssertEqual(report.removal?.outcome, .failed)
    }

    /// The report round-trips through JSON — it is the `serve repair --json`
    /// wire shape.
    func testRepairReportCodableRoundTrip() throws {
        let h = Harness(plistPresent: true)
        let report = h.lifecycle.repair(observation: wedgedObservation)
        let decoded = try JSONDecoder().decode(ServeLifecycle.RepairReport.self,
                                               from: JSONEncoder().encode(report))
        XCTAssertEqual(decoded, report)
    }
}
