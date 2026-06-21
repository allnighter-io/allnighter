import CryptoKit
import Foundation

public enum RemoteProtocol {
    public static let currentMajor = 1
    public static let commandMethod = "remote.command.v1"
    public static let eventMethod = "remote.event.v1"
    public static let commandAckMethod = "remote.command_ack.v1"
}

public enum ConnectionMode: String, Codable, Sendable, CaseIterable {
    case cloudRelay
    case tailscaleDirect
    case loopback
}

public enum RemoteCommandKind: String, Codable, Sendable, CaseIterable {
    case startRun
    case stopRun
    case stopAll
    case approveRequest
    case rejectRequest
    case openOnMac
    case landPlane

    public var requiresSealedPayload: Bool {
        switch self {
        case .startRun:
            return true
        case .stopRun, .stopAll, .approveRequest, .rejectRequest, .openOnMac, .landPlane:
            return false
        }
    }

    public var requiredCapability: RemoteCapability? {
        switch self {
        case .stopAll:
            return nil
        case .startRun:
            return .startRun
        case .stopRun:
            return .stopRun
        case .approveRequest:
            return .approveRequest
        case .rejectRequest:
            return .rejectRequest
        case .openOnMac:
            return .openOnMac
        case .landPlane:
            return .landPlane
        }
    }

    public var isDeferredAfterV1: Bool {
        switch self {
        case .startRun, .stopRun, .stopAll:
            return false
        case .approveRequest, .rejectRequest, .openOnMac, .landPlane:
            return true
        }
    }
}

public enum RemoteCapability: String, Codable, Sendable, CaseIterable {
    case startRun
    case stopRun
    case approveRequest
    case rejectRequest
    case openOnMac
    case landPlane
}

public enum RemoteCryptoSuite: String, Codable, Sendable, CaseIterable {
    case hpkeCurve25519HKDFSHA256AESGCM256 = "HPKE-DHKEM-X25519-HKDF-SHA256/HKDF-SHA256/AES-GCM-256"
}

public struct SealedBlob: Codable, Equatable, Sendable {
    public var ciphertext: Data
    public var encapsulatedKey: Data
    public var sealedForKeyId: String
    public var suite: RemoteCryptoSuite
    public var contentType: String

    public init(
        ciphertext: Data,
        encapsulatedKey: Data,
        sealedForKeyId: String,
        suite: RemoteCryptoSuite = .hpkeCurve25519HKDFSHA256AESGCM256,
        contentType: String
    ) {
        self.ciphertext = ciphertext
        self.encapsulatedKey = encapsulatedKey
        self.sealedForKeyId = sealedForKeyId
        self.suite = suite
        self.contentType = contentType
    }
}

public enum RemoteCommandPayloadKind: String, Codable, Sendable {
    case empty
    case lightJSON
    case sealedBlob
}

public struct RemoteCommandPayload: Codable, Equatable, Sendable {
    public var kind: RemoteCommandPayloadKind
    public var lightPayload: [String: JSONValue]?
    public var sealedBlob: SealedBlob?

    public init(
        kind: RemoteCommandPayloadKind,
        lightPayload: [String: JSONValue]? = nil,
        sealedBlob: SealedBlob? = nil
    ) {
        self.kind = kind
        self.lightPayload = lightPayload
        self.sealedBlob = sealedBlob
    }

    public static var empty: RemoteCommandPayload {
        RemoteCommandPayload(kind: .empty)
    }

    public static func light(_ payload: [String: JSONValue]) -> RemoteCommandPayload {
        RemoteCommandPayload(kind: .lightJSON, lightPayload: payload)
    }

    public static func sealed(_ blob: SealedBlob) -> RemoteCommandPayload {
        RemoteCommandPayload(kind: .sealedBlob, sealedBlob: blob)
    }

    public var isSealed: Bool {
        kind == .sealedBlob && sealedBlob != nil
    }
}

public struct DeviceAssertion: Codable, Equatable, Sendable {
    public var deviceId: String
    public var method: String
    public var requestId: String
    public var timestamp: Date
    public var protocolMajor: Int
    public var kind: RemoteCommandKind
    public var payloadSHA256: String
    public var signature: String

