import CryptoKit
import XCTest
@testable import AllnighterCore

final class RemoteThreadReaderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_920_000)

    func testFetchSnapshotValidatesProtocolVersion() async throws {
        let client = MockiOSClient(
            macs: [mac()],
            threadSnapshots: [
                "mac_1": RemoteThreadSnapshotEnvelope(
                    threads: [summary(threadId: "thread_1")],
                    serverTime: now
                ),
            ],
            serverNow: now
        )
        try await client.connect(account: account(), mode: .cloudRelay)

        let snapshot = try await RemoteThreadReader.fetchSnapshot(client: client, macId: "mac_1")

        XCTAssertEqual(snapshot.threads.map(\.id), ["thread_1"])
        XCTAssertEqual(snapshot.serverTime, now)
    }

    func testFetchSnapshotRejectsUnsupportedProtocolVersion() async throws {
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

        do {
            _ = try await RemoteThreadReader.fetchSnapshot(client: client, macId: "mac_1")
            XCTFail("unsupported thread snapshot protocol should be rejected")
        } catch let error as RemoteThreadReaderError {
            XCTAssertEqual(error, .unsupportedProtocolVersion(expected: RemoteProtocol.currentMajor, actual: 99))
        }
    }

    func testFetchDetailDecryptsLocallyAndKeepsCloudBlobSealed() async throws {
        let deviceSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let detail = remoteDetail(threadId: "thread_1", userText: "private prompt", workerText: "private reply")
        let blob = try sealedDetail(detail, deviceId: "device_1", sealingKey: deviceSealingKey)
        let client = MockiOSClient(
            macs: [mac()],
            threadDetails: ["thread_1": ["device_1": blob]],
            serverNow: now
        )
        try await client.connect(account: account(), mode: .cloudRelay)

        let bundle = try await RemoteThreadReader.fetchDetailBundle(
            client: client,
            macId: "mac_1",
            threadId: "thread_1",
            deviceId: "device_1",
            deviceSealingKey: deviceSealingKey
        )
        let opened = try await RemoteThreadReader.fetchDetail(
            client: client,
            macId: "mac_1",
            threadId: "thread_1",
            deviceId: "device_1",
            deviceSealingKey: deviceSealingKey
        )

        XCTAssertEqual(bundle.detail, detail)
        XCTAssertEqual(opened, detail)
        XCTAssertEqual(bundle.detail.turns.map(\.text), ["private prompt", "private reply"])
        let encodedBlob = String(decoding: try CoreJSON.encode(bundle.sealedDetail), as: UTF8.self)
        XCTAssertFalse(encodedBlob.contains("private prompt"))
        XCTAssertFalse(encodedBlob.contains("private reply"))
    }

    func testFetchDetailRejectsWrongDeviceEnvelopeBeforeDecrypting() async throws {
        let deviceSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let detail = remoteDetail(threadId: "thread_1")
        let blob = try RemoteCrypto.seal(
            CoreJSON.encode(detail),
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

        do {
            _ = try await RemoteThreadReader.fetchDetail(
                client: client,
                macId: "mac_1",
                threadId: "thread_1",
                deviceId: "device_1",
                deviceSealingKey: deviceSealingKey
            )
            XCTFail("wrong-device sealed detail should be rejected")
        } catch let error as RemoteThreadReaderError {
            XCTAssertEqual(error, .sealedDetailEnvelopeMismatch(
                expectedDeviceId: "device_1",
                actualDeviceId: "device_2",
                expectedContentType: RemoteThreadDetail.sealedContentType,
                actualContentType: RemoteThreadDetail.sealedContentType
            ))
        }
    }

    func testFetchDetailRejectsWrongContentTypeBeforeDecrypting() async throws {
        let deviceSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let detail = remoteDetail(threadId: "thread_1")
        let blob = try RemoteCrypto.seal(
            CoreJSON.encode(detail),
            to: RemoteCrypto.sealingPublicKeyBase64(deviceSealingKey.publicKey),
            sealedForKeyId: "device_1",
            contentType: "text/plain"
        )
        let client = MockiOSClient(
            macs: [mac()],
            threadDetails: ["thread_1": ["device_1": blob]],
            serverNow: now
        )
        try await client.connect(account: account(), mode: .cloudRelay)

        do {
            _ = try await RemoteThreadReader.fetchDetail(
                client: client,
                macId: "mac_1",
                threadId: "thread_1",
                deviceId: "device_1",
                deviceSealingKey: deviceSealingKey
            )
            XCTFail("wrong content type should be rejected")
        } catch let error as RemoteThreadReaderError {
            XCTAssertEqual(error, .sealedDetailEnvelopeMismatch(
                expectedDeviceId: "device_1",
                actualDeviceId: "device_1",
                expectedContentType: RemoteThreadDetail.sealedContentType,
                actualContentType: "text/plain"
            ))
        }
    }

    func testFetchDetailRejectsDecodedThreadMismatch() async throws {
        let deviceSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let detail = remoteDetail(threadId: "thread_2")
        let blob = try sealedDetail(detail, deviceId: "device_1", sealingKey: deviceSealingKey)
        let client = MockiOSClient(
            macs: [mac()],
            threadDetails: ["thread_1": ["device_1": blob]],
            serverNow: now
        )
        try await client.connect(account: account(), mode: .cloudRelay)

        do {
            _ = try await RemoteThreadReader.fetchDetail(
                client: client,
                macId: "mac_1",
                threadId: "thread_1",
                deviceId: "device_1",
                deviceSealingKey: deviceSealingKey
            )
            XCTFail("decoded thread mismatch should be rejected")
        } catch let error as RemoteThreadReaderError {
            XCTAssertEqual(error, .detailThreadMismatch(expectedThreadId: "thread_1", actualThreadId: "thread_2"))
        }
    }

    func testFetchDetailCannotOpenWithAnotherDeviceKey() async throws {
        let deviceSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let otherDeviceKey = Curve25519.KeyAgreement.PrivateKey()
        let detail = remoteDetail(threadId: "thread_1")
        let blob = try sealedDetail(detail, deviceId: "device_1", sealingKey: deviceSealingKey)
        let client = MockiOSClient(
            macs: [mac()],
            threadDetails: ["thread_1": ["device_1": blob]],
            serverNow: now
        )
        try await client.connect(account: account(), mode: .cloudRelay)

        do {
            _ = try await RemoteThreadReader.fetchDetail(
                client: client,
                macId: "mac_1",
                threadId: "thread_1",
                deviceId: "device_1",
                deviceSealingKey: otherDeviceKey
            )
            XCTFail("wrong private key should not open sealed thread detail")
        } catch {
            // Expected: CryptoKit rejects opening a blob sealed to another device key.
        }
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

    private func remoteDetail(
        threadId: String,
        userText: String = "user text",
        workerText: String = "worker text"
    ) -> RemoteThreadDetail {
        RemoteThreadDetail(
            summary: summary(threadId: threadId),
            turns: [
                RemoteThreadTurnDetail(
                    id: "u1",
                    kind: .userMessage,
                    status: .done,
                    author: .user,
                    createdAt: now.addingTimeInterval(-20),
                    completedAt: now.addingTimeInterval(-20),
                    text: userText
                ),
                RemoteThreadTurnDetail(
                    id: "w1",
                    kind: .workerChat,
                    status: .done,
                    author: .worker,
                    createdAt: now.addingTimeInterval(-10),
                    completedAt: now.addingTimeInterval(-10),
                    text: workerText,
                    modelId: "codex"
                ),
            ]
        )
    }

    private func summary(threadId: String) -> RemoteThreadSummary {
        RemoteThreadSummary(
            id: threadId,
            title: "Remote thread",
            status: .active,
            projectId: "project_1",
            createdAt: now.addingTimeInterval(-30),
            updatedAt: now.addingTimeInterval(-10),
            pinnedAt: nil,
            displayState: .replied,
            readState: RemoteThreadReadState(
                readCursor: nil,
                hasUnread: true,
                unreadNeedsAttention: true,
                firstUnreadTurnId: "w1",
                latestUnreadTurnId: "w1"
            ),
            turnCount: 2,
            latestTurn: RemoteThreadTurnLight(
                id: "w1",
                kind: .workerChat,
                status: .done,
                author: .worker,
                createdAt: now.addingTimeInterval(-10),
                completedAt: now.addingTimeInterval(-10),
                modelId: "codex"
            )
        )
    }

    private func mac() -> MacAgentRef {
        MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio",
            agentSigningPubkey: "sign_mac",
            agentSealingPubkey: "seal_mac",
            lastSeenAt: now
        )
    }

    private func account() -> RemoteAccountSession {
        RemoteAccountSession(accountId: "acct_1", provider: .apple)
    }
}
