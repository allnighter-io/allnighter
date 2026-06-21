import XCTest
@testable import AllnighterMac

/// Bug #2: Floor worker rows show an honest state dot + response time derived from
/// persisted timing (never view-mount time).
final class FloorWorkerStatePresenterTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testDotColorsPerState() {
        XCTAssertEqual(FloorWorkerStatePresenter.dot(status: "running"), .running)
        XCTAssertEqual(FloorWorkerStatePresenter.dot(status: "done"), .done)
        XCTAssertEqual(FloorWorkerStatePresenter.dot(status: "failed"), .failed)
        XCTAssertEqual(FloorWorkerStatePresenter.dot(status: "timed_out"), .failed)
        XCTAssertEqual(FloorWorkerStatePresenter.dot(status: "cancelled"), .failed)
        XCTAssertEqual(FloorWorkerStatePresenter.dot(status: "queued"), .neutral)
        XCTAssertEqual(FloorWorkerStatePresenter.dot(status: "skipped"), .neutral)
    }

    func testDoneUsesDurationMs() {
        let label = FloorWorkerStatePresenter.durationLabel(
            status: "done", startedAt: now.addingTimeInterval(-10), finishedAt: now,
            durationMs: 2300, now: now)
        XCTAssertEqual(label, "2.3s", "done prefers durationMs")
    }

    func testTerminalFallsBackToFinishedMinusStarted() {
        let label = FloorWorkerStatePresenter.durationLabel(
            status: "timed_out", startedAt: now.addingTimeInterval(-300), finishedAt: now,
            durationMs: nil, now: now)
        XCTAssertEqual(label, "5m 0s", "no durationMs → finishedAt - startedAt")
    }

    func testRunningShowsLiveElapsedFromStartedAt() {
        let label = FloorWorkerStatePresenter.durationLabel(
            status: "running", startedAt: now.addingTimeInterval(-42), finishedAt: nil,
            durationMs: nil, now: now)
        XCTAssertEqual(label, "42.0s", "running ticks from startedAt, not mount time")
    }

    func testQueuedHasNoDuration() {
        XCTAssertNil(FloorWorkerStatePresenter.durationLabel(
            status: "queued", startedAt: nil, finishedAt: nil, durationMs: nil, now: now))
    }
}
