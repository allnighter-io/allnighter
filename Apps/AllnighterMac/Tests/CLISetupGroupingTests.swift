import XCTest
import AllnighterCore
import AllnighterEngine
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

    func testCursorAppPresentSurfacesInstallPrompt() {
        let cards = [
            card("cursor_agent", state: .notInstalled),
            card("agy", state: .notInstalled),
        ]
        let prompted = CLISetupGrouping.cursorInstallPromptCards(from: cards, cursorAppPresent: true)
        XCTAssertEqual(prompted.map(\.driverId), ["cursor_agent"])
        let hidden = CLISetupGrouping.cursorInstallPromptCards(from: cards, cursorAppPresent: false)
        XCTAssertTrue(hidden.isEmpty)
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

    func testParkControlAvailableOnNeedsLoginAndOtherOnMacStates() {
        let parkable: [SetupCardState] = [
            .needsLogin, .waiting, .needsPath, .probeFailed,
            .installedNotProbed, .rateLimited, .ready, .parked,
        ]
        for state in parkable {
            XCTAssertTrue(
                CLISetupGrouping.showsParkControl(for: state),
                "park must stay available for \(state)")
        }
    }

    func testParkControlHiddenDuringInFlightProbeAndCatalogAbsence() {
        let hidden: [SetupCardState] = [
            .detecting, .reprobing, .queued, .notInstalled, .notChecked,
        ]
        for state in hidden {
            XCTAssertFalse(
                CLISetupGrouping.showsParkControl(for: state),
                "park must stay hidden for \(state)")
        }
    }

    func testParkEscapeCaptionOnlyOnAttentionWhileParkable() {
        XCTAssertTrue(CLISetupGrouping.showsParkEscapeCaption(for: .needsLogin))
        XCTAssertTrue(CLISetupGrouping.showsParkEscapeCaption(for: .probeFailed))
        XCTAssertTrue(CLISetupGrouping.showsParkEscapeCaption(for: .needsPath))
        XCTAssertFalse(CLISetupGrouping.showsParkEscapeCaption(for: .ready))
        XCTAssertFalse(CLISetupGrouping.showsParkEscapeCaption(for: .parked))
        XCTAssertFalse(CLISetupGrouping.showsParkEscapeCaption(for: .detecting))
        XCTAssertTrue(
            CLISetupGrouping.parkEscapeCaption.contains("Park it"),
            CLISetupGrouping.parkEscapeCaption)
    }

    func testMuseNeedsLoginFixtureIsParkableAttention() {
        #if DEBUG
        XCTAssertEqual(
            GUIFixture.readinessFocusDriverId(for: "readiness-muse-needs-login"),
            "muse")
        let records = GUIFixture.seededToolStatuses(
            for: [],
            now: Date(timeIntervalSince1970: 0),
            scenario: "readiness-muse-needs-login")
        let cards = AppSetupModel.setupCards(
            registry: DefaultConfig.registry,
            toolStatuses: records,
            models: [],
            parkedDriverIds: [])
        guard let muse = cards.first(where: { $0.driverId == "muse" }) else {
            return XCTFail("muse must be in the setup roster")
        }
        XCTAssertEqual(muse.state, .needsLogin)
        XCTAssertEqual(muse.version, "0.1.0")
        XCTAssertTrue(CLISetupGrouping.showsParkControl(for: muse.state))
        XCTAssertTrue(CLISetupGrouping.showsParkEscapeCaption(for: muse.state))
        #endif
    }

    func testReadySeatDoesNotNeedHealingProbe() {
        XCTAssertFalse(CLISetupGrouping.needsHealingProbe(state: .ready))
        XCTAssertFalse(CLISetupGrouping.needsHealingProbe(state: .parked))
        XCTAssertFalse(CLISetupGrouping.needsHealingProbe(state: .rateLimited))
        XCTAssertTrue(CLISetupGrouping.needsHealingProbe(state: .probeFailed))
        XCTAssertTrue(CLISetupGrouping.needsHealingProbe(state: .needsLogin))
        XCTAssertFalse(CLISetupGrouping.needsHealingProbe(state: .notInstalled))
        XCTAssertTrue(
            CLISetupGrouping.needsHealingProbe(state: .notInstalled, includeCatalogAbsence: true))
    }
}
