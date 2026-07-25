import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

/// FR8 — `--json` streaming commands emit exactly one JSON object per stdout line,
/// including the final envelope (Field_Reports_3.md).
final class JSONStreamLawTests: XCTestCase {

    /// Dumb line-by-line JSON reader — the works-test loop from Field_Reports_3.
    private func parseLines(_ lines: [String]) throws -> [[String: Any]] {
        try lines.map { line in
            XCTAssertFalse(line.contains("\n"), "each stdout line must be single-line JSON")
            let data = Data(line.utf8)
            let obj = try JSONSerialization.jsonObject(with: data)
            return try XCTUnwrap(obj as? [String: Any], "each line must be one JSON object")
        }
    }

    func testJSONLineIsSingleLineAndRoundTrips() throws {
        let sample = RelayProgressJSON(
            contractVersion: ContractRegistry.contractVersion,
            event: "roundStarted",
            round: 1
        )
        let line = AllnighterCLI.jsonLine(sample)
        XCTAssertFalse(line.contains("\n"))
        let objs = try parseLines([line])
        XCTAssertEqual(objs[0]["event"] as? String, "roundStarted")
        XCTAssertEqual(objs[0]["round"] as? Int, 1)
    }

    func testRelayStreamingProgressAndTerminalLinesAllParse() throws {
        let events: [RelayCoordinator.RelayEvent] = [
            .roundStarted(round: 1),
            .pmTurnFinished(round: 1, verdict: .continueRelay),
            .devTurnFinished(round: 1),
        ]
        var lines = events.map { RelayDispatch.progressJSONLine($0) }
        let terminal = RelayJSON.project(
            RelayState(
                id: "relay_stream", projectRoot: "/repo", docPath: "docs/spec.md",
                pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .awaitingPM,
                createdAt: Date()
            ),
            contractVersion: ContractRegistry.contractVersion
        )
        lines.append(AllnighterCLI.jsonLine(terminal))
        let objs = try parseLines(lines)
        XCTAssertEqual(objs.count, 4)
        XCTAssertEqual(objs.last?["relayId"] as? String, "relay_stream")
        XCTAssertEqual(objs.last?["status"] as? String, "awaitingPM")
    }

    func testPilotHandoffStreamingLinesAllParse() throws {
        var lines: [String] = [
            RelayDispatch.progressJSONLine(.roundStarted(round: 1)),
            RelayDispatch.progressJSONLine(.devTurnFinished(round: 1)),
        ]
        let relayJSON = RelayJSON.project(
            RelayState(
                id: "relay_pilot_stream", projectRoot: "/repo", docPath: "docs/spec.md",
                pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .awaitingPM,
                pmMode: .external, createdAt: Date()
            ),
            contractVersion: ContractRegistry.contractVersion
        )
        lines.append(AllnighterCLI.jsonLine(PilotHandoffJSON(relay: relayJSON, devReport: "shipped it")))
        let objs = try parseLines(lines)
        XCTAssertEqual(objs.count, 3)
        XCTAssertNotNil(objs.last?["relay"])
        XCTAssertEqual(objs.last?["devReport"] as? String, "shipped it")
    }

    func testPilotWatchEnvelopeIsSingleLineJSON() throws {
        let relayJSON = RelayJSON.project(
            RelayState(
                id: "relay_watch", projectRoot: "/repo", docPath: "docs/spec.md",
                pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .awaitingPM,
                pmMode: .external, createdAt: Date()
            ),
            contractVersion: ContractRegistry.contractVersion
        )
        let line = AllnighterCLI.jsonLine(PilotWatchJSON(relay: relayJSON, devReport: nil, note: "settled"))
        let objs = try parseLines([line])
        XCTAssertEqual(objs[0]["note"] as? String, "settled")
    }
}