    public init(
        deviceId: String,
        method: String = RemoteProtocol.commandMethod,
        requestId: String,
        timestamp: Date,
        protocolMajor: Int = RemoteProtocol.currentMajor,
        kind: RemoteCommandKind,
        payloadSHA256: String,
        signature: String
    ) {
        self.deviceId = deviceId
        self.method = method
        self.requestId = requestId
        self.timestamp = timestamp
        self.protocolMajor = protocolMajor
        self.kind = kind
        self.payloadSHA256 = payloadSHA256
        self.signature = signature
    }

    public var signingString: String {
        RemoteCrypto.commandSigningString(
            deviceId: deviceId,
            method: method,
            requestId: requestId,
            timestamp: timestamp,
            protocolMajor: protocolMajor,
            kind: kind,
            payloadSHA256: payloadSHA256
        )
    }
}

public struct RemoteCommand: Codable, Equatable, Sendable {
    public var requestId: String
    public var kind: RemoteCommandKind
    public var payload: RemoteCommandPayload
    public var assertion: DeviceAssertion

    public init(
        requestId: String,
        kind: RemoteCommandKind,
        payload: RemoteCommandPayload,
        assertion: DeviceAssertion
    ) {
        self.requestId = requestId
        self.kind = kind
        self.payload = payload
        self.assertion = assertion
    }

    public var carriesRequiredSealedPayload: Bool {
        !kind.requiresSealedPayload || payload.isSealed
    }
}

public enum RemoteCommandAckOutcome: String, Codable, Sendable, CaseIterable {
    case accepted
    case rejected
    case duplicate
    case queued
}

public enum RemoteCommandRejectReason: String, Codable, Sendable, CaseIterable {
    case clockSkew
    case revoked
    case expired
    case unauthorizedKind
    case replayedRequestId
    case badSignature
    case upgradeRequired
    case invalidPayload
}

public struct CommandAck: Codable, Equatable, Sendable {
    public var requestId: String
    public var accepted: Bool
    public var reason: RemoteCommandRejectReason?
    public var outcome: RemoteCommandAckOutcome
    public var serverTime: Date?
    public var signature: String

    public init(
        requestId: String,
        accepted: Bool,
        reason: RemoteCommandRejectReason? = nil,
        outcome: RemoteCommandAckOutcome,
        serverTime: Date? = nil,
        signature: String
    ) {
        self.requestId = requestId
        self.accepted = accepted
        self.reason = reason
        self.outcome = outcome
        self.serverTime = serverTime
        self.signature = signature
    }
}

public struct StopAllResult: Codable, Equatable, Sendable {
    public var terminated: Int

    public init(terminated: Int) {
        self.terminated = terminated
    }
}

public struct MacAgentRef: Codable, Equatable, Sendable, Identifiable {
    public var id: String { macAgentId }
    public var macAgentId: String
    public var displayName: String
    public var agentSigningPubkey: String
    public var agentSealingPubkey: String
    public var lastSeenAt: Date?

    public init(
        macAgentId: String,
        displayName: String,
        agentSigningPubkey: String,
        agentSealingPubkey: String,
        lastSeenAt: Date? = nil
    ) {
        self.macAgentId = macAgentId
        self.displayName = displayName
        self.agentSigningPubkey = agentSigningPubkey
        self.agentSealingPubkey = agentSealingPubkey
        self.lastSeenAt = lastSeenAt
    }
}

public struct TrustedDevice: Codable, Equatable, Sendable, Identifiable {
    public var id: String { deviceId }
    public var deviceId: String
    public var displayName: String
    public var deviceSigningPubkey: String
    public var deviceSealingPubkey: String
    public var accountId: String
    public var macAgentId: String
    public var pairedAt: Date
    public var validUntil: Date
    public var revoked: Bool
    public var revokedAt: Date?
    public var lastSeenAt: Date?
    public var capabilities: Set<RemoteCapability>

