import CryptoKit
import Foundation
import XCTest
@testable import AllnighterCore

final class RemoteFoundationTests: XCTestCase {
    func testCommandSetIsClosedAndHasNoShellEscape() {
        let cases = RemoteCommandKind.allCases.map(\.rawValue)
        XCTAssertEqual(cases, [
            "startRun",
            "stopRun",
            "stopAll",
            "approveRequest",
            "rejectRequest",
            "openOnMac",
            "landPlane",
        ])
        XCTAssertFalse(cases.contains { $0.localizedCaseInsensitiveContains("shell") })
        XCTAssertFalse(cases.contains { $0.localizedCaseInsensitiveContains("mcp") })
    }

    func testStartRunRequiresSealedPayloadAndStopAllIsCapabilityUngated() {
        XCTAssertTrue(RemoteCommandKind.startRun.requiresSealedPayload)
        XCTAssertEqual(RemoteCommandKind.startRun.requiredCapability, .startRun)
        XCTAssertFalse(RemoteCommandKind.stopAll.requiresSealedPayload)
        XCTAssertNil(RemoteCommandKind.stopAll.requiredCapability)

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let trusted = TrustedDevice(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "signing",
            deviceSealingPubkey: "sealing",
            accountId: "acct_1",
            macAgentId: "mac_1",
            pairedAt: now,
            validUntil: now.addingTimeInterval(60),
            capabilities: []
        )

        XCTAssertTrue(trusted.authorizes(.stopAll, at: now))
        XCTAssertFalse(trusted.authorizes(.startRun, at: now))
    }

    func testStartRunCommandRejectsPlainLightPayloadByContract() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let payload = RemoteCommandPayload.light(["prompt": .string("do the secret thing")])
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: "device_1",
            requestId: "req_1",
            timestamp: Date(timeIntervalSince1970: 1_750_000_000),
            kind: .startRun,
            payload: payload,
            signingKey: signingKey
        )
        let command = RemoteCommand(requestId: "req_1", kind: .startRun, payload: payload, assertion: assertion)
        XCTAssertFalse(command.carriesRequiredSealedPayload)
    }

    func testCommandSigningStringIsDeterministicAndDeviceBound() {
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        let signingString = RemoteCrypto.commandSigningString(
            deviceId: "device_1",
            requestId: "req_1",
            timestamp: timestamp,
            kind: .startRun,
            payloadSHA256: "abc123"
        )

        XCTAssertEqual(
            signingString,
            "device_1|remote.command.v1|req_1|2025-06-15T15:06:40Z|1|startRun|abc123"
        )
    }

    func testPayloadDigestIsCanonicalForLightJSON() throws {
        let one = RemoteCommandPayload.light(["b": .int(2), "a": .string("one")])
        let two = RemoteCommandPayload.light(["a": .string("one"), "b": .int(2)])
        XCTAssertEqual(try RemoteCrypto.payloadDigest(one), try RemoteCrypto.payloadDigest(two))
    }

    func testDeviceAssertionSignsAndRejectsTampering() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let publicKey = RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey)
        let payload = RemoteCommandPayload.light(["runId": .string("run_1")])
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: "device_1",
            requestId: "req_1",
            timestamp: Date(timeIntervalSince1970: 1_750_000_000),
            kind: .stopRun,
            payload: payload,
            signingKey: signingKey
        )

        XCTAssertTrue(try RemoteCrypto.verifyDeviceAssertion(assertion, signingPublicKeyBase64: publicKey))

        var tampered = assertion
        tampered.kind = .stopAll
        XCTAssertFalse(try RemoteCrypto.verifyDeviceAssertion(tampered, signingPublicKeyBase64: publicKey))
    }

    func testHPKESealedBlobRoundTripsAndCarriesNoPlaintext() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let recipientPublicKey = RemoteCrypto.sealingPublicKeyBase64(recipient.publicKey)
        let plaintext = Data("start run with the sealed prompt".utf8)

        let blob = try RemoteCrypto.seal(
            plaintext,
            to: recipientPublicKey,
            sealedForKeyId: "agent_seal_1",
            contentType: "application/vnd.allnighter.remote-command+json"
        )

        XCTAssertEqual(blob.suite, .hpkeCurve25519HKDFSHA256AESGCM256)
        XCTAssertNotEqual(blob.ciphertext, plaintext)
        XCTAssertFalse(String(decoding: blob.ciphertext, as: UTF8.self).contains("sealed prompt"))

        let opened = try RemoteCrypto.open(blob, with: recipient)
        XCTAssertEqual(opened, plaintext)
    }

    func testRemoteEventEnvelopeNormalizesLegacySynthesisKinds() {
        let event = RunEvent(
            id: "evt_1",
            seq: 7,
            ts: Date(timeIntervalSince1970: 1_750_000_000),
            kind: RunEventKind.synthesisCompleted,
            payload: ["runId": .string("run_1")]
        )

        let envelope = RemoteRunEventEnvelope(event: event, signature: "sig")
        XCTAssertEqual(envelope.event.kind, RunEventKind.stageCompleted)
        XCTAssertTrue(RunEventKind.isRemotePublicKind(envelope.event.kind))
    }

    func testSnapshotEnvelopeRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let snapshot = SnapshotEnvelope(
            runs: [
                TeamRunLight(
                    id: "run_1",
                    status: .done,
                    origin: .ios,
                    promptExcerpt: "Update the tests",
                    teamDisplayName: "Default Team",
                    createdAt: now,
                    completedAt: now.addingTimeInterval(20)
                )
            ],
            lastSeq: 42,
            serverTime: now
        )

        let decoded = try CoreJSON.decode(SnapshotEnvelope.self, from: CoreJSON.encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
    }

    func testRemoteAuditEventCapsSummary() {
        let audit = RemoteAuditEvent(
            ts: Date(timeIntervalSince1970: 1_750_000_000),
            deviceId: "device_1",
            commandKind: .stopRun,
            requestId: "req_1",
            targetSummary: String(repeating: "x", count: 240),
            outcome: .accepted
        )

        XCTAssertEqual(audit.targetSummary.count, RemoteAuditEvent.targetSummaryLimit)
    }
}
