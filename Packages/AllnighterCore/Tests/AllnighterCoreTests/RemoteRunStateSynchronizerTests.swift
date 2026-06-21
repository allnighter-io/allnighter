import CryptoKit
import XCTest
@testable import AllnighterCore

final class RemoteRunStateSynchronizerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_370_000)

    func testSyncFetchesSnapshotForFreshStateAndAppliesVerifiedEvents() async throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let mac = Self.mac(signingKey: signingKey, now: now)
        let snapshot = SnapshotEnvelope(
            runs: [Self.run(id: "run_1", status: .running, now: now)],
            lastSeq: 1,
            serverTime: now
        )
        let done = try Self.envelope(
            id: "evt_done",
            seq: 2,
            runId: "run_1",
            kind: RunEventKind.runStatusChanged,
            payload: ["to": .string("done")],
            signingKey: signingKey,
            now: now
        )
        let client = MockiOSClient(
            macs: [mac],
            snapshots: ["mac_1": snapshot],
            events: ["mac_1": [done]],
            serverNow: now
        )
        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)

        let result = try await RemoteRunStateSynchronizer.sync(client: client, macId: "mac_1")

        XCTAssertTrue(result.fetchedSnapshot)
        XCTAssertEqual(result.receivedEventCount, 1)
        XCTAssertEqual(result.appliedEventCount, 1)
        XCTAssertEqual(result.state.lastSeq, 2)
        XCTAssertEqual(result.state.run(id: "run_1")?.status, .done)
        XCTAssertEqual(result.state.run(id: "run_1")?.completedAt, now)
    }

    func testSyncResumesFromCurrentStateAndDedupesAppliedEventIds() async throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let mac = Self.mac(signingKey: signingKey, now: now)
        let duplicateDone = try Self.envelope(
            id: "evt_done",
            seq: 2,
            runId: "run_1",
            kind: RunEventKind.runStatusChanged,
            payload: ["to": .string("done")],
            signingKey: signingKey,
            now: now
        )
        let failed = try Self.envelope(
            id: "evt_failed",
            seq: 3,
            runId: "run_1",
            kind: RunEventKind.runStatusChanged,
            payload: ["to": .string("failed")],
            signingKey: signingKey,
            now: now.addingTimeInterval(1)
        )
        let current = RemoteRunViewState(
            runs: [Self.run(id: "run_1", status: .running, now: now)],
            lastSeq: 1,
            appliedEventIds: ["evt_done"],
            recentEvents: [duplicateDone],
            serverTime: now
        )
        let client = MockiOSClient(
            macs: [mac],
            events: ["mac_1": [duplicateDone, failed]],
            serverNow: now
        )
        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)

        let result = try await RemoteRunStateSynchronizer.sync(client: client, macId: "mac_1", current: current)

        XCTAssertFalse(result.fetchedSnapshot)
        XCTAssertEqual(result.receivedEventCount, 2)
        XCTAssertEqual(result.appliedEventCount, 1)
        XCTAssertEqual(result.state.lastSeq, 3)
        XCTAssertEqual(result.state.appliedEventIds, ["evt_done", "evt_failed"])
        XCTAssertEqual(result.state.run(id: "run_1")?.status, .failed)
        XCTAssertEqual(result.state.run(id: "run_1")?.completedAt, now.addingTimeInterval(1))
    }

    private static func mac(
        signingKey: Curve25519.Signing.PrivateKey,
        now: Date
    ) -> MacAgentRef {
        MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio",
            agentSigningPubkey: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey),
            agentSealingPubkey: "agent-seal",
            lastSeenAt: now
        )
    }

    private static func run(id: String, status: TeamRunJSON.Status, now: Date) -> TeamRunLight {
        TeamRunLight(
            id: id,
            status: status,
            origin: .ios,
            promptExcerpt: "",
            createdAt: now
        )
    }

    private static func envelope(
        id: String,
        seq: Int64,
        runId: String,
        kind: String,
        payload: [String: JSONValue],
        signingKey: Curve25519.Signing.PrivateKey,
        now: Date
    ) throws -> RemoteRunEventEnvelope {
        var payload = payload
        payload["runId"] = .string(runId)
        return try RemoteCrypto.makeRemoteRunEventEnvelope(
            macAgentId: "mac_1",
            event: RunEvent(id: id, seq: seq, ts: now, kind: kind, payload: payload),
            signingKey: signingKey
        )
    }
}
