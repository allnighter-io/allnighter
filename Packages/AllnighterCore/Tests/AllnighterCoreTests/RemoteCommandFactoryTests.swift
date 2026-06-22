import CryptoKit
import XCTest
@testable import AllnighterCore

final class RemoteCommandFactoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_751_400_000)

    func testFactorySignsStopAllCommand() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let fixedNow = now
        let factory = RemoteCommandFactory(
            deviceId: " device_1 ",
            signingKey: signingKey,
            now: { fixedNow }
        )

        let command = try factory.stopAll(requestId: " req_stop_all ")

        XCTAssertEqual(command.requestId, "req_stop_all")
        XCTAssertEqual(command.kind, .stopAll)
        XCTAssertEqual(command.payload, .empty)
        XCTAssertEqual(command.assertion.deviceId, "device_1")
        XCTAssertEqual(command.assertion.timestamp, now)
        XCTAssertTrue(try RemoteCrypto.verifyDeviceAssertion(
            command.assertion,
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey)
        ))
    }

    func testFactoryBuildsStopRunLightPayload() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let fixedNow = now
        let factory = RemoteCommandFactory(
            deviceId: "device_1",
            signingKey: signingKey,
            now: { fixedNow }
        )

        let command = try factory.stopRun(requestId: "req_stop", runId: " run_1 ")

        XCTAssertEqual(command.kind, .stopRun)
        XCTAssertEqual(command.payload.kind, .lightJSON)
        let payload = try CoreJSON.decode(
            RemoteStopRunPayload.self,
            from: CoreJSON.encode(try XCTUnwrap(command.payload.lightPayload))
        )
        XCTAssertEqual(payload.runId, "run_1")
        XCTAssertTrue(try RemoteCrypto.verifyDeviceAssertion(
            command.assertion,
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey)
        ))
    }

    func testFactoryBuildsMarkThreadReadLightPayload() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let fixedNow = now
        let factory = RemoteCommandFactory(
            deviceId: "device_1",
            signingKey: signingKey,
            now: { fixedNow }
        )

        let command = try factory.markThreadRead(
            requestId: "req_read",
            threadId: " thread_1 ",
            throughTurnId: " turn_1 "
        )

        XCTAssertEqual(command.kind, .markThreadRead)
        XCTAssertEqual(command.payload.kind, .lightJSON)
        let payload = try CoreJSON.decode(
            RemoteMarkThreadReadPayload.self,
            from: CoreJSON.encode(try XCTUnwrap(command.payload.lightPayload))
        )
        XCTAssertEqual(payload.threadId, "thread_1")
        XCTAssertEqual(payload.throughTurnId, "turn_1")
        XCTAssertTrue(try RemoteCrypto.verifyDeviceAssertion(
            command.assertion,
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey)
        ))
    }

    func testFactorySealsStartRunPayloadToMac() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let macSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let mac = MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: "mac_sign",
            agentSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(macSealingKey.publicKey)
        )
        let fixedNow = now
        let factory = RemoteCommandFactory(
            deviceId: "device_1",
            signingKey: signingKey,
            now: { fixedNow }
        )

        let command = try factory.startRun(
            requestId: "req_start",
            payload: RemoteStartRunPayload(
                prompt: "secret launch prompt",
                lane: "code",
                teamPresetId: "code_core",
                effort: "med",
                context: "private context"
            ),
            mac: mac
        )

        XCTAssertEqual(command.kind, .startRun)
        XCTAssertTrue(command.carriesRequiredSealedPayload)
        XCTAssertNil(command.payload.lightPayload)
        let blob = try XCTUnwrap(command.payload.sealedBlob)
        XCTAssertEqual(blob.sealedForKeyId, "mac_1")
        let opened = try RemoteCrypto.open(blob, with: macSealingKey)
        let decoded = try CoreJSON.decode(RemoteStartRunPayload.self, from: opened)
        XCTAssertEqual(decoded.prompt, "secret launch prompt")
        XCTAssertEqual(decoded.lane, "code")
        XCTAssertEqual(decoded.teamPresetId, "code_core")
        XCTAssertEqual(decoded.effort, "med")
        XCTAssertEqual(decoded.context, "private context")
        XCTAssertTrue(try RemoteCrypto.verifyDeviceAssertion(
            command.assertion,
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey)
        ))
        let encodedCommand = String(data: try CoreJSON.encode(command), encoding: .utf8)
        XCTAssertFalse(try XCTUnwrap(encodedCommand).contains("secret launch prompt"))
    }

    func testFactoryRejectsInvalidCommandFields() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let macSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let mac = MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: "mac_sign",
            agentSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(macSealingKey.publicKey)
        )
        let fixedNow = now
        let factory = RemoteCommandFactory(
            deviceId: "device_1",
            signingKey: signingKey,
            now: { fixedNow }
        )

        XCTAssertThrowsError(try factory.stopAll(requestId: " ")) { error in
            XCTAssertEqual(error as? RemoteCommandFactoryError, .emptyRequestId)
        }
        XCTAssertThrowsError(try factory.stopRun(requestId: "req_stop", runId: " ")) { error in
            XCTAssertEqual(error as? RemoteCommandFactoryError, .emptyRunId)
        }
        XCTAssertThrowsError(try factory.markThreadRead(
            requestId: "req_read",
            threadId: " ",
            throughTurnId: "turn_1"
        )) { error in
            XCTAssertEqual(error as? RemoteCommandFactoryError, .emptyThreadId)
        }
        XCTAssertThrowsError(try factory.markThreadRead(
            requestId: "req_read",
            threadId: "thread_1",
            throughTurnId: " "
        )) { error in
            XCTAssertEqual(error as? RemoteCommandFactoryError, .emptyTurnId)
        }
        XCTAssertThrowsError(try factory.startRun(
            requestId: "req_start",
            payload: RemoteStartRunPayload(prompt: " "),
            mac: mac
        )) { error in
            XCTAssertEqual(error as? RemoteCommandFactoryError, .invalidStartRunPayload)
        }

        let emptyDeviceFactory = RemoteCommandFactory(
            deviceId: " ",
            signingKey: signingKey,
            now: { fixedNow }
        )
        XCTAssertThrowsError(try emptyDeviceFactory.stopAll(requestId: "req_stop_all")) { error in
            XCTAssertEqual(error as? RemoteCommandFactoryError, .emptyDeviceId)
        }
    }
}
