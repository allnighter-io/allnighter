import XCTest
@testable import AllnighterMac

@MainActor
final class CLISetupGroupingTests: XCTestCase {

    private func card(_ id: String, state: SetupCardState) -> SetupCardModel {
        SetupCardModel(
            driverId: id, name: id, route: "via \(id)", version: nil, state: state, workers: [],
            loginCommand: nil, installHint: nil, docsURL: nil, shimCommand: nil, probeReason: nil,
            headlessTrust: nil)
    }

    func testNotCheckedWithModelsOnBenchIsAttentionNotDormant() {
        let cards = [card("muse", state: .notChecked)]
        let onBench: (String) -> [String] = { $0 == "muse" ? ["Muse Spark 1.2"] : [] }

        XCTAssertEqual(CLISetupGrouping.attentionCards(from: cards, onModelNames: onBench).map(\.driverId), ["muse"])
        XCTAssertTrue(CLISetupGrouping.dormantCards(from: cards, onModelNames: onBench).isEmpty)
        XCTAssertTrue(CLIStatusGroup.isAttention(.notChecked))
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
