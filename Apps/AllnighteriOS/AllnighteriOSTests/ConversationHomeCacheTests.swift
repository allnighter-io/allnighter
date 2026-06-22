//
//  ConversationHomeCacheTests.swift
//  AllnighteriOSTests
//

import XCTest
@testable import AllnighteriOS

@MainActor
final class ConversationHomeCacheTests: XCTestCase {
    func testRoundTripPersistsConversationHomeSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("conversation_home.json")
        let cache = ConversationHomeCache(fileURL: fileURL)
        let serverTime = Date(timeIntervalSince1970: 1_751_200_000)
        let snapshot = ConversationListSnapshot(
            pinned: [
                ConversationSummary(
                    id: "thread_1",
                    title: "Cached thread",
                    relativeAge: "1 hour ago",
                    statusLabel: "Running",
                    isUnread: false,
                    isPending: true
                ),
            ],
            projects: []
        )
        let entry = ConversationHomeCacheEntry(
            accountId: "acct_1",
            macAgentId: "mac_1",
            serverTime: serverTime,
            cachedAt: Date(timeIntervalSince1970: 1_751_200_100),
            snapshot: snapshot
        )

        try cache.save(entry)
        let loaded = try XCTUnwrap(cache.load())

        XCTAssertEqual(loaded, entry)
    }

    func testLoadReturnsNilForMismatchedVersion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("conversation_home.json")
        let cache = ConversationHomeCache(fileURL: fileURL)
        var entry = ConversationHomeCacheEntry(
            accountId: "acct_1",
            macAgentId: "mac_1",
            serverTime: Date(),
            snapshot: .empty
        )
        entry.version = 0
        try cache.save(entry)

        XCTAssertNil(try cache.load())
    }
}
