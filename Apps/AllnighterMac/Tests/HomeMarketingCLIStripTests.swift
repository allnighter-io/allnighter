import XCTest
@testable import AllnighterMac

@MainActor
final class HomeMarketingCLIStripTests: XCTestCase {

    private func card(_ id: String, state: SetupCardState) -> SetupCardModel {
        SetupCardModel(
            driverId: id, name: id, route: "via \(id)", version: nil, state: state, workers: [],
            loginCommand: nil, installHint: nil, docsURL: nil, loginDocsURL: nil, shimCommand: nil,
            probeReason: nil, headlessTrust: nil)
    }

    func testNeverScannedSuppressesChipRow() {
        let cards = [
            card("claude_code", state: .notChecked),
            card("codex", state: .notChecked),
            card("cursor_agent", state: .notChecked),
        ]
        XCTAssertNil(HomeMarketingCLIStrip.visibleCards(from: cards, showsFindTeamFrame: true))
    }

    func testAfterScanShowsOneCardPerCLI() {
        let cards = [
            card("claude_code", state: .ready),
            card("codex", state: .needsLogin),
            card("missing_cli", state: .notInstalled),
        ]
        let visible = HomeMarketingCLIStrip.visibleCards(from: cards, showsFindTeamFrame: false)
        XCTAssertEqual(visible?.map(\.driverId), ["claude_code", "codex"])
    }

    func testWithoutReadyKeepsNotInstalled() {
        let cards = [
            card("codex", state: .needsLogin),
            card("missing_cli", state: .notInstalled),
        ]
        let visible = HomeMarketingCLIStrip.visibleCards(from: cards, showsFindTeamFrame: false)
        XCTAssertEqual(visible?.map(\.driverId), ["codex", "missing_cli"])
    }

    func testDotFoldMatchesPacketTable() {
        XCTAssertEqual(HomeMarketingCLIStrip.dotKind(for: .ready), .ready)
        XCTAssertEqual(HomeMarketingCLIStrip.dotKind(for: .needsLogin), .attention)
        XCTAssertEqual(HomeMarketingCLIStrip.dotKind(for: .parked), .dormant)
        XCTAssertEqual(HomeMarketingCLIStrip.dotKind(for: .notChecked), .dormant)
        XCTAssertEqual(HomeMarketingCLIStrip.dotKind(for: .rateLimited), .attention)
        XCTAssertEqual(HomeMarketingCLIStrip.dotKind(for: .probeFailed), .attention)
        XCTAssertEqual(HomeMarketingCLIStrip.dotKind(for: .notInstalled), .dormant)
    }

    func testNoModelFanOut_visibleCountBoundedByCardsNotModels() {
        // Grain proof: projection is over setup cards only — N cards → ≤ N chips,
        // never multiply by enabled models on a driver.
        let cards = (0..<9).map { card("cli_\($0)", state: .notChecked) }
        let visible = HomeMarketingCLIStrip.visibleCards(from: cards, showsFindTeamFrame: false)
        XCTAssertEqual(visible?.count, 9)
    }
}
