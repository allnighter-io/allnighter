import XCTest
@testable import AllnighterCore

final class RemoteCommandRelayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_751_200_000)

    func testSubmitCommandQueuesPendingEntryAndCommandAckReturnsMacEnvelope() async throws {
        let relay = MockRemoteMacRelay()
        let entry = commandEntry(requestId: "req_1")

        try await relay.submitCommand(entry)

        let pending = try await relay.pendingCommands(accountId: "acct_1", macAgentId: "mac_1", limit: 10)
        XCTAssertEqual(pending, [entry])
        let noAck = try await relay.commandAck(accountId: "acct_1", macAgentId: "mac_1", requestId: "req_1")
        XCTAssertNil(noAck)

        let envelope = ackEnvelope(requestId: "req_1")
        try await relay.acknowledge(envelope)

        let ack = try await relay.commandAck(accountId: "acct_1", macAgentId: "mac_1", requestId: "req_1")
        XCTAssertEqual(ack, envelope)
        let drained = try await relay.pendingCommands(accountId: "acct_1", macAgentId: "mac_1", limit: 10)
        XCTAssertTrue(drained.isEmpty)
    }

    func testSubmitCommandReplacesDuplicateRequestId() async throws {
        let relay = MockRemoteMacRelay()
        let first = commandEntry(requestId: "req_1", createdAt: now)
        let replacement = commandEntry(requestId: "req_1", createdAt: now.addingTimeInterval(1))

        try await relay.submitCommand(first)
        try await relay.submitCommand(replacement)

        let pending = try await relay.pendingCommands(accountId: "acct_1", macAgentId: "mac_1", limit: 10)
        XCTAssertEqual(pending, [replacement])
    }

    private func commandEntry(
        requestId: String,
        createdAt: Date? = nil
    ) -> RemoteCommandInboxEntry {
        let assertion = DeviceAssertion(
            deviceId: "device_1",
            requestId: requestId,
            timestamp: now,
            kind: .stopAll,
            payloadSHA256: "digest",
            signature: "signature"
        )
        let command = RemoteCommand(
            requestId: requestId,
            kind: .stopAll,
            payload: .empty,
            assertion: assertion
        )
        return RemoteCommandInboxEntry(
            requestId: requestId,
            accountId: "acct_1",
            macAgentId: "mac_1",
            fromDeviceId: "device_1",
            command: command,
            createdAt: createdAt ?? now
        )
    }

    private func ackEnvelope(requestId: String) -> RemoteCommandAckEnvelope {
        RemoteCommandAckEnvelope(
            requestId: requestId,
            accountId: "acct_1",
            macAgentId: "mac_1",
            ack: CommandAck(
                requestId: requestId,
                accepted: true,
                outcome: .accepted,
                signature: "sig"
            ),
            auditEvent: RemoteAuditEvent(
                ts: now,
                deviceId: "device_1",
                commandKind: .stopAll,
                requestId: requestId,
                targetSummary: "stopAll terminated=1",
                outcome: .accepted
            ),
            createdAt: now
        )
    }
}
