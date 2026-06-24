import CryptoKit
import XCTest
import AllnighterCore

final class RemoteCredentialStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-credential-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDeviceStoreCreatesAndReloadsStableKeys() throws {
        let store = RemoteDeviceCredentialStore(
            fileURL: root.appendingPathComponent("device_credentials.json")
        )

        let first = try store.loadOrCreate(displayName: "Mike's iPhone", deviceId: "device_1")
        let second = try store.loadOrCreate(displayName: "Mike's iPhone", deviceId: "device_1")

        XCTAssertEqual(first.credentials.deviceId, "device_1")
        XCTAssertEqual(second.credentials.deviceId, "device_1")
        XCTAssertEqual(first.credentials.keys.signingPrivateKeyBase64, second.credentials.keys.signingPrivateKeyBase64)
        XCTAssertEqual(try first.credentials.pairingIdentity.deviceSigningPubkey, try second.credentials.pairingIdentity.deviceSigningPubkey)
    }

    func testMacAgentStorePersistsCredentials() throws {
        let generated = RemoteStoredKeyPair.generate()
        let store = RemoteMacAgentCredentialStore(
            fileURL: root.appendingPathComponent("mac_agent_credentials.json")
        )
        let credentials = RemoteMacAgentCredentials(
            macAgentId: "mac_1",
            displayName: "Studio",
            accountId: "acct_1",
            accountProvider: .apple,
            keys: generated.material
        )

        try store.save(credentials)
        let loaded = try XCTUnwrap(try store.load())

        XCTAssertEqual(loaded, credentials)
        XCTAssertEqual(
            try loaded.keys.signingKey().publicKey.rawRepresentation,
            generated.signingKey.publicKey.rawRepresentation
        )
    }
}
