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
}
