import XCTest
@testable import AllnighterCore

/// Output-discipline + content tests for the `alln team --stream` NDJSON
/// projection (docs/phases/CLI_Implementation_Contract.md §NDJSON Stream).
/// Fixture-only; no live runs.
final class NDJSONStreamProjectorTests: XCTestCase {
    private let terminal: Set<String> = ["teamRunCompleted", "teamRunFailed", "error"]

    /// Each NDJSON line must parse independently as one JSON object, be a single
    /// line, and carry no ANSI. Returns the parsed objects in order.
    private func parseLines(_ lines: [String]) throws -> [[String: Any]] {
        try lines.map { line in
            XCTAssertFalse(line.contains("\n"), "NDJSON line must be single-line")
            XCTAssertFalse(line.contains("\u{1B}"), "no ANSI in machine output")
            let obj = try JSONSerialization.jsonObject(with: Data(line.utf8))
            return try XCTUnwrap(obj as? [String: Any], "each line must be one JSON object")
        }
    }

    func testCompleteRunStreamShapeAndOrder() throws {
        let run = try Fixtures.run(.runComplete)
        let objs = try parseLines(NDJSONStreamProjector.lines(for: run))
        XCTAssertFalse(objs.isEmpty)

        // seq is monotonic 1..N.
        XCTAssertEqual(objs.compactMap { $0["seq"] as? Int }, Array(1...objs.count))
        // Begins with teamRunStarted, ends with a terminal event.
        XCTAssertEqual(objs.first?["event"] as? String, "teamRunStarted")
        XCTAssertEqual(objs.last?["event"] as? String, "teamRunCompleted")
        XCTAssertTrue(terminal.contains(objs.last?["event"] as? String ?? ""))

        let events = objs.compactMap { $0["event"] as? String }
        XCTAssertTrue(events.contains("workerStarted"))
        XCTAssertTrue(events.contains("workerAnswered"))
        XCTAssertTrue(events.contains("planWritten"))   // run_complete has a done plan
        // Every line is stamped with the run id and schemaVersion.
        XCTAssertTrue(objs.allSatisfy { $0["teamRunId"] as? String == run.id })
        XCTAssertTrue(objs.allSatisfy { $0["schemaVersion"] as? Int == 1 })
    }

    func testPartialRunSurfacesWorkerFailuresAndNoPlanWritten() throws {
        let run = try Fixtures.run(.runPartial)
        let objs = try parseLines(NDJSONStreamProjector.lines(for: run))
        let events = objs.compactMap { $0["event"] as? String }

        // Failed workers are visible as workerFailed, each carrying an error.
        XCTAssertTrue(events.contains("workerFailed"))
        let failures = objs.filter { $0["event"] as? String == "workerFailed" }
        XCTAssertTrue(failures.allSatisfy { ($0["data"] as? [String: Any])?["error"] != nil })

        // Plan failed → planStarted but never planWritten.
        XCTAssertTrue(events.contains("planStarted"))
        XCTAssertFalse(events.contains("planWritten"))
        // Partial still terminates as completed (partial -> done).
        XCTAssertEqual(objs.last?["event"] as? String, "teamRunCompleted")
    }

    func testEverySeqIsUniqueAndTerminalIsLastOnly() throws {
        for fixture in [Fixtures.Name.runComplete, .runPartial, .runInflight] {
            let run = try Fixtures.run(fixture)
            let objs = try parseLines(NDJSONStreamProjector.lines(for: run))
            let seqs = objs.compactMap { $0["seq"] as? Int }
            XCTAssertEqual(seqs.count, Set(seqs).count, "seq must be unique in \(fixture.rawValue)")
            let terminals = objs.filter { terminal.contains($0["event"] as? String ?? "") }
            XCTAssertEqual(terminals.count, 1, "exactly one terminal event in \(fixture.rawValue)")
            XCTAssertTrue(terminal.contains(objs.last?["event"] as? String ?? ""), "terminal must be last in \(fixture.rawValue)")
        }
    }
}