    public init(
        deviceId: String,
        displayName: String,
        deviceSigningPubkey: String,
        deviceSealingPubkey: String,
        accountId: String,
        macAgentId: String,
        pairedAt: Date,
        validUntil: Date,
        revoked: Bool = false,
        revokedAt: Date? = nil,
        lastSeenAt: Date? = nil,
        capabilities: Set<RemoteCapability>
    ) {
        self.deviceId = deviceId
        self.displayName = displayName
        self.deviceSigningPubkey = deviceSigningPubkey
        self.deviceSealingPubkey = deviceSealingPubkey
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.pairedAt = pairedAt
        self.validUntil = validUntil
        self.revoked = revoked
        self.revokedAt = revokedAt
        self.lastSeenAt = lastSeenAt
        self.capabilities = capabilities
    }

    public func authorizes(_ kind: RemoteCommandKind, at now: Date) -> Bool {
        guard !revoked, validUntil >= now else { return false }
        guard let capability = kind.requiredCapability else { return true }
        return capabilities.contains(capability)
    }
}

public struct MediaRef: Codable, Equatable, Sendable, Identifiable {
    public var id: String { ref }
    public var ref: String
    public var macAgentId: String
    public var r2Key: String
    public var contentType: String
    public var expiresAt: Date

    public init(ref: String, macAgentId: String, r2Key: String, contentType: String, expiresAt: Date) {
        self.ref = ref
        self.macAgentId = macAgentId
        self.r2Key = r2Key
        self.contentType = contentType
        self.expiresAt = expiresAt
    }
}

public struct RemoteRunEventEnvelope: Codable, Equatable, Sendable, Identifiable {
    public var id: String { event.id }
    public var macAgentId: String
    public var event: RunEvent
    public var sealedRef: MediaRef?
    public var signature: String

    public init(macAgentId: String = "", event: RunEvent, sealedRef: MediaRef? = nil, signature: String) {
        self.macAgentId = macAgentId
        var remoteEvent = event
        remoteEvent.kind = RunEventKind.remotePublicKind(for: event.kind)
        self.event = remoteEvent
        self.sealedRef = sealedRef
        self.signature = signature
    }
}

public struct TeamRunLight: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var status: TeamRunJSON.Status
    public var origin: TeamRunJSON.Origin
    public var promptExcerpt: String
    public var teamDisplayName: String?
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: String,
        status: TeamRunJSON.Status,
        origin: TeamRunJSON.Origin,
        promptExcerpt: String,
        teamDisplayName: String? = nil,
        createdAt: Date,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.status = status
        self.origin = origin
        self.promptExcerpt = promptExcerpt
        self.teamDisplayName = teamDisplayName
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public struct SnapshotEnvelope: Codable, Equatable, Sendable {
    public var runs: [TeamRunLight]
    public var lastSeq: Int64
    public var serverTime: Date
    public var protocolVersion: Int

    public init(
        runs: [TeamRunLight],
        lastSeq: Int64,
        serverTime: Date,
        protocolVersion: Int = RemoteProtocol.currentMajor
    ) {
        self.runs = runs
        self.lastSeq = lastSeq
        self.serverTime = serverTime
        self.protocolVersion = protocolVersion
    }
}

public struct ResyncRequired: Codable, Equatable, Sendable {
    public var reason: String
    public var snapshotHint: String?

    public init(reason: String, snapshotHint: String? = nil) {
        self.reason = reason
        self.snapshotHint = snapshotHint
    }
}

public struct RemoteAuditEvent: Codable, Equatable, Sendable {
    public static let targetSummaryLimit = 200

    public var ts: Date
    public var deviceId: String
    public var commandKind: RemoteCommandKind
    public var requestId: String
    public var targetSummary: String
    public var outcome: RemoteCommandAckOutcome

    public init(
        ts: Date,
        deviceId: String,
        commandKind: RemoteCommandKind,
        requestId: String,
        targetSummary: String,
        outcome: RemoteCommandAckOutcome
    ) {
        self.ts = ts
        self.deviceId = deviceId
        self.commandKind = commandKind
        self.requestId = requestId
        self.targetSummary = String(targetSummary.prefix(Self.targetSummaryLimit))
        self.outcome = outcome
    }
}

