//
//  ConversationThreadStoreTests.swift
//  AllnighteriOSTests
//

import AllnighterCore
import CryptoKit
import XCTest
@testable import AllnighteriOS

final class ConversationThreadStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_751_100_000)

    @MainActor
    func testLoadDecryptsRemoteThreadDetailIntoTranscript() async throws {
        let deviceSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let detail = remoteDetail(threadId: "thread_1")
        let client = MockiOSClient(
            macs: [mac()],
            threadDetails: [
                "thread_1": [
                    "device_1": try sealedDetail(detail, deviceId: "device_1", sealingKey: deviceSealingKey),
                ],
            ],
            serverNow: now
        )
        try await client.connect(account: account(), mode: .cloudRelay)
        let store = ConversationThreadStore(
            client: client,
            macId: "mac_1",
            deviceId: "device_1",
            deviceSealingKey: deviceSealingKey
        )

        await store.load(threadId: "thread_1")

        let snapshot = try XCTUnwrap(store.state.snapshot)
        XCTAssertEqual(store.state.status, .loaded(threadId: "thread_1"))
        XCTAssertEqual(snapshot.id, "thread_1")
        XCTAssertEqual(snapshot.title, "Remote thread")
        XCTAssertEqual(snapshot.turns.map(\.role), [.user, .assistant, .system])
        XCTAssertEqual(snapshot.turns.map(\.text), ["Hello", "Working on it", nil])
        XCTAssertEqual(snapshot.turns.map(\.isPending), [false, true, false])
        XCTAssertEqual(snapshot.turns.map(\.runId), [nil, nil, nil])
        XCTAssertEqual(snapshot.turns.map(\.isFailed), [false, false, false])
        XCTAssertEqual(snapshot.turns.map(\.isTruncated), [false, true, false])
        XCTAssertEqual(snapshot.turns[1].modelId, "model_opus#0")
        XCTAssertEqual(snapshot.turns[1].agentTitle, "Agent (Opus)")
    }

    @MainActor
    func testLoadFailurePreservesLastThreadSnapshot() async throws {
        let deviceSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let initialSnapshot = ConversationThreadSnapshot(
            id: "thread_old",
            title: "Last opened",
            statusLabel: nil,
            isActive: false,
            hasUnread: false,
            readThroughTurnId: nil,
            turns: [
                ConversationThreadTurn(
                    id: "old_turn",
                    role: .assistant,
                    text: "Previous reply",
                    runId: nil,
                    modelId: "model_opus#0",
                    driverId: "claude_code",
                    agentTitle: "Agent (Opus 4.6)",
                    isPending: false,
                    isFailed: false,
                    isTruncated: false,
                    hasAttachments: false,
                    hasFileReferences: false
                ),
            ]
        )
        let blob = try RemoteCrypto.seal(
            CoreJSON.encode(remoteDetail(threadId: "thread_1")),
            to: RemoteCrypto.sealingPublicKeyBase64(deviceSealingKey.publicKey),
            sealedForKeyId: "device_2",
            contentType: RemoteThreadDetail.sealedContentType
        )
        let client = MockiOSClient(
            macs: [mac()],
            threadDetails: ["thread_1": ["device_1": blob]],
            serverNow: now
        )
        try await client.connect(account: account(), mode: .cloudRelay)
        let store = ConversationThreadStore(
            client: client,
            macId: "mac_1",
            deviceId: "device_1",
            deviceSealingKey: deviceSealingKey,
            initialSnapshot: initialSnapshot
        )

        await store.load(threadId: "thread_1")

        XCTAssertEqual(store.state.snapshot, initialSnapshot)
        XCTAssertEqual(
            store.state.status,
            .failed(
                threadId: "thread_1",
                .sealedDetailEnvelopeMismatch(
                    expectedDeviceId: "device_1",
                    actualDeviceId: "device_2",
                    expectedContentType: RemoteThreadDetail.sealedContentType,
                    actualContentType: RemoteThreadDetail.sealedContentType
                )
            )
        )
    }

    private func sealedDetail(
        _ detail: RemoteThreadDetail,
        deviceId: String,
        sealingKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> SealedBlob {
        try RemoteCrypto.seal(
            CoreJSON.encode(detail),
            to: RemoteCrypto.sealingPublicKeyBase64(sealingKey.publicKey),
            sealedForKeyId: deviceId,
            contentType: RemoteThreadDetail.sealedContentType
        )
    }

    private func remoteDetail(threadId: String) -> RemoteThreadDetail {
        RemoteThreadDetail(
            summary: summary(threadId: threadId),
            turns: [
                RemoteThreadTurnDetail(
                    id: "user_1",
                    kind: .userMessage,
                    status: .done,
                    author: .user,
                    createdAt: now.addingTimeInterval(-30),
                    completedAt: now.addingTimeInterval(-30),
                    text: "  Hello  "
                ),
                RemoteThreadTurnDetail(
                    id: "worker_1",
                    kind: .workerChat,
                    status: .running,
                    author: .worker,
                    createdAt: now.addingTimeInterval(-20),
                    text: "Working on it",
                    modelId: "model_opus#0",
                    partialOutputTruncated: true
                ),
                RemoteThreadTurnDetail(
                    id: "system_1",
                    kind: .systemEvent,
                    status: .done,
                    author: .system,
                    createdAt: now.addingTimeInterval(-10),
                    completedAt: now.addingTimeInterval(-10),
                    text: " "
                ),
            ]
        )
    }

    private func summary(threadId: String) -> RemoteThreadSummary {
        RemoteThreadSummary(
            id: threadId,
            title: "Remote thread",
            status: .active,
            projectId: nil,
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now.addingTimeInterval(-10),
            pinnedAt: nil,
            displayState: .running,
            readState: RemoteThreadReadState(
                readCursor: nil,
                hasUnread: true,
                unreadNeedsAttention: true,
                firstUnreadTurnId: "worker_1",
                latestUnreadTurnId: "worker_1"
            ),
            turnCount: 3,
            latestTurn: nil
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
}
