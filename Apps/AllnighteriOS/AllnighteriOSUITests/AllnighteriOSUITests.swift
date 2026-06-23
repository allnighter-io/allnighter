//
//  AllnighteriOSUITests.swift
//  AllnighteriOSUITests
//
//  Created by Michael Reining on 2026-06-15.
//

import XCTest

final class AllnighteriOSUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchPreviewApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui_testing_preview"] + extraArguments
        app.launchEnvironment["ALLNIGHTER_UI_TESTING_PREVIEW"] = "1"
        app.launch()
        return app
    }

    @MainActor
    private func element(matching identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func waitForPreviewHome(_ app: XCUIApplication, timeout: TimeInterval = 30) {
        XCTAssertTrue(
            element(matching: "connection-status-banner", in: app).waitForExistence(timeout: timeout),
            "preview home did not appear"
        )
        XCTAssertTrue(element(matching: "conversations-title", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element(matching: "ios-composer-bar", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element(matching: "composer-send-button", in: app).waitForExistence(timeout: 8))
    }

    /// Single launch covers home + model picker — avoids cold-start flake between cases.
    @MainActor
    func testPreviewHomeAndModelPicker() throws {
        let app = launchPreviewApp(extraArguments: ["-ui_fixture_model_picker"])
        waitForPreviewHome(app)

        let homeShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        homeShot.name = "home"
        homeShot.lifetime = .keepAlways
        add(homeShot)

        XCTAssertTrue(element(matching: "model-picker-sheet", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Auto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Opus 4.8"].waitForExistence(timeout: 5))

        let agentPrefix = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Agent (")
        )
        XCTAssertEqual(agentPrefix.count, 0, "model picker must not use Agent (...) labels")

        let pickerShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        pickerShot.name = "model-picker"
        pickerShot.lifetime = .keepAlways
        add(pickerShot)
    }
}
