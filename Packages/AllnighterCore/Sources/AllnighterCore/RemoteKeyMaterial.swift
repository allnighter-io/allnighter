import CryptoKit
import Foundation

public struct RemoteStoredKeyPair: Codable, Equatable, Sendable {
    public var signingPrivateKeyBase64: String
    public var sealingPrivateKeyBase64: String

    public init(signingPrivateKeyBase64: String, sealingPrivateKeyBase64: String) {
        self.signingPrivateKeyBase64 = signingPrivateKeyBase64
        self.sealingPrivateKeyBase64 = sealingPrivateKeyBase64
    }

    public static func generate() -> (
        material: RemoteStoredKeyPair,
        signingKey: Curve25519.Signing.PrivateKey,
        sealingKey: Curve25519.KeyAgreement.PrivateKey
    ) {
        let signingKey = Curve25519.Signing.PrivateKey()
        let sealingKey = Curve25519.KeyAgreement.PrivateKey()
        let material = RemoteStoredKeyPair(
            signingPrivateKeyBase64: signingKey.rawRepresentation.base64EncodedString(),
            sealingPrivateKeyBase64: sealingKey.rawRepresentation.base64EncodedString()
        )
        return (material, signingKey, sealingKey)
    }

    public func signingKey() throws -> Curve25519.Signing.PrivateKey {
        try RemoteCrypto.signingPrivateKey(fromBase64: signingPrivateKeyBase64)
    }

    public func sealingKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        try RemoteCrypto.sealingPrivateKey(fromBase64: sealingPrivateKeyBase64)
    }

    public var deviceSigningPubkey: String {
        get throws {
            try RemoteCrypto.signingPublicKeyBase64(signingKey().publicKey)
        }
    }

    public var deviceSealingPubkey: String {
        get throws {
            try RemoteCrypto.sealingPublicKeyBase64(sealingKey().publicKey)
        }
    }
}

public struct RemoteMacAgentCredentials: Codable, Equatable, Sendable {
    public var macAgentId: String
    public var displayName: String
    public var accountId: String
    public var accountProvider: RemoteAccountSession.Provider
    public var keys: RemoteStoredKeyPair

    public init(
        macAgentId: String,
        displayName: String,
        accountId: String,
        accountProvider: RemoteAccountSession.Provider,
        keys: RemoteStoredKeyPair
    ) {
        self.macAgentId = macAgentId
        self.displayName = displayName
        self.accountId = accountId
        self.accountProvider = accountProvider
        self.keys = keys
    }

    public var account: RemoteAccountSession {
        RemoteAccountSession(accountId: accountId, provider: accountProvider, displayName: displayName)
    }
}

public struct RemoteDeviceCredentials: Codable, Equatable, Sendable {
    public var deviceId: String
    public var displayName: String
    public var keys: RemoteStoredKeyPair

    public init(deviceId: String, displayName: String, keys: RemoteStoredKeyPair) {
        self.deviceId = deviceId
        self.displayName = displayName
        self.keys = keys
    }

    public var pairingIdentity: RemotePairingDeviceIdentity {
        get throws {
            RemotePairingDeviceIdentity(
                deviceId: deviceId,
                displayName: displayName,
                deviceSigningPubkey: try keys.deviceSigningPubkey,
                deviceSealingPubkey: try keys.deviceSealingPubkey
            )
        }
    }
}
