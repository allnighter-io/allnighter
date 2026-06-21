import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class DirectModeMediaKeyHandlerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_390_000)

    func testHandlerFetchesMediaKeyWithServerTime() async throws {
        let key = MediaKeyEnvelope(
            ref: "media_1",
            macAgentId: "mac_1",
            deviceId: "device_1",
            sealedKey: SealedBlob(
                ciphertext: Data("ciphertext".utf8),
                encapsulatedKey: Data("encapsulated".utf8),
                sealedForKeyId: "device_1",
                contentType: RemoteMediaCrypto.mediaKeyContentType
            )
        )
        let provider = RecordingDirectModeMediaKeyProvider(keys: [
            "media_1:device_1": key,
        ])
        let fixedNow = now
        let handler = DirectModeMediaKeyHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            provider: provider,
            now: { fixedNow }
        )

        let response = try await handler.mediaKey(DirectModeMediaKeyRequest(
            accountId: "acct_1",
            macAgentId: "mac_1",
            ref: "media_1",
            deviceId: "device_1",
            checkedAt: now.addingTimeInterval(-300)
        ))

        XCTAssertEqual(response, DirectModeMediaKeyResponse(key: key))
        let requests = await provider.requests()
        XCTAssertEqual(requests, [
            RecordingDirectModeMediaKeyProvider.Request(
                ref: "media_1",
                macAgentId: "mac_1",
                deviceId: "device_1",
                at: now
            ),
        ])
    }

    func testHandlerRejectsWrongAccountOrMac() async throws {
        let fixedNow = now
        let handler = DirectModeMediaKeyHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            provider: RecordingDirectModeMediaKeyProvider(keys: [:]),
            now: { fixedNow }
        )

        do {
            _ = try await handler.mediaKey(DirectModeMediaKeyRequest(
                accountId: "acct_wrong",
                macAgentId: "mac_wrong",
                ref: "media_1",
                deviceId: "device_1",
                checkedAt: now
            ))
            XCTFail("Expected request mismatch")
        } catch {
            XCTAssertEqual(
                error as? DirectModeMediaKeyError,
                .requestMismatch(
                    expectedAccountId: "acct_1",
                    actualAccountId: "acct_wrong",
                    expectedMacAgentId: "mac_1",
                    actualMacAgentId: "mac_wrong"
                )
            )
        }
    }

    func testHandlerRejectsMissingMediaKey() async throws {
        let fixedNow = now
        let handler = DirectModeMediaKeyHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            provider: RecordingDirectModeMediaKeyProvider(keys: [:]),
            now: { fixedNow }
        )

        do {
            _ = try await handler.mediaKey(DirectModeMediaKeyRequest(
                accountId: "acct_1",
                macAgentId: "mac_1",
                ref: "media_missing",
                deviceId: "device_1",
                checkedAt: now
            ))
            XCTFail("Expected missing media key")
        } catch {
            XCTAssertEqual(
                error as? DirectModeMediaKeyError,
                .mediaKeyNotFound(ref: "media_missing", deviceId: "device_1")
            )
        }
    }

    func testHandlerRejectsMismatchedProviderMediaKey() async throws {
        let mismatchedKey = MediaKeyEnvelope(
            ref: "media_other",
            macAgentId: "mac_2",
            deviceId: "device_other",
            sealedKey: SealedBlob(
                ciphertext: Data("ciphertext".utf8),
                encapsulatedKey: Data("encapsulated".utf8),
                sealedForKeyId: "device_other",
                contentType: RemoteMediaCrypto.mediaKeyContentType
            )
        )
        let provider = RecordingDirectModeMediaKeyProvider(keys: [
            "media_1:device_1": mismatchedKey,
        ])
        let fixedNow = now
        let handler = DirectModeMediaKeyHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            provider: provider,
            now: { fixedNow }
        )

        do {
            _ = try await handler.mediaKey(DirectModeMediaKeyRequest(
                accountId: "acct_1",
                macAgentId: "mac_1",
                ref: "media_1",
                deviceId: "device_1",
                checkedAt: now
            ))
            XCTFail("Expected mismatched media key")
        } catch {
            XCTAssertEqual(
                error as? DirectModeMediaKeyError,
                .mediaKeyMismatch(
                    expectedMacAgentId: "mac_1",
                    actualMacAgentId: "mac_2",
                    expectedRef: "media_1",
                    actualRef: "media_other",
                    expectedDeviceId: "device_1",
                    actualDeviceId: "device_other"
                )
            )
        }
    }
}

private actor RecordingDirectModeMediaKeyProvider: DirectModeMediaKeyProviding {
    struct Request: Equatable {
        var ref: String
        var macAgentId: String
        var deviceId: String
        var at: Date
    }

    private let keys: [String: MediaKeyEnvelope]
    private var storedRequests: [Request] = []

    init(keys: [String: MediaKeyEnvelope]) {
        self.keys = keys
    }

    func mediaKey(ref: String, macAgentId: String, deviceId: String, at: Date) async throws -> MediaKeyEnvelope? {
        storedRequests.append(Request(ref: ref, macAgentId: macAgentId, deviceId: deviceId, at: at))
        return keys["\(ref):\(deviceId)"]
    }

    func requests() -> [Request] {
        storedRequests
    }
}
