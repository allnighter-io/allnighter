import XCTest
@testable import AllnighterCore

final class RemoteMacRelayDiscoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_751_000_000)

    func testMacDiscoveryIsScopedToSignedInAccount() async throws {
        let relay = MockRemoteMacRelay()

        _ = try await relay.registerMacAgent(RemoteMacAgentRegistration(
            accountId: "acct_1",
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: "sign_1",
            agentSealingPubkey: "seal_1"
        ))
        try await relay.heartbeat(RemoteMacAgentHeartbeat(
            accountId: "acct_1",
            macAgentId: "mac_1",
            at: now
        ))
        _ = try await relay.registerMacAgent(RemoteMacAgentRegistration(
            accountId: "acct_2",
            macAgentId: "mac_2",
            displayName: "Travel Mac",
            agentSigningPubkey: "sign_2",
            agentSealingPubkey: "seal_2"
        ))

        let accountOneMacs = try await relay.macAgents(accountId: "acct_1")
        XCTAssertEqual(accountOneMacs.map(\.macAgentId), ["mac_1"])
        XCTAssertEqual(accountOneMacs.first?.lastSeenAt, now)

        let accountTwoMacs = try await relay.macAgents(accountId: "acct_2")
        XCTAssertEqual(accountTwoMacs.map(\.macAgentId), ["mac_2"])

        let missingAccountMacs = try await relay.macAgents(accountId: "acct_missing")
        XCTAssertTrue(missingAccountMacs.isEmpty)
    }

    func testSameMacAgentIdStaysScopedByAccount() async throws {
        let relay = MockRemoteMacRelay()

        _ = try await relay.registerMacAgent(RemoteMacAgentRegistration(
            accountId: "acct_1",
            macAgentId: "mac_shared",
            displayName: "Studio Mac",
            agentSigningPubkey: "sign_1",
            agentSealingPubkey: "seal_1"
        ))
        try await relay.heartbeat(RemoteMacAgentHeartbeat(
            accountId: "acct_1",
            macAgentId: "mac_shared",
            at: now
        ))
        _ = try await relay.registerMacAgent(RemoteMacAgentRegistration(
            accountId: "acct_2",
            macAgentId: "mac_shared",
            displayName: "Travel Mac",
            agentSigningPubkey: "sign_2",
            agentSealingPubkey: "seal_2"
        ))

        let accountOneMacs = try await relay.macAgents(accountId: "acct_1")
        let accountTwoMacs = try await relay.macAgents(accountId: "acct_2")
        let accountOneMac = try XCTUnwrap(accountOneMacs.first)
        let accountTwoMac = try XCTUnwrap(accountTwoMacs.first)

        XCTAssertEqual(accountOneMac.agentSigningPubkey, "sign_1")
        XCTAssertEqual(accountOneMac.lastSeenAt, now)
        XCTAssertEqual(accountTwoMac.agentSigningPubkey, "sign_2")
        XCTAssertNil(accountTwoMac.lastSeenAt)
    }

    func testSeededMacDiscoveryToleratesDuplicateRowsForSameScope() async throws {
        let stale = MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Old Studio",
            agentSigningPubkey: "sign_old",
            agentSealingPubkey: "seal_old"
        )
        let fresh = MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio",
            agentSigningPubkey: "sign_new",
            agentSealingPubkey: "seal_new"
        )
        let relay = MockRemoteMacRelay(
            macs: [stale, fresh],
            macAccountIds: ["mac_1": "acct_1"]
        )

        let macs = try await relay.macAgents(accountId: "acct_1")

        XCTAssertEqual(macs, [fresh])
    }

    func testRegistrationRejectsUnsupportedProtocolVersion() async throws {
        let relay = MockRemoteMacRelay()

        do {
            _ = try await relay.registerMacAgent(RemoteMacAgentRegistration(
                accountId: "acct_1",
                macAgentId: "mac_1",
                displayName: "Studio Mac",
                agentSigningPubkey: "sign_1",
                agentSealingPubkey: "seal_1",
                protocolVersion: RemoteProtocol.currentMajor + 1
            ))
            XCTFail("unsupported registration protocol should be rejected")
        } catch let error as RemoteMacRelayError {
            XCTAssertEqual(
                error,
                .unsupportedProtocolVersion(
                    expected: RemoteProtocol.currentMajor,
                    actual: RemoteProtocol.currentMajor + 1
                )
            )
        }

        let macs = try await relay.macAgents(accountId: "acct_1")
        XCTAssertTrue(macs.isEmpty)
    }

    func testHeartbeatRejectsUnsupportedProtocolVersionWithoutMarkingReachable() async throws {
        let relay = MockRemoteMacRelay()

        _ = try await relay.registerMacAgent(RemoteMacAgentRegistration(
            accountId: "acct_1",
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: "sign_1",
            agentSealingPubkey: "seal_1"
        ))

        do {
            try await relay.heartbeat(RemoteMacAgentHeartbeat(
                accountId: "acct_1",
                macAgentId: "mac_1",
                at: now,
                protocolVersion: RemoteProtocol.currentMajor + 1
            ))
            XCTFail("unsupported heartbeat protocol should be rejected")
        } catch let error as RemoteMacRelayError {
            XCTAssertEqual(
                error,
                .unsupportedProtocolVersion(
                    expected: RemoteProtocol.currentMajor,
                    actual: RemoteProtocol.currentMajor + 1
                )
            )
        }

        let macs = try await relay.macAgents(accountId: "acct_1")
        let mac = try XCTUnwrap(macs.first)
        XCTAssertNil(mac.lastSeenAt)
    }
}
