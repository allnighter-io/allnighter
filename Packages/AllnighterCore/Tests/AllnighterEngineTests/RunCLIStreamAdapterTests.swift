import XCTest
@testable import AllnighterCLI
@testable import AllnighterCore
@testable import AllnighterEngine

final class RunCLIStreamAdapterTests: XCTestCase {
    private final class Recorder {
        var failures: [(String, String)] = []
        var lines: [String] = []
    }

    func testStreamBranchEmitsTypedServiceFailureAndNonzeroExit() async {
        let recorder = Recorder()
        let outcome = await RunCLI.runStream(.init(
            run: { continuation in
                continuation.finish()
                return .failure(.teamResolution("selected Team is unavailable", code: "TEAM_NOT_FOUND"))
            },
            append: { $0 },
            liveLine: { _ in nil },
            closingLine: { nil },
            writeLine: { recorder.lines.append($0) },
            emitFailure: { recorder.failures.append(($0, $1)) }
        ))

        XCTAssertEqual(outcome.exitCode, 1)
        XCTAssertEqual(outcome.errorCode, "TEAM_NOT_FOUND")
        XCTAssertEqual(recorder.failures.map(\.0), ["TEAM_NOT_FOUND"])
        XCTAssertEqual(recorder.failures.first?.1, "selected Team is unavailable")
    }

    func testStreamBranchEmitsTerminalJournalFailureAndNonzeroExit() async {
        let recorder = Recorder()
        let event = RunEvent(
            id: "event",
            seq: 0,
            ts: Date(),
            kind: RunEventKind.runStatusChanged,
            payload: ["runId": .string("run-1")]
        )
        let outcome = await RunCLI.runStream(.init(
            run: { continuation in
                continuation.yield(event)
                continuation.finish()
                return .failure(.teamResolution("must not replace journal failure", code: "TEAM_NOT_FOUND"))
            },
            append: { _ in throw RemoteRunEventJournalError.missingRunId(eventId: "event") },
            liveLine: { _ in nil },
            closingLine: { nil },
            writeLine: { recorder.lines.append($0) },
            emitFailure: { recorder.failures.append(($0, $1)) }
        ))

        XCTAssertEqual(outcome.exitCode, 1)
        XCTAssertEqual(outcome.errorCode, "STREAM_JOURNAL_FAILED")
        XCTAssertEqual(recorder.failures.map(\.0), ["STREAM_JOURNAL_FAILED"])
        XCTAssertTrue(recorder.failures.first?.1.contains("could not persist a stream event") == true)
    }
}
