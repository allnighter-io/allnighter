//
//  AllnighteriOSTests.swift
//  AllnighteriOSTests
//
//  Created by Michael Reining on 2026-06-15.
//

import AllnighterCore
import XCTest
@testable import AllnighteriOS

final class AllnighteriOSTests: XCTestCase {

    func testDebugConversationSnapshotMatchesMVPHomeShape() {
        #if DEBUG
        let snapshot = ConversationHomePreviewData.snapshot

        XCTAssertEqual(snapshot.pinned.map(\.title), ["Give me a picture of a cat"])
        XCTAssertEqual(snapshot.projects.map(\.name), ["Allnighter", "X", "Unassigned"])
        XCTAssertEqual(snapshot.projects.last?.isExpanded, true)
        XCTAssertEqual(snapshot.projects.last?.conversations.count, 5)
        #else
        XCTAssertTrue(ConversationListSnapshot.empty.projects.isEmpty)
        #endif
    }

    func testConversationHomeMapperGroupsRemoteThreadSummaries() {
        let now = Date(timeIntervalSince1970: 10_000)
        let mapper = ConversationHomeMapper(projectNames: ["proj_allnighter": "Allnighter"])
        let snapshot = mapper.snapshot(
            from: RemoteThreadSnapshotEnvelope(
                threads: [
                    thread(
                        id: "archived",
                        title: "Hidden",
                        projectId: nil,
                        status: .archived,
                        updatedAt: now
                    ),
                    thread(
                        id: "pinned",
                        title: "Pinned",
                        projectId: nil,
                        updatedAt: now.addingTimeInterval(-3_600),
                        pinnedAt: now
                    ),
                    thread(
                        id: "project",
                        title: "Project work",
                        projectId: "proj_allnighter",
                        updatedAt: now.addingTimeInterval(-7_200),
                        hasUnread: true
                    ),
                    thread(
                        id: "unassigned",
                        title: "New work order",
                        projectId: nil,
                        updatedAt: now.addingTimeInterval(-86_400),
                        displayState: .pending
                    )
                ],
                serverTime: now
            ),
            now: now
        )

        XCTAssertEqual(snapshot.pinned.map(\.title), ["Pinned"])
        XCTAssertEqual(snapshot.projects.map(\.name), ["Allnighter", "Unassigned"])
        XCTAssertEqual(snapshot.projects.first?.hasUnread, true)
        XCTAssertEqual(snapshot.projects.first?.conversations.first?.relativeAge, "2 hours ago")
        XCTAssertEqual(snapshot.projects.last?.conversations.first?.isPending, true)
    }

    func testConversationSnapshotFilteringDropsEmptyProjects() {
        let snapshot = ConversationListSnapshot(
            pinned: [
                ConversationSummary(id: "pinned", title: "Pinned", relativeAge: "just now", isUnread: true, isPending: false)
            ],
            projects: [
                ConversationProject(
                    id: "project",
                    name: "Project",
                    icon: .folder,
                    isExpanded: true,
                    hasUnread: false,
                    conversations: [
                        ConversationSummary(id: "read", title: "Read", relativeAge: "just now", isUnread: false, isPending: false)
                    ]
                )
            ]
        )

        let filtered = snapshot.filtering(\.isUnread)

        XCTAssertEqual(filtered.pinned.map(\.id), ["pinned"])
        XCTAssertTrue(filtered.projects.isEmpty)
    }

    private func thread(
        id: String,
        title: String,
        projectId: String?,
        status: ThreadStatus = .active,
        updatedAt: Date,
        pinnedAt: Date? = nil,
        hasUnread: Bool = false,
        displayState: ThreadDisplayState = .idle
    ) -> RemoteThreadSummary {
        RemoteThreadSummary(
            id: id,
            title: title,
            status: status,
            projectId: projectId,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            pinnedAt: pinnedAt,
            displayState: displayState,
            readState: RemoteThreadReadState(
                readCursor: nil,
                hasUnread: hasUnread,
                unreadNeedsAttention: false,
                firstUnreadTurnId: hasUnread ? "\(id)-first-unread" : nil,
                latestUnreadTurnId: hasUnread ? "\(id)-latest-unread" : nil
            ),
            turnCount: 1,
            latestTurn: nil
        )
    }

}
