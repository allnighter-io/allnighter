import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

@MainActor
final class SetupCursorPresentationTests: XCTestCase {

    func testDriverBrandAssetMapsCursorAgent() {
        XCTAssertEqual(DriverBrandAsset.imageName(for: "cursor_agent"), "cursor")
    }

    func testSetupCardsIncludeCursorAgentWithHeadlessTrust() {
        let model = AppModel()
        let card = model.setupCards.first { $0.driverId == "cursor_agent" }
        XCTAssertNotNil(card, "cursor_agent must appear in setup roster from DriverRegistry")
        XCTAssertEqual(card?.name, "Cursor Agent")
        XCTAssertEqual(card?.headlessTrust?.cliFlag, "--trust")
        XCTAssertTrue(card?.headlessTrust?.required ?? false)
        XCTAssertTrue(card?.headlessTrust?.disclosure.contains("--trust") ?? false)
    }

    func testCursorReadyFixtureShowsComposerOnBenchNotFast() {
        #if DEBUG
        let base = AppConfig.loadDefaultModels()
        let patched = GUIFixture.seededModels(base: base, scenario: "readiness-cursor-ready")
        XCTAssertNotNil(patched)
        let auto = patched?.first { $0.id == "model_cursor_auto" }
        let composer = patched?.first { $0.id == "model_cursor_composer_25" }
        let fast = patched?.first { $0.id == "model_cursor_composer_25_fast" }
        XCTAssertTrue(auto?.enabled ?? false, "Auto stays on-bench in cursor-ready fixture")
        XCTAssertTrue(composer?.enabled ?? false, "Composer 2.5 stays on-bench in cursor-ready fixture")
        XCTAssertFalse(fast?.enabled ?? true, "Composer 2.5 Fast stays off-bench")
        #endif
    }

    func testCursorKeychainFixtureMapsToNeedsLogin() {
        #if DEBUG
        let model = AppModel()
        model.applyDevBenchScenario("readiness-cursor-keychain")
        let card = model.setupCards.first { $0.driverId == "cursor_agent" }
        XCTAssertEqual(card?.state, .needsLogin)
        XCTAssertTrue(card?.showsHeadlessTrustDisclosure ?? false)
        #endif
    }

    func testCursorNotCheckedFixtureLeavesCursorUnchecked() {
        #if DEBUG
        let model = AppModel()
        model.applyDevBenchScenario("readiness-cursor-not-checked")
        let card = model.setupCards.first { $0.driverId == "cursor_agent" }
        XCTAssertEqual(card?.state, .notChecked)
        XCTAssertTrue(card?.showsHeadlessTrustDisclosure ?? false)
        #endif
    }
}