public enum ConnectionDiagnosisRung: String, Codable, Sendable, CaseIterable {
    case signedIn
    case providerAccountMatch
    case macVisible
    case macReachable
    case clockInSync
    case deviceApproved
}

public struct ConnectionDiagnosis: Codable, Equatable, Sendable {
    public struct Rung: Codable, Equatable, Sendable {
        public var rung: ConnectionDiagnosisRung
        public var ok: Bool
        public var nextAction: String?

        public init(rung: ConnectionDiagnosisRung, ok: Bool, nextAction: String? = nil) {
            self.rung = rung
            self.ok = ok
            self.nextAction = nextAction
        }
    }

    public var rungs: [Rung]

    public init(rungs: [Rung]) {
        self.rungs = rungs
    }
}

public enum RemoteCryptoError: Error, Equatable {
    case invalidBase64(String)
    case unsupportedSuite(String)
}

public enum RemoteCrypto {
    public static func signingPublicKeyBase64(_ key: Curve25519.Signing.PublicKey) -> String {
        key.rawRepresentation.base64EncodedString()
    }

    public static func sealingPublicKeyBase64(_ key: Curve25519.KeyAgreement.PublicKey) -> String {
        key.rawRepresentation.base64EncodedString()
    }

    public static func payloadDigest(_ payload: RemoteCommandPayload) throws -> String {
        try sha256Hex(CoreJSON.encode(payload))
    }

    public static func commandSigningString(
        deviceId: String,
        method: String = RemoteProtocol.commandMethod,
        requestId: String,
        timestamp: Date,
        protocolMajor: Int = RemoteProtocol.currentMajor,
        kind: RemoteCommandKind,
        payloadSHA256: String
    ) -> String {
        [
            deviceId,
            method,
            requestId,
            remoteTimestampString(from: timestamp),
            String(protocolMajor),
            kind.rawValue,
            payloadSHA256,
        ].joined(separator: "|")
    }

    public static func makeDeviceAssertion(
        deviceId: String,
        requestId: String,
        timestamp: Date,
        kind: RemoteCommandKind,
        payload: RemoteCommandPayload,
        signingKey: Curve25519.Signing.PrivateKey,
        method: String = RemoteProtocol.commandMethod,
        protocolMajor: Int = RemoteProtocol.currentMajor
    ) throws -> DeviceAssertion {
        let digest = try payloadDigest(payload)
        let signingString = commandSigningString(
            deviceId: deviceId,
            method: method,
            requestId: requestId,
            timestamp: timestamp,
            protocolMajor: protocolMajor,
            kind: kind,
            payloadSHA256: digest
        )
        let signature = try signingKey.signature(for: Data(signingString.utf8)).base64EncodedString()
        return DeviceAssertion(
            deviceId: deviceId,
            method: method,
            requestId: requestId,
            timestamp: timestamp,
            protocolMajor: protocolMajor,
            kind: kind,
            payloadSHA256: digest,
            signature: signature
        )
    }

    public static func verifyDeviceAssertion(
        _ assertion: DeviceAssertion,
        signingPublicKeyBase64: String
    ) throws -> Bool {
        let keyData = try dataFromBase64(signingPublicKeyBase64, label: "signingPublicKey")
        let signature = try dataFromBase64(assertion.signature, label: "signature")
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        return publicKey.isValidSignature(signature, for: Data(assertion.signingString.utf8))
    }

    public static func eventSigningString(
        macAgentId: String,
        method: String = RemoteProtocol.eventMethod,
        event: RunEvent,
        payloadSHA256: String
    ) -> String {
        [
            macAgentId,
            method,
            event.id,
            String(event.seq),
            remoteTimestampString(from: event.ts),
            event.kind,
            payloadSHA256,
        ].joined(separator: "|")
    }

