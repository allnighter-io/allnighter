import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

final class PairCLITests: XCTestCase {
    func testListJSONUsesTrustedRemoteEnvelope() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pair-cli-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TrustedRemoteStore(fileURL: root.appendingPathComponent("trusted_remotes.json"))
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        try store.upsertPending(RemotePairRequest(
            id: "pair_1",
            accountId: "acct_1",
            macAgentId: "mac_1",
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "sign",
            deviceSealingPubkey: "seal",
            requestedAt: now,
            expiresAt: now.addingTimeInterval(300)
        ))

        let payload = try PairCLI.listJSON(store: store, now: now)

        XCTAssertEqual(payload.contractVersion, ContractRegistry.contractVersion)
        XCTAssertEqual(payload.pendingRequests.map(\.deviceId), ["device_1"])
        XCTAssertTrue(payload.trustedDevices.isEmpty)
    }

    func testBeginJSONArmsDirectModeCarrierAndPersistsNoPlaintextSecrets() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pair-cli-begin-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionStore = DirectModePairingSessionStore(
            fileURL: root.appendingPathComponent("direct_pairing_sessions.json"),
            idFactory: { "session_1" }
        )
        let now = Date(timeIntervalSince1970: 1_750_500_000)

        let output = try PairCLI.beginJSON(
            [
                "--transport", "tailscaleHTTPS",
                "--host", "studio.tail123.ts.net",
                "--port", "42123",
                "--agent-signing-pubkey", "agent_signing_pub",
                "--agent-sealing-pubkey", "agent_sealing_pub",
                "--tailnet", "tail123.ts.net",
                "--ttl-seconds", "120",
                "--link-base", "https://join.allnighter.test/pair",
            ],
            sessionStore: sessionStore,
            now: { now },
            tokenFactory: { "pair_token_secret" },
            manualCodeFactory: { "123456" }
        )

        XCTAssertEqual(output.contractVersion, ContractRegistry.contractVersion)
        XCTAssertEqual(output.sessionId, "session_1")
        XCTAssertEqual(output.manualCode, "123456")
        XCTAssertEqual(output.payload.expiresAt, now.addingTimeInterval(120))
        XCTAssertEqual(output.payload.endpoints, [
            RemotePairingEndpoint(url: "https://studio.tail123.ts.net", transportMode: .tailscaleDirect),
        ])
        XCTAssertEqual(output.serveCommand, ["tailscale", "serve", "--bg", "--https=443", "http://127.0.0.1:42123"])
        XCTAssertEqual(output.certificateProbeCommand, ["tailscale", "cert", "studio.tail123.ts.net"])

        let link = try XCTUnwrap(output.pairingLink)
        XCTAssertEqual(try payload(fromPairingLink: link), output.payload)

        let stored = String(decoding: try CoreJSON.encode(sessionStore.load()), as: UTF8.self)
        XCTAssertFalse(stored.contains("pair_token_secret"))
        XCTAssertFalse(stored.contains("123456"))
        XCTAssertEqual(try sessionStore.active(now: now).map(\.id), ["session_1"])
    }

    func testSliceQueueVerbsPrintTombstone() {
        XCTAssertTrue(PairCLI.sliceQueueRetiredMessage.contains("pm_relay"))
        XCTAssertTrue(PairCLI.sliceQueueRetiredMessage.contains("retired"))
    }

    private func payload(fromPairingLink link: String) throws -> RemotePairingPayload {
        let components = try XCTUnwrap(URLComponents(string: link))
        let encodedPayload = try XCTUnwrap(components.queryItems?.first { $0.name == "payload" }?.value)
        var base64 = encodedPayload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        return try CoreJSON.decode(RemotePairingPayload.self, from: data)
    }
}
