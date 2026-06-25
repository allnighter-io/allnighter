//
//  AllnighteriOSTests.swift
//  AllnighteriOSTests
//
//  Created by Michael Reining on 2026-06-15.
//

import AllnighterCore
import XCTest
@testable import AllnighteriOS

@MainActor
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

    func testUnauthenticatedReleaseFallbackUsesPreviewUntilSignInShips() {
        let fallback = RemoteAppModel.unauthenticatedFallback(
            isDebugBuild: false,
            isRemoteSignInEnabled: false
        )

        XCTAssertEqual(fallback, .preview)
    }

    func testUnauthenticatedReleaseFallbackCanUseOnboardingAfterSignInShips() {
        let fallback = RemoteAppModel.unauthenticatedFallback(
            isDebugBuild: false,
            isRemoteSignInEnabled: true
        )

        XCTAssertEqual(fallback, .onboarding)
    }

    func testUnauthenticatedDebugFallbackUsesPreview() {
        let fallback = RemoteAppModel.unauthenticatedFallback(
            isDebugBuild: true,
            isRemoteSignInEnabled: true
        )

        XCTAssertEqual(fallback, .preview)
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

    func testConversationHomeMapperSurfacesNeedsAttention() {
        let now = Date(timeIntervalSince1970: 10_000)
        let mapper = ConversationHomeMapper()
        let snapshot = mapper.snapshot(
            from: RemoteThreadSnapshotEnvelope(
                threads: [
                    thread(
                        id: "attention",
                        title: "Pick a design",
                        projectId: nil,
                        updatedAt: now,
                        hasUnread: true,
                        unreadNeedsAttention: true,
                        displayState: .replied
                    ),
                ],
                serverTime: now
            ),
            now: now
        )

        let conversation = snapshot.projects.first?.conversations.first
        XCTAssertEqual(conversation?.statusLabel, "Needs you")
        XCTAssertTrue(conversation?.needsAttention == true)
    }

    func testConversationSnapshotFilteringDropsEmptyProjects() {
        let snapshot = ConversationListSnapshot(
            pinned: [
                ConversationSummary(id: "pinned", title: "Pinned", relativeAge: "just now", statusLabel: nil, isUnread: true, isPending: false, needsAttention: false)
            ],
            projects: [
                ConversationProject(
                    id: "project",
                    name: "Project",
                    icon: .folder,
                    isExpanded: true,
                    hasUnread: false,
                    conversations: [
                        ConversationSummary(id: "read", title: "Read", relativeAge: "just now", statusLabel: nil, isUnread: false, isPending: false, needsAttention: false)
                    ]
                )
            ]
        )

        let filtered = snapshot.filtering(\.isUnread)

        XCTAssertEqual(filtered.pinned.map(\.id), ["pinned"])
        XCTAssertTrue(filtered.projects.isEmpty)
    }

    func testThreadMapperUsesLatestUnreadTurnForReadCursor() {
        let mapper = ConversationThreadMapper()
        let detail = RemoteThreadDetail(
            summary: RemoteThreadSummary(
                id: "thread_1",
                title: "Unread thread",
                status: .active,
                projectId: nil,
                createdAt: Date(timeIntervalSince1970: 1_751_100_000),
                updatedAt: Date(timeIntervalSince1970: 1_751_100_100),
                pinnedAt: nil,
                displayState: .replied,
                readState: RemoteThreadReadState(
                    readCursor: nil,
                    hasUnread: true,
                    unreadNeedsAttention: true,
                    firstUnreadTurnId: "turn_user",
                    latestUnreadTurnId: "turn_worker"
                ),
                turnCount: 2,
                latestTurn: nil
            ),
            turns: [
                RemoteThreadTurnDetail(
                    id: "turn_user",
                    kind: .userMessage,
                    status: .done,
                    author: .user,
                    createdAt: Date(timeIntervalSince1970: 1_751_100_000),
                    text: "Hello"
                ),
                RemoteThreadTurnDetail(
                    id: "turn_worker",
                    kind: .workerChat,
                    status: .done,
                    author: .worker,
                    createdAt: Date(timeIntervalSince1970: 1_751_100_100),
                    text: "Reply"
                ),
            ]
        )

        let snapshot = mapper.snapshot(from: detail)

        XCTAssertTrue(snapshot.hasUnread)
        XCTAssertEqual(snapshot.readThroughTurnId, "turn_worker")
    }

    private func thread(
        id: String,
        title: String,
        projectId: String?,
        status: ThreadStatus = .active,
        updatedAt: Date,
        pinnedAt: Date? = nil,
        hasUnread: Bool = false,
        unreadNeedsAttention: Bool = false,
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
                unreadNeedsAttention: unreadNeedsAttention,
                firstUnreadTurnId: hasUnread ? "\(id)-first-unread" : nil,
                latestUnreadTurnId: hasUnread ? "\(id)-latest-unread" : nil
            ),
            turnCount: 1,
            latestTurn: nil
        )
    }

}