    public static func makeRemoteRunEventEnvelope(
        macAgentId: String,
        event: RunEvent,
        sealedRef: MediaRef? = nil,
        signingKey: Curve25519.Signing.PrivateKey,
        method: String = RemoteProtocol.eventMethod
    ) throws -> RemoteRunEventEnvelope {
        var remoteEvent = event
        remoteEvent.kind = RunEventKind.remotePublicKind(for: event.kind)
        let digest = try remoteEventDigest(macAgentId: macAgentId, event: remoteEvent, sealedRef: sealedRef)
        let signingString = eventSigningString(
            macAgentId: macAgentId,
            method: method,
            event: remoteEvent,
            payloadSHA256: digest
        )
        let signature = try signingKey.signature(for: Data(signingString.utf8)).base64EncodedString()
        return RemoteRunEventEnvelope(
            macAgentId: macAgentId,
            event: remoteEvent,
            sealedRef: sealedRef,
            signature: signature
        )
    }

    public static func verifyRemoteRunEventEnvelope(
        _ envelope: RemoteRunEventEnvelope,
        signingPublicKeyBase64: String,
        method: String = RemoteProtocol.eventMethod
    ) throws -> Bool {
        let keyData = try dataFromBase64(signingPublicKeyBase64, label: "agentSigningPublicKey")
        let signature = try dataFromBase64(envelope.signature, label: "signature")
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        let digest = try remoteEventDigest(
            macAgentId: envelope.macAgentId,
            event: envelope.event,
            sealedRef: envelope.sealedRef
        )
        let signingString = eventSigningString(
            macAgentId: envelope.macAgentId,
            method: method,
            event: envelope.event,
            payloadSHA256: digest
        )
        return publicKey.isValidSignature(signature, for: Data(signingString.utf8))
    }

    public static func seal(
        _ plaintext: Data,
        to recipientPublicKeyBase64: String,
        sealedForKeyId: String,
        contentType: String,
        info: Data = Data()
    ) throws -> SealedBlob {
        let publicKeyData = try dataFromBase64(recipientPublicKeyBase64, label: "recipientPublicKey")
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKeyData)
        let suite = hpkeSuite()
        var sender = try HPKE.Sender(recipientKey: publicKey, ciphersuite: suite, info: info)
        let ciphertext = try sender.seal(plaintext)
        return SealedBlob(
            ciphertext: ciphertext,
            encapsulatedKey: sender.encapsulatedKey,
            sealedForKeyId: sealedForKeyId,
            contentType: contentType
        )
    }

    public static func open(
        _ blob: SealedBlob,
        with recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        info: Data = Data()
    ) throws -> Data {
        guard blob.suite == .hpkeCurve25519HKDFSHA256AESGCM256 else {
            throw RemoteCryptoError.unsupportedSuite(blob.suite.rawValue)
        }
        var recipient = try HPKE.Recipient(
            privateKey: recipientPrivateKey,
            ciphersuite: hpkeSuite(),
            info: info,
            encapsulatedKey: blob.encapsulatedKey
        )
        return try recipient.open(blob.ciphertext)
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func remoteTimestampString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func dataFromBase64(_ value: String, label: String) throws -> Data {
        guard let data = Data(base64Encoded: value) else {
            throw RemoteCryptoError.invalidBase64(label)
        }
        return data
    }

    private static func hpkeSuite() -> HPKE.Ciphersuite {
        HPKE.Ciphersuite(kem: .Curve25519_HKDF_SHA256, kdf: .HKDF_SHA256, aead: .AES_GCM_256)
    }

    private static func remoteEventDigest(
        macAgentId: String,
        event: RunEvent,
        sealedRef: MediaRef?
    ) throws -> String {
        try sha256Hex(CoreJSON.encode(RemoteEventSigningBody(
            macAgentId: macAgentId,
            event: event,
            sealedRef: sealedRef
        )))
    }
}

private struct RemoteEventSigningBody: Codable, Sendable {
    var macAgentId: String
    var event: RunEvent
    var sealedRef: MediaRef?
}

public extension RunEventKind {
    static func remotePublicKind(for kind: String) -> String {
        switch kind {
        case synthesisStarted:
            return stageStarted
        case synthesisCompleted:
            return stageCompleted
        case synthesisFailed:
            return stageFailed
        default:
            return kind
        }
    }

    static func isRemotePublicKind(_ kind: String) -> Bool {
        !kind.hasPrefix("synthesis.")
    }
}
