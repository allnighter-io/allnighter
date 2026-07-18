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

    func testOpusAliasPrefersClaude48OverAgy46() {
        // Both catalog Opus seats match "opus"; Claude 4.8 (rank 100) must win.
        let models = [
            model("model_agy_opus", name: "Claude Opus 4.6", driver: "antigravity"),
            model("model_opus", name: "Opus 4.8"),
        ]
        XCTAssertEqual(try PilotSeatResolver.resolve(alias: "opus", models: models).get(), "model_opus")
    }

    func testAmbiguousAliasListsCandidatesWhenRanksTie() {
        // Two models match with equal (zero) strength — still ambiguous.
        let models = [
            model("model_custom_a", name: "Custom Alpha", driver: "codex"),
            model("model_custom_b", name: "Custom Alpha Plus", driver: "codex"),
        ]
        let result = PilotSeatResolver.resolve(alias: "alpha", models: models)
        guard case .failure(.ambiguous(let alias, let candidates)) = result else {
            return XCTFail("expected ambiguous")
        }
        XCTAssertEqual(alias, "alpha")
        XCTAssertEqual(candidates.map(\.id).sorted(), ["model_custom_a", "model_custom_b"])
    }

    func testSonnetAliasPrefersClaudeCodeOverAgyWhenRanksDiffer() {
        // model_sonnet rank 80; model_agy_sonnet has no explicit rank (0) → Claude Code wins.
        let models = [
            model("model_sonnet", name: "Sonnet 4.6"),
            model("model_agy_sonnet", name: "AGY Sonnet", driver: "antigravity"),
        ]
        XCTAssertEqual(try PilotSeatResolver.resolve(alias: "sonnet", models: models).get(), "model_sonnet")
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

    /// SR-14 (Sol F28): duplicate probe records for one driver (possible via a hand-edited or
    /// migrated `cli_setup.json`) must degrade gracefully — keep the latest — not trap the
    /// process. Before the fix `Dictionary(uniqueKeysWithValues:)` crashed `pilot start`.
    func testReadySeatsWithDuplicateDriverRecordsDoesNotCrash() {
        let models = [model("model_ready", name: "Ready", driver: "claude_code")]
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .notInstalled, lastProbeAt: now),
            ToolProbeRecord(driverId: "claude_code", status: .ready(version: "2"), lastProbeAt: now),
        ]
        let ready = PilotSeatResolver.readySeats(from: models, probeRecords: records)
        // Latest record (ready) wins → seat is offered.
        XCTAssertEqual(ready.map(\.id), ["model_ready"])
    }
}
