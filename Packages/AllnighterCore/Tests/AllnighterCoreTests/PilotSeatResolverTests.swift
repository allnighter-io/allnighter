import XCTest
import AllnighterCore

final class PilotSeatResolverTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func model(_ id: String, name: String, driver: String = "claude_code") -> Model {
        Model(id: id, displayName: name, modelLabel: name.lowercased(), driverId: driver, role: .both)
    }

    func testUniqueAliasResolves() {
        let models = [
            model("model_sonnet", name: "Sonnet 4.6"),
            model("model_opus", name: "Opus 4.8"),
        ]
        XCTAssertEqual(try PilotSeatResolver.resolve(alias: "opus", models: models).get(), "model_opus")
    }

    func testAmbiguousAliasListsCandidates() {
        let models = [
            model("model_sonnet", name: "Sonnet 4.6"),
            model("model_agy_sonnet", name: "AGY Sonnet", driver: "antigravity"),
        ]
        let result = PilotSeatResolver.resolve(alias: "sonnet", models: models)
        guard case .failure(.ambiguous(let alias, let candidates)) = result else {
            return XCTFail("expected ambiguous")
        }
        XCTAssertEqual(alias, "sonnet")
        XCTAssertEqual(candidates.map(\.id).sorted(), ["model_agy_sonnet", "model_sonnet"])
    }

    func testCaseInsensitiveSubstringMatch() {
        let models = [model("model_cursor_grok", name: "Grok 4.5", driver: "cursor_agent")]
        XCTAssertEqual(try PilotSeatResolver.resolve(alias: "GROK", models: models).get(), "model_cursor_grok")
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
}
