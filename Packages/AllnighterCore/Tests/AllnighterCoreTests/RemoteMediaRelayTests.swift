import XCTest
@testable import AllnighterCore

final class RemoteMediaRelayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_751_800_000)

    func testPublishMediaStoresScopedDataAndDeviceKeys() async throws {
        let relay = MockRemoteMacRelay()
        let ref = mediaRef(ref: "media_1", expiresAt: now.addingTimeInterval(60))
        let key = mediaKey(ref: "media_1", deviceId: "device_1")

        try await relay.publishMedia(ref: ref, data: Data("ciphertext".utf8), keys: [key])

        let data = try await relay.mediaData(ref: "media_1", macAgentId: "mac_1", at: now)
        let wrongMac = try await relay.mediaData(ref: "media_1", macAgentId: "mac_other", at: now)
        let fetchedKey = try await relay.mediaKey(ref: "media_1", macAgentId: "mac_1", deviceId: "device_1", at: now)
        let missingKey = try await relay.mediaKey(ref: "media_1", macAgentId: "mac_1", deviceId: "device_2", at: now)

        XCTAssertEqual(data, Data("ciphertext".utf8))
        XCTAssertNil(wrongMac)
        XCTAssertEqual(fetchedKey, key)
        XCTAssertNil(missingKey)
    }

    func testPublishMediaToleratesDuplicateDeviceKeys() async throws {
        let relay = MockRemoteMacRelay()
        let key = mediaKey(ref: "media_1", deviceId: "device_1")

        try await relay.publishMedia(
            ref: mediaRef(ref: "media_1", expiresAt: now.addingTimeInterval(60)),
            data: Data("ciphertext".utf8),
            keys: [key, key]
        )

        let fetchedKey = try await relay.mediaKey(ref: "media_1", macAgentId: "mac_1", deviceId: "device_1", at: now)
        XCTAssertEqual(fetchedKey, key)
    }

    func testPublishMediaRejectsMismatchedKeyScopeWithoutStoringData() async throws {
        let relay = MockRemoteMacRelay()
        let ref = mediaRef(ref: "media_1", expiresAt: now.addingTimeInterval(60))
        let wrongMacKey = mediaKey(ref: "media_1", macAgentId: "mac_2", deviceId: "device_wrong_mac")

        do {
            try await relay.publishMedia(ref: ref, data: Data("ciphertext".utf8), keys: [wrongMacKey])
            XCTFail("expected media scope mismatch")
        } catch let error as RemoteMacRelayError {
            XCTAssertEqual(
                error,
                .mediaScopeMismatch(
                    expectedMacAgentId: "mac_1",
                    actualMacAgentId: "mac_2",
                    expectedRef: "media_1",
                    actualRef: "media_1"
                )
            )
        }

        let data = try await relay.mediaData(ref: "media_1", macAgentId: "mac_1", at: now)
        let key = try await relay.mediaKey(ref: "media_1", macAgentId: "mac_1", deviceId: "device_wrong_mac", at: now)
        XCTAssertNil(data)
        XCTAssertNil(key)
    }

    func testExpiredMediaReturnsNil() async throws {
        let relay = MockRemoteMacRelay()
        try await relay.publishMedia(
            ref: mediaRef(ref: "media_expired", expiresAt: now.addingTimeInterval(-1)),
            data: Data("ciphertext".utf8),
            keys: [mediaKey(ref: "media_expired", deviceId: "device_1")]
        )

        let data = try await relay.mediaData(ref: "media_expired", macAgentId: "mac_1", at: now)
        let key = try await relay.mediaKey(ref: "media_expired", macAgentId: "mac_1", deviceId: "device_1", at: now)

        XCTAssertNil(data)
        XCTAssertNil(key)
    }

    func testUpsertMediaKeyAddsLaterDeviceWithoutReplacingBlob() async throws {
        let relay = MockRemoteMacRelay()
        let firstKey = mediaKey(ref: "media_1", deviceId: "device_1")
        let secondKey = mediaKey(ref: "media_1", deviceId: "device_2")
        try await relay.publishMedia(
            ref: mediaRef(ref: "media_1", expiresAt: now.addingTimeInterval(60)),
            data: Data("ciphertext".utf8),
            keys: [firstKey]
        )

        try await relay.upsertMediaKey(secondKey, macAgentId: "mac_1")

        let data = try await relay.mediaData(ref: "media_1", macAgentId: "mac_1", at: now)
        let fetchedFirst = try await relay.mediaKey(ref: "media_1", macAgentId: "mac_1", deviceId: "device_1", at: now)
        let fetchedSecond = try await relay.mediaKey(ref: "media_1", macAgentId: "mac_1", deviceId: "device_2", at: now)

        XCTAssertEqual(data, Data("ciphertext".utf8))
        XCTAssertEqual(fetchedFirst, firstKey)
        XCTAssertEqual(fetchedSecond, secondKey)
    }

    func testUpsertMediaKeyRejectsMismatchedMacScope() async throws {
        let relay = MockRemoteMacRelay()
        let firstKey = mediaKey(ref: "media_1", deviceId: "device_1")
        let wrongMacKey = mediaKey(ref: "media_1", macAgentId: "mac_2", deviceId: "device_wrong_mac")
        try await relay.publishMedia(
            ref: mediaRef(ref: "media_1", expiresAt: now.addingTimeInterval(60)),
            data: Data("ciphertext".utf8),
            keys: [firstKey]
        )

        do {
            try await relay.upsertMediaKey(wrongMacKey, macAgentId: "mac_1")
            XCTFail("expected media scope mismatch")
        } catch let error as RemoteMacRelayError {
            XCTAssertEqual(
                error,
                .mediaScopeMismatch(
                    expectedMacAgentId: "mac_1",
                    actualMacAgentId: "mac_2",
                    expectedRef: "media_1",
                    actualRef: "media_1"
                )
            )
        }

        let fetchedWrongMac = try await relay.mediaKey(
            ref: "media_1",
            macAgentId: "mac_1",
            deviceId: "device_wrong_mac",
            at: now
        )
        XCTAssertNil(fetchedWrongMac)
    }

    func testPublishMediaRefreshesExistingRefAndReplacesDeviceKeys() async throws {
        let relay = MockRemoteMacRelay()
        try await relay.publishMedia(
            ref: mediaRef(ref: "media_refresh", expiresAt: now.addingTimeInterval(-1)),
            data: Data("old-ciphertext".utf8),
            keys: [mediaKey(ref: "media_refresh", deviceId: "device_old")]
        )

        try await relay.publishMedia(
            ref: mediaRef(ref: "media_refresh", expiresAt: now.addingTimeInterval(60)),
            data: Data("new-ciphertext".utf8),
            keys: [mediaKey(ref: "media_refresh", deviceId: "device_new")]
        )

        let data = try await relay.mediaData(ref: "media_refresh", macAgentId: "mac_1", at: now)
        let oldKey = try await relay.mediaKey(ref: "media_refresh", macAgentId: "mac_1", deviceId: "device_old", at: now)
        let newKey = try await relay.mediaKey(ref: "media_refresh", macAgentId: "mac_1", deviceId: "device_new", at: now)

        XCTAssertEqual(data, Data("new-ciphertext".utf8))
        XCTAssertNil(oldKey)
        XCTAssertEqual(newKey, mediaKey(ref: "media_refresh", deviceId: "device_new"))
    }

    func testSameRefStaysScopedByMacAgent() async throws {
        let relay = MockRemoteMacRelay()
        let firstKey = mediaKey(ref: "media_shared", deviceId: "device_1")
        let secondKey = mediaKey(ref: "media_shared", macAgentId: "mac_2", deviceId: "device_2")
        try await relay.publishMedia(
            ref: mediaRef(ref: "media_shared", macAgentId: "mac_1", expiresAt: now.addingTimeInterval(60)),
            data: Data("mac-1-ciphertext".utf8),
            keys: [firstKey]
        )
        try await relay.publishMedia(
            ref: mediaRef(ref: "media_shared", macAgentId: "mac_2", expiresAt: now.addingTimeInterval(60)),
            data: Data("mac-2-ciphertext".utf8),
            keys: [secondKey]
        )

        let firstData = try await relay.mediaData(ref: "media_shared", macAgentId: "mac_1", at: now)
        let secondData = try await relay.mediaData(ref: "media_shared", macAgentId: "mac_2", at: now)
        let firstFetchedKey = try await relay.mediaKey(
            ref: "media_shared",
            macAgentId: "mac_1",
            deviceId: "device_1",
            at: now
        )
        let secondFetchedKey = try await relay.mediaKey(
            ref: "media_shared",
            macAgentId: "mac_2",
            deviceId: "device_2",
            at: now
        )
        let wrongMacKey = try await relay.mediaKey(
            ref: "media_shared",
            macAgentId: "mac_1",
            deviceId: "device_2",
            at: now
        )

        XCTAssertEqual(firstData, Data("mac-1-ciphertext".utf8))
        XCTAssertEqual(secondData, Data("mac-2-ciphertext".utf8))
        XCTAssertEqual(firstFetchedKey, firstKey)
        XCTAssertEqual(secondFetchedKey, secondKey)
        XCTAssertNil(wrongMacKey)
    }

    private func mediaRef(ref: String, macAgentId: String = "mac_1", expiresAt: Date) -> MediaRef {
        MediaRef(
            ref: ref,
            macAgentId: macAgentId,
            r2Key: "r2/\(ref)",
            contentType: "image/png",
            expiresAt: expiresAt
        )
    }

    private func mediaKey(ref: String, macAgentId: String = "mac_1", deviceId: String) -> MediaKeyEnvelope {
        MediaKeyEnvelope(
            ref: ref,
            macAgentId: macAgentId,
            deviceId: deviceId,
            sealedKey: SealedBlob(
                ciphertext: Data("sealed-key-\(deviceId)".utf8),
                encapsulatedKey: Data("encapsulated".utf8),
                sealedForKeyId: deviceId,
                contentType: RemoteMediaCrypto.mediaKeyContentType
            )
        )
    }
}
