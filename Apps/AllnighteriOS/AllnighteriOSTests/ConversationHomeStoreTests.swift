//
//  ConversationHomeStoreTests.swift
//  AllnighteriOSTests
//

import AllnighterCore
import XCTest
@testable import AllnighteriOS

final class ConversationHomeStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_980_000)

    @MainActor
    func testRefreshLoadsRemoteSnapshotThroughCoreReader() async throws {
        let client = MockiOSClient(
            macs: [mac()],
            threadSnapshots: [
                "mac_1": RemoteThreadSnapshotEnvelope(
                    threads: [
                        thread(
                            id: "pinned",
                            title: "Pinned",
                            projectId: nil,
                            updatedAt: now.addingTimeInterval(-60),
                            pinnedAt: now
                        ),
                        thread(
                            id: "pending",
                            title: "Pending work",
                            projectId: "proj_1",
                            updatedAt: now.addingTimeInterval(-120),
                            hasUnread: true,
                            displayState: .running
                        ),
                    ],
                    serverTime: now
                ),
            ],
            serverNow: now
        )
        try await client.connect(account: account(), mode: .cloudRelay)
        let store = ConversationHomeStore(
            client: client,
            macId: "mac_1",
            mapper: ConversationHomeMapper(projectNames: ["proj_1": "Allnighter"])
        )

        await store.refresh()

        XCTAssertEqual(store.state.status, .loaded(serverTime: now))
        XCTAssertEqual(store.state.snapshot.pinned.map(\.title), ["Pinned"])
        XCTAssertEqual(store.state.snapshot.projects.map(\.name), ["Allnighter"])
        XCTAssertEqual(store.state.snapshot.projects.first?.hasUnread, true)
        XCTAssertEqual(store.state.snapshot.projects.first?.conversations.first?.isPending, true)
    }

    @MainActor
    func testRefreshFailurePreservesLastGoodSnapshot() async throws {
        let initialSnapshot = ConversationListSnapshot(
            pinned: [
                ConversationSummary(
                    id: "old",
                    title: "Last known thread",
                    relativeAge: "1 hour ago",
                    statusLabel: nil,
                    isUnread: false,
                    isPending: false
                ),
            ],
            projects: []
        )
        let client = MockiOSClient(
            macs: [mac()],
            threadSnapshots: [
                "mac_1": RemoteThreadSnapshotEnvelope(
                    threads: [],
                    protocolVersion: 99,
                    serverTime: now
                ),
            ],
            serverNow: now
        )
        try await client.connect(account: account(), mode: .cloudRelay)
        let store = ConversationHomeStore(
            client: client,
            macId: "mac_1",
            initialSnapshot: initialSnapshot
        )

        await store.refresh()

        XCTAssertEqual(store.state.snapshot, initialSnapshot)
        XCTAssertEqual(
            store.state.status,
            .failed(.unsupportedProtocolVersion(expected: RemoteProtocol.currentMajor, actual: 99))
        )
    }

    private func account() -> RemoteAccountSession {
        RemoteAccountSession(accountId: "acct_1", provider: .apple)
    }

    private func mac() -> MacAgentRef {
        MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio",
            agentSigningPubkey: "agent-sign",
            agentSealingPubkey: "agent-seal",
            lastSeenAt: now
        )
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
                unreadNeedsAttention: hasUnread,
                firstUnreadTurnId: hasUnread ? "\(id)-first-unread" : nil,
                latestUnreadTurnId: hasUnread ? "\(id)-latest-unread" : nil
            ),
            turnCount: 1,
            latestTurn: nil
        )
    }
}
