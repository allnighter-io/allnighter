import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class DirectModeEventsHandlerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_280_000)

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("direct-mode-events-handler-\(UUID().uuidString)", isDirectory: true)
    }

    func testHandlerReplaysBoundedSignedContentLightEvents() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteRunEventJournal(rootDirectory: root)
        let signingKey = Curve25519.Signing.PrivateKey()

        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))
        _ = try journal.append(Self.secretEvent(id: "evt_2", runId: "run_1", now: now))
        _ = try journal.append(Self.event(id: "evt_3", runId: "run_1", now: now))

        let handler = DirectModeEventsHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            journal: journal,
            signingKey: signingKey,
            maxLimit: 1
        )
        let response = try await handler.events(DirectModeEventsRequest(
            accountId: "acct_1",
            macAgentId: "mac_1",
            afterSeq: 1,
            limit: 50
        ))

        let envelope = try XCTUnwrap(response.events.first)
        XCTAssertEqual(response.events.map(\.event.id), ["evt_2"])
        XCTAssertEqual(envelope.macAgentId, "mac_1")
        XCTAssertEqual(envelope.event.seq, 2)
        XCTAssertEqual(envelope.event.payload["runId"], .string("run_1"))
        XCTAssertEqual(envelope.event.payload["workerId"], .string("worker_1"))
        XCTAssertEqual(envelope.event.payload["truncated"], .bool(false))
        XCTAssertNil(envelope.event.payload["text"])
        XCTAssertTrue(try RemoteCrypto.verifyRemoteRunEventEnvelope(
            envelope,
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey)
        ))
    }

    func testHandlerRejectsWrongAccountOrMac() async throws {
        let handler = DirectModeEventsHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            journal: RemoteRunEventJournal(rootDirectory: tempRoot()),
            signingKey: Curve25519.Signing.PrivateKey()
        )

        do {
            _ = try await handler.events(DirectModeEventsRequest(
                accountId: "acct_wrong",
                macAgentId: "mac_wrong",
                afterSeq: 0,
                limit: 10
            ))
            XCTFail("Expected request mismatch")
        } catch {
            XCTAssertEqual(
                error as? DirectModeEventsError,
                .requestMismatch(
                    expectedAccountId: "acct_1",
                    actualAccountId: "acct_wrong",
                    expectedMacAgentId: "mac_1",
                    actualMacAgentId: "mac_wrong"
                )
            )
        }
    }

    func testHandlerReturnsEmptyForZeroLimit() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteRunEventJournal(rootDirectory: root)
        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))

        let handler = DirectModeEventsHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            journal: journal,
            signingKey: Curve25519.Signing.PrivateKey()
        )
        let response = try await handler.events(DirectModeEventsRequest(
            accountId: "acct_1",
            macAgentId: "mac_1",
            afterSeq: 0,
            limit: 0
        ))

        XCTAssertEqual(response.events, [])
    }

    private static func event(id: String, runId: String, now: Date) -> RunEvent {
        RunEvent(
            id: id,
            seq: 0,
            ts: now,
            kind: RunEventKind.runStatusChanged,
            payload: [
                "runId": .string(runId),
                "to": .string(RunStatus.fanningOut.rawValue),
            ]
        )
    }

    private static func secretEvent(id: String, runId: String, now: Date) -> RunEvent {
        RunEvent(
            id: id,
            seq: 0,
            ts: now,
            kind: RunEventKind.workerAnswerDelta,
            payload: [
                "runId": .string(runId),
                "workerId": .string("worker_1"),
                "text": .string("secret answer should stay local"),
                "truncated": .bool(false),
            ]
        )
    }
}
