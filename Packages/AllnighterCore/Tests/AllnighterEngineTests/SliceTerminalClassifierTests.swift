import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class SliceTerminalClassifierTests: XCTestCase {
    private func packet() -> WorkSlicePacket {
        .init(
            sliceId: "S1",
            intent: "x",
            touchAllowlist: ["a.swift"],
            check: .init(method: .command, command: "true")
        )
    }

    func testPassedWhenCheckSucceeds() {
        let outcome = WorkerRunOutcome(status: .done, output: "done")
        let check = CheckResult(exitCode: 0)
        let terminal = SliceTerminalClassifier.classify(
            .init(workerOutcome: outcome, check: check, packet: packet(), now: Date())
        )
        XCTAssertEqual(terminal, .passed)
    }

    func testFailedWhenCheckNonZero() {
        let outcome = WorkerRunOutcome(status: .done, output: "done")
        let check = CheckResult(exitCode: 1)
        let terminal = SliceTerminalClassifier.classify(
            .init(workerOutcome: outcome, check: check, packet: packet(), now: Date())
        )
        XCTAssertEqual(terminal, .failed)
    }

    func testStalledOnEmptyOutput() {
        let outcome = WorkerRunOutcome(status: .done, output: "")
        let check = CheckResult(exitCode: 0)
        let terminal = SliceTerminalClassifier.classify(
            .init(workerOutcome: outcome, check: check, packet: packet(), now: Date())
        )
        XCTAssertEqual(terminal, .stalled)
    }

    func testAdvisoryReviewPassesWhenCheckPassesDespiteEmptyVisible() {
        var p = packet()
        p.mode = .review
        let outcome = WorkerRunOutcome(status: .done, output: "")
        let check = CheckResult(exitCode: 0)
        let terminal = SliceTerminalClassifier.classify(
            .init(workerOutcome: outcome, check: check, packet: p, now: Date())
        )
        XCTAssertEqual(terminal, .passed)
    }

    func testDoneWithBackoffSubstringAndPassedCheckIsPassed() {
        let outcome = WorkerRunOutcome(status: .done, output: "server busy but finished")
        let check = CheckResult(exitCode: 0)
        let terminal = SliceTerminalClassifier.classify(
            .init(workerOutcome: outcome, check: check, packet: packet(), now: Date())
        )
        XCTAssertEqual(terminal, .passed)
    }

    func testCompactionMarkerWhileRunning() {
        let started = Date().addingTimeInterval(-30)
        var outcome = WorkerRunOutcome(status: .running, output: "Compaction in progress")
        outcome.startedAt = started
        let check = CheckResult()
        let terminal = SliceTerminalClassifier.classify(
            .init(workerOutcome: outcome, check: check, packet: packet(), now: Date())
        )
        XCTAssertEqual(terminal, .compacting)
    }
}
