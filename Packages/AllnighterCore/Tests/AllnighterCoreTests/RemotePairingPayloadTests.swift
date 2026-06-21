import XCTest
@testable import AllnighterCore

final class RemotePairingPayloadTests: XCTestCase {
    private let expiresAt = Date(timeIntervalSince1970: 1_750_500_000)

    func testDirectModePairingPayloadRoundTrips() throws {
        let payload = RemotePairingPayload(
            endpoints: [
                RemotePairingEndpoint(url: "https://studio.tail123.ts.net", transportMode: .tailscaleDirect),
                RemotePairingEndpoint(url: "http://127.0.0.1:42123", transportMode: .loopback),
            ],
            agentSigningPubkey: "agent_signing_pub",
            agentSealingPubkey: "agent_sealing_pub",
            tailnetName: "tail123.ts.net",
            pairingToken: "pair_token_1",
            expiresAt: expiresAt
        )

        let decoded = try CoreJSON.decode(RemotePairingPayload.self, from: CoreJSON.encode(payload))

        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.protocolVersion, RemoteProtocol.currentMajor)
        XCTAssertEqual(decoded.endpoints.map(\.transportMode), [.tailscaleDirect, .loopback])
    }

    func testPairingPayloadExpiryIsStrictlyPastExpiresAt() {
        let payload = RemotePairingPayload(
            endpoints: [],
            agentSigningPubkey: "agent_signing_pub",
            agentSealingPubkey: "agent_sealing_pub",
            pairingToken: "pair_token_1",
            expiresAt: expiresAt
        )

        XCTAssertFalse(payload.isExpired(at: expiresAt))
        XCTAssertTrue(payload.isExpired(at: expiresAt.addingTimeInterval(0.001)))
    }
}
