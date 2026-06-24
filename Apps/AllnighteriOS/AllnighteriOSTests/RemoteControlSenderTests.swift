//
//  RemoteControlSenderTests.swift
//  AllnighteriOSTests
//

import AllnighterCore
import CryptoKit
import XCTest
@testable import AllnighteriOS

private let remoteControlSenderFixtureNow = Date(timeIntervalSince1970: 1_751_160_000)

@MainActor
final class RemoteControlSenderTests: XCTestCase {

    func testStopAllSendsTypedEmptyCommand() async throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let client = RecordingRemoteClient(acks: [ack(requestId: "req_stop_all")])
        let sender = RemoteControlSender(
            client: client,
            deviceId: "device_1",
            deviceSigningKey: signingKey,
            requestId: { " req_stop_all " },
            now: { remoteControlSenderFixtureNow }
        )

        let result = try await sender.stopAll()

        let commands = await client.sentCommands()
        let command = try XCTUnwrap(commands.first)
        XCTAssertEqual(result.requestId, "req_stop_all")
        XCTAssertEqual(command.requestId, "req_stop_all")
        XCTAssertEqual(command.kind, .stopAll)
        XCTAssertEqual(command.payload, .empty)
        XCTAssertTrue(try RemoteCrypto.verifyDeviceAssertion(
            command.assertion,
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey)
        ))
    }

    func testStopRunSendsRunIdLightPayload() async throws {
        let client = RecordingRemoteClient(acks: [ack(requestId: "req_stop")])
        let sender = RemoteControlSender(
            client: client,
            deviceId: "device_1",
            deviceSigningKey: Curve25519.Signing.PrivateKey(),
            requestId: { "req_stop" },
            now: { remoteControlSenderFixtureNow }
        )

        _ = try await sender.stopRun(runId: " run_1 ")

        let commands = await client.sentCommands()
        let command = try XCTUnwrap(commands.first)
        XCTAssertEqual(command.kind, .stopRun)
        XCTAssertEqual(command.payload.kind, .lightJSON)
        let payload = try CoreJSON.decode(
            RemoteStopRunPayload.self,
            from: CoreJSON.encode(try XCTUnwrap(command.payload.lightPayload))
        )
        XCTAssertEqual(payload.runId, "run_1")
    }

    func testMarkThreadReadSendsThreadReadLightPayload() async throws {
        let client = RecordingRemoteClient(acks: [ack(requestId: "req_read")])
        let sender = RemoteControlSender(
            client: client,
            deviceId: "device_1",
            deviceSigningKey: Curve25519.Signing.PrivateKey(),
            requestId: { "req_read" },
            now: { remoteControlSenderFixtureNow }
        )

        _ = try await sender.markThreadRead(threadId: " thread_1 ", throughTurnId: " turn_9 ")

        let commands = await client.sentCommands()
        let command = try XCTUnwrap(commands.first)
        XCTAssertEqual(command.kind, .markThreadRead)
        XCTAssertEqual(command.payload.kind, .lightJSON)
        let payload = try CoreJSON.decode(
            RemoteMarkThreadReadPayload.self,
            from: CoreJSON.encode(try XCTUnwrap(command.payload.lightPayload))
        )
        XCTAssertEqual(payload.threadId, "thread_1")
        XCTAssertEqual(payload.throughTurnId, "turn_9")
    }

    func testStopRunRejectsEmptyRunIdBeforeRemoteSend() async throws {
        let client = RecordingRemoteClient(acks: [])
        let sender = RemoteControlSender(
            client: client,
            deviceId: "device_1",
            deviceSigningKey: Curve25519.Signing.PrivateKey(),
            requestId: { "req_stop" },
            now: { remoteControlSenderFixtureNow }
        )

        do {
            _ = try await sender.stopRun(runId: " ")
            XCTFail("empty run id should be rejected before send")
        } catch let error as RemoteCommandFactoryError {
            XCTAssertEqual(error, .emptyRunId)
        }

        let commands = await client.sentCommands()
        XCTAssertTrue(commands.isEmpty)
    }

    private func ack(requestId: String) -> CommandAck {
        CommandAck(
            requestId: requestId,
            accepted: true,
            outcome: .accepted,
            serverTime: remoteControlSenderFixtureNow,
            signature: "mac-signature"
        )
    }
}
