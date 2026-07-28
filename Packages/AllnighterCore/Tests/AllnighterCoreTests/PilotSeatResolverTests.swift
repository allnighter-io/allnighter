import XCTest
@testable import AllnighterCore

final class PilotSeatResolverTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func model(_ id: String, name: String, driver: String = "claude_code") -> Model {
        Model(id: id, displayName: name, modelLabel: name.lowercased(), driverId: driver, role: .both)
    }

    func testExactModelIdHonored() {
        let models = [
            model("model_sonnet", name: "Sonnet 4.6"),
            model("model_opus", name: "Opus 5"),
        ]
        XCTAssertEqual(try PilotSeatResolver.resolve(alias: "model_opus", models: models).get(), "model_opus")
    }

    func testDisplayNameRejected() {
        let models = [model("model_opus", name: "Opus 5")]
        let result = PilotSeatResolver.resolve(alias: "Opus 5", models: models)
        guard case .failure(.exactId(let failure)) = result else {
            return XCTFail("expected exactId failure, got \(result)")
        }
        XCTAssertEqual(failure.provided, "Opus 5")
        XCTAssertTrue(failure.suggestionIds.contains("model_opus"))
    }

    func testFuzzyAliasRejected() {
        let models = [
            model("model_sonnet", name: "Sonnet 4.6"),
            model("model_opus", name: "Opus 5"),
        ]
        XCTAssertThrowsError(try PilotSeatResolver.resolve(alias: "opus", models: models).get())
    }

    /// An exact model id must resolve to itself even when it is a substring of other ids.
    func testExactModelIdResolvesToItselfNotAFuzzyMatch() {
        let models = [
            model("model_chatgpt", name: "ChatGPT 5.6 Sol"),
            model("model_chatgpt_54", name: "ChatGPT 5.4"),
            model("model_chatgpt_sol", name: "ChatGPT 5.6 Sol (Cursor)"),
        ]
        XCTAssertEqual(PilotSeatResolver.resolve(alias: "model_chatgpt", models: models), .success("model_chatgpt"))
        XCTAssertEqual(PilotSeatResolver.resolve(alias: "model_chatgpt_sol", models: models), .success("model_chatgpt_sol"))
    }

    func testReadySeatsUsesGlobalProbe() {
        let models = [
            model("model_ready", name: "Ready", driver: "claude_code"),
            model("model_cold", name: "Cold", driver: "codex"),
        ]
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: now),
            ToolProbeRecord(driverId: "codex", status: .notInstalled, lastProbeAt: now),
        ]
        let ready = PilotSeatResolver.readySeats(from: models, probeRecords: records)
        XCTAssertEqual(ready.map(\.id), ["model_ready"])
    }

    /// SR-14 (Sol F28): duplicate probe records for one driver must degrade gracefully.
    func testReadySeatsWithDuplicateDriverRecordsDoesNotCrash() {
        let models = [model("model_ready", name: "Ready", driver: "claude_code")]
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .notInstalled, lastProbeAt: now),
            ToolProbeRecord(driverId: "claude_code", status: .ready(version: "2"), lastProbeAt: now),
        ]
        let ready = PilotSeatResolver.readySeats(from: models, probeRecords: records)
        XCTAssertEqual(ready.map(\.id), ["model_ready"])
    }
}
