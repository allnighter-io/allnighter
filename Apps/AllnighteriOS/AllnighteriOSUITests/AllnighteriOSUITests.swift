//
//  AllnighteriOSUITests.swift
//  AllnighteriOSUITests
//
//  Created by Michael Reining on 2026-06-15.
//

import XCTest

final class AllnighteriOSUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testConversationsHomeLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Conversations"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["conversation-search-field"].exists)
        XCTAssertTrue(app.otherElements["ios-composer-bar"].exists)
        XCTAssertTrue(app.buttons["composer-send-button"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
