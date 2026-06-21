//
//  AllnighteriOSTests.swift
//  AllnighteriOSTests
//
//  Created by Michael Reining on 2026-06-15.
//

import XCTest
@testable import AllnighteriOS

final class AllnighteriOSTests: XCTestCase {

    func testDebugConversationSnapshotMatchesMVPHomeShape() {
        #if DEBUG
        let snapshot = ConversationHomePreviewData.snapshot

        XCTAssertEqual(snapshot.pinned.map(\.title), ["Give me a picture of a cat"])
        XCTAssertEqual(snapshot.projects.map(\.name), ["Allnighter", "X", "Unassigned"])
        XCTAssertEqual(snapshot.projects.last?.isExpanded, true)
        XCTAssertEqual(snapshot.projects.last?.hiddenConversationCount, 1)
        #else
        XCTAssertTrue(ConversationListSnapshot.empty.projects.isEmpty)
        #endif
    }

}
