import XCTest
@testable import AllnighterMac

@MainActor
final class CLISetupGroupingTests: XCTestCase {

    private func card(_ id: String, state: SetupCardState) -> SetupCardModel {
        SetupCardModel(
            driverId: id, name: id, route: "via \(id)", version: nil, state: state, workers: [],
            loginCommand: nil, installHint: nil, docsURL: nil, loginDocsURL: nil, shimCommand: nil, probeReason: nil,
            headlessTrust: nil)
    }

    func testCatalogAbsencesAreNotNeedsAttention() {
        // Dropdown / chrome: notInstalled and notChecked are catalog, not "need a step".
        XCTAssertFalse(CLIStatusGroup.isAttention(.notInstalled))
        XCTAssertFalse(CLIStatusGroup.isAttention(.notChecked))
        let cards = [
            card("agy", state: .notInstalled),
            card("muse", state: .notChecked),
            card("claude_code", state: .probeFailed),
        ]
        let recognized = CLISetupGrouping.recognizedCards(from: cards)
        XCTAssertEqual(recognized.map(\.driverId), ["claude_code"])
        let onBench: (String) -> [String] = { _ in [] }
        XCTAssertEqual(
            CLISetupGrouping.attentionCards(from: recognized, onModelNames: onBench).map(\.driverId),
            ["claude_code"])
        XCTAssertEqual(
            CLISetupGrouping.notInstalledCards(from: cards).map(\.driverId),
            ["agy"])
    }

    func testProbeFailedAndNeedsLoginAreAttention() {
        let cards = [
            card("cursor_agent", state: .probeFailed),
            card("codex", state: .needsLogin),
        ]
        let onBench: (String) -> [String] = { _ in [] }
        XCTAssertEqual(
            CLISetupGrouping.attentionCards(from: cards, onModelNames: onBench).map(\.driverId),
            ["cursor_agent", "codex"])
    }

    func testReadyWithNoModelsOnBenchIsDormant() {
        let cards = [card("muse", state: .ready)]
        let onBench: (String) -> [String] = { _ in [] }

        XCTAssertTrue(CLISetupGrouping.attentionCards(from: cards, onModelNames: onBench).isEmpty)
        XCTAssertEqual(CLISetupGrouping.dormantCards(from: cards, onModelNames: onBench).map(\.driverId), ["muse"])
        XCTAssertFalse(CLIStatusGroup.isAttention(.ready))
    }

    func testNeedsLoginWithModelsOnBenchIsAttention() {
        let cards = [card("muse", state: .needsLogin)]
        let onBench: (String) -> [String] = { $0 == "muse" ? ["Muse Spark 1.2"] : [] }

        XCTAssertEqual(CLISetupGrouping.attentionCards(from: cards, onModelNames: onBench).map(\.driverId), ["muse"])
        XCTAssertTrue(CLISetupGrouping.dormantCards(from: cards, onModelNames: onBench).isEmpty)
    }
}
