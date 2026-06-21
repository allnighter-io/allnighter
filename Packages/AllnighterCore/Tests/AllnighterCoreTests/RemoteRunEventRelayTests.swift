import XCTest
@testable import AllnighterCore

final class RemoteRunEventRelayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_751_500_000)

    func testRunEventsAreScopedOrderedAndBounded() async throws {
        let relay = MockRemoteMacRelay()
        try await relay.publishEvents(
            accountId: "acct_1",
            macAgentId: "mac_1",
            events: [
                envelope(id: "evt_1", seq: 1, macAgentId: "mac_1"),
                envelope(id: "evt_3", seq: 3, macAgentId: "mac_1"),
                envelope(id: "evt_2", seq: 2, macAgentId: "mac_1"),
            ]
        )
        try await relay.publishEvents(
            accountId: "acct_2",
            macAgentId: "mac_2",
            events: [envelope(id: "evt_other", seq: 4, macAgentId: "mac_2")]
        )

        let events = try await relay.runEvents(
            accountId: "acct_1",
            macAgentId: "mac_1",
            after: 1,
            limit: 1
        )
        let otherAccount = try await relay.runEvents(
            accountId: "acct_2",
            macAgentId: "mac_1",
            after: 0,
            limit: 10
        )

        XCTAssertEqual(events.map(\.event.id), ["evt_2"])
        XCTAssertTrue(otherAccount.isEmpty)
    }

    func testDuplicateEventIdsStayScopedByAccount() async throws {
        let relay = MockRemoteMacRelay()
        try await relay.publishEvents(
            accountId: "acct_1",
            macAgentId: "mac_1",
            events: [envelope(id: "evt_shared", seq: 1, macAgentId: "mac_1")]
        )
        try await relay.publishEvents(
            accountId: "acct_2",
            macAgentId: "mac_1",
            events: [envelope(id: "evt_shared", seq: 2, macAgentId: "mac_1")]
        )

        let accountOne = try await relay.runEvents(
            accountId: "acct_1",
            macAgentId: "mac_1",
            after: 0,
            limit: 10
        )
        let accountTwo = try await relay.runEvents(
            accountId: "acct_2",
            macAgentId: "mac_1",
            after: 0,
            limit: 10
        )

        XCTAssertEqual(accountOne.map(\.event.seq), [1])
        XCTAssertEqual(accountTwo.map(\.event.seq), [2])
    }

    func testPublishEventsRejectsEnvelopesForOtherMacAgent() async throws {
        let relay = MockRemoteMacRelay()
        do {
            try await relay.publishEvents(
                accountId: "acct_1",
                macAgentId: "mac_1",
                events: [
                    envelope(id: "evt_wrong_mac", seq: 1, macAgentId: "mac_2"),
                    envelope(id: "evt_right_mac", seq: 2, macAgentId: "mac_1"),
                ]
            )
            XCTFail("expected event scope mismatch")
        } catch let error as RemoteMacRelayError {
            XCTAssertEqual(
                error,
                .eventScopeMismatch(
                    expectedMacAgentId: "mac_1",
                    actualMacAgentId: "mac_2",
                    eventId: "evt_wrong_mac"
                )
            )
        }

        let publishedEvents = await relay.publishedEvents
        let selectedMacEvents = try await relay.runEvents(
            accountId: "acct_1",
            macAgentId: "mac_1",
            after: 0,
            limit: 10
        )
        let wrongMacEvents = try await relay.runEvents(
            accountId: "acct_1",
            macAgentId: "mac_2",
            after: 0,
            limit: 10
        )

        XCTAssertTrue(publishedEvents.isEmpty)
        XCTAssertTrue(selectedMacEvents.isEmpty)
        XCTAssertTrue(wrongMacEvents.isEmpty)
    }

    func testPublishEventsRejectsSealedRefsForOtherMacAgent() async throws {
        let relay = MockRemoteMacRelay()
        do {
            try await relay.publishEvents(
                accountId: "acct_1",
                macAgentId: "mac_1",
                events: [
                    envelope(
                        id: "evt_wrong_media_mac",
                        seq: 1,
                        macAgentId: "mac_1",
                        sealedRef: mediaRef(macAgentId: "mac_2")
                    ),
                ]
            )
            XCTFail("expected event scope mismatch")
        } catch let error as RemoteMacRelayError {
            XCTAssertEqual(
                error,
                .eventScopeMismatch(
                    expectedMacAgentId: "mac_1",
                    actualMacAgentId: "mac_2",
                    eventId: "evt_wrong_media_mac"
                )
            )
        }

        let publishedEvents = await relay.publishedEvents
        XCTAssertTrue(publishedEvents.isEmpty)
    }

    private func envelope(
        id: String,
        seq: Int64,
        macAgentId: String,
        sealedRef: MediaRef? = nil
    ) -> RemoteRunEventEnvelope {
        RemoteRunEventEnvelope(
            macAgentId: macAgentId,
            event: RunEvent(
                id: id,
                seq: seq,
                ts: now,
                kind: "run.started",
                payload: ["runId": .string("run_1")]
            ),
            sealedRef: sealedRef,
            signature: "sig"
        )
    }

    private func mediaRef(macAgentId: String) -> MediaRef {
        MediaRef(
            ref: "media_1",
            macAgentId: macAgentId,
            r2Key: "r2/media_1",
            contentType: "image/png",
            expiresAt: now.addingTimeInterval(3600)
        )
    }
}
