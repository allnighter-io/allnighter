//
//  WorkRequestSenderTests.swift
//  AllnighteriOSTests
//

import AllnighterCore
import CryptoKit
import XCTest
@testable import AllnighteriOS

private let workRequestSenderFixtureNow = Date(timeIntervalSince1970: 1_751_040_000)

@MainActor
final class WorkRequestSenderTests: XCTestCase {

    func testSendWorkRequestBuildsSealedStartRunWithoutTeamConfig() async throws {
        let deviceSigningKey = Curve25519.Signing.PrivateKey()
        let macSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let client = RecordingRemoteClient(acks: [
            CommandAck(
                requestId: "req_start",
                accepted: true,
                outcome: .accepted,
                serverTime: workRequestSenderFixtureNow,
                signature: "mac-signature"
            ),
        ])
        let sender = WorkRequestSender(
            client: client,
            mac: mac(sealingKey: macSealingKey),
            deviceId: "device_1",
            deviceSigningKey: deviceSigningKey,
            requestId: { " req_start " },
            now: { workRequestSenderFixtureNow }
        )

        let result = try await sender.send(WorkRequestDraft(
            prompt: "  Build the draft  ",
            threadId: " thread_1 ",
            originConversationId: " conversation_1 ",
            originMessageId: " message_1 "
        ))

        let commands = await client.sentCommands()
        let command = try XCTUnwrap(commands.first)
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(result.requestId, "req_start")
        XCTAssertEqual(result.commandResult.ack.accepted, true)
        XCTAssertEqual(result.commandResult.attemptCount, 1)
        XCTAssertEqual(command.kind, .startRun)
        XCTAssertEqual(command.requestId, "req_start")
        XCTAssertNil(command.payload.lightPayload)
        XCTAssertTrue(command.carriesRequiredSealedPayload)
        XCTAssertTrue(try RemoteCrypto.verifyDeviceAssertion(
            command.assertion,
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(deviceSigningKey.publicKey)
        ))

        let blob = try XCTUnwrap(command.payload.sealedBlob)
        let opened = try RemoteCrypto.open(blob, with: macSealingKey)
        let payload = try CoreJSON.decode(RemoteStartRunPayload.self, from: opened)
        XCTAssertEqual(payload.prompt, "Build the draft")
        XCTAssertEqual(payload.threadId, "thread_1")
        XCTAssertEqual(payload.originConversationId, "conversation_1")
        XCTAssertEqual(payload.originMessageId, "message_1")
        XCTAssertNil(payload.lane)
        XCTAssertNil(payload.teamPresetId)
        XCTAssertNil(payload.effort)
        XCTAssertNil(payload.type)
        XCTAssertNil(payload.context)

        let encodedCommand = String(decoding: try CoreJSON.encode(command), as: UTF8.self)
        XCTAssertFalse(encodedCommand.contains("Build the draft"))
    }

    func testSendWorkRequestPassesTeamAndEffortInSealedPayload() async throws {
        let deviceSigningKey = Curve25519.Signing.PrivateKey()
        let macSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let client = RecordingRemoteClient(acks: [
            CommandAck(
                requestId: "req_start",
                accepted: true,
                outcome: .accepted,
                serverTime: workRequestSenderFixtureNow,
                signature: "mac-signature"
            ),
        ])
        let sender = WorkRequestSender(
            client: client,
            mac: mac(sealingKey: macSealingKey),
            deviceId: "device_1",
            deviceSigningKey: deviceSigningKey,
            requestId: { "req_start" },
            now: { workRequestSenderFixtureNow }
        )

        _ = try await sender.send(WorkRequestDraft(
            prompt: "Ship it",
            teamPresetId: "code_core",
            lane: .code,
            effort: .high
        ))

        let commands = await client.sentCommands()
        let command = try XCTUnwrap(commands.first)
        let blob = try XCTUnwrap(command.payload.sealedBlob)
        let opened = try RemoteCrypto.open(blob, with: macSealingKey)
        let payload = try CoreJSON.decode(RemoteStartRunPayload.self, from: opened)
        XCTAssertEqual(payload.teamPresetId, "code_core")
        XCTAssertEqual(payload.lane, WorkLane.code.rawValue)
        XCTAssertEqual(payload.effort, EffortLevel.high.rawValue)
    }

    func testSendWorkRequestRejectsEmptyPromptBeforeRemoteSend() async throws {
        let client = RecordingRemoteClient(acks: [])
        let sender = WorkRequestSender(
            client: client,
            mac: mac(sealingKey: Curve25519.KeyAgreement.PrivateKey()),
            deviceId: "device_1",
            deviceSigningKey: Curve25519.Signing.PrivateKey(),
            requestId: { "req_start" },
            now: { workRequestSenderFixtureNow }
        )

        do {
            _ = try await sender.send(WorkRequestDraft(prompt: " \n\t "))
            XCTFail("empty prompt should be rejected locally")
        } catch let error as WorkRequestSenderError {
            XCTAssertEqual(error, .emptyPrompt)
        }

        let commands = await client.sentCommands()
        XCTAssertTrue(commands.isEmpty)
    }

    private func mac(sealingKey: Curve25519.KeyAgreement.PrivateKey) -> MacAgentRef {
        MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio",
            agentSigningPubkey: "agent-sign",
            agentSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(sealingKey.publicKey),
            lastSeenAt: workRequestSenderFixtureNow
        )
    }
}

actor RecordingRemoteClient: RemoteClient {
    private var commands: [RemoteCommand] = []
    private var acks: [CommandAck]

    init(acks: [CommandAck]) {
        self.acks = acks
    }

    func sentCommands() -> [RemoteCommand] {
        commands
    }

    func connect(account _: RemoteAccountSession, mode _: ConnectionMode) async throws {
    }

    func macs() async throws -> [MacAgentRef] {
        throw RecordingRemoteClientError.unimplemented
    }

    func snapshot(macId _: String, since _: Int64?) async throws -> SnapshotEnvelope {
        throw RecordingRemoteClientError.unimplemented
    }

    func threadSnapshot(macId _: String) async throws -> RemoteThreadSnapshotEnvelope {
        throw RecordingRemoteClientError.unimplemented
    }

    func sealedThreadDetail(macId _: String, threadId _: String, deviceId _: String) async throws -> SealedBlob {
        throw RecordingRemoteClientError.unimplemented
    }

    func stream(macId _: String, since _: Int64) async -> AsyncStream<RemoteRunEventEnvelope> {
        AsyncStream { $0.finish() }
    }

    func send(_ command: RemoteCommand) async throws -> CommandAck {
        commands.append(command)
        guard !acks.isEmpty else {
            throw RecordingRemoteClientError.missingAck
        }
        return acks.removeFirst()
    }

    func fetchSealed(_ ref: MediaRef) async throws -> Data {
        throw RecordingRemoteClientError.unimplemented
    }

    func fetchMediaKey(_ ref: MediaRef, deviceId _: String) async throws -> MediaKeyEnvelope {
        throw RecordingRemoteClientError.unimplemented
    }

    func diagnose() async -> ConnectionDiagnosis {
        ConnectionDiagnosis(rungs: [])
    }
}

enum RecordingRemoteClientError: Error, Equatable {
    case unimplemented
    case missingAck
}
