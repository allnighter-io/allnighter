import CryptoKit
import XCTest
import AllnighterCore

final class RemoteCloudClientAssemblyTests: XCTestCase {
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_751_200_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-cloud-client-assembly-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSkipsPairingWhenDeviceAlreadyTrusted() async throws {
        let device = try makeDevice(deviceId: "device_trusted")
        let identity = try device.pairingIdentity
        let pairedAt = Date()
        let trusted = TrustedDevice(
            deviceId: device.deviceId,
            displayName: device.displayName,
            deviceSigningPubkey: identity.deviceSigningPubkey,
            deviceSealingPubkey: identity.deviceSealingPubkey,
            accountId: "acct_1",
            macAgentId: "mac_1",
            pairedAt: pairedAt,
            validUntil: pairedAt.addingTimeInterval(3_600),
            capabilities: Set(RemoteCapability.allCases)
        )
        let relay = MockRemoteMacRelay(
            macs: [macRef()],
            macAccountIds: ["mac_1": "acct_1"],
            trustedDevices: [trusted]
        )
        let store = deviceStore(device)
        let phaseBox = PhaseBox()

        let connected = try await assemble(
            relay: relay,
            store: store,
            onPairingPhase: { phaseBox.append($0) }
        )

        XCTAssertEqual(connected.mac.macAgentId, "mac_1")
        XCTAssertEqual(phaseBox.values, [.checkingTrust, .approved])
        let events = await relay.eventLog
        XCTAssertFalse(events.contains("submitPairRequest"))
    }

    func testWaitsForPairingApprovalBeforeConnecting() async throws {
        let device = try makeDevice(deviceId: "device_pending")
        let deviceMaterial = device
        let pairedAt = Date()
        let relay = MockRemoteMacRelay(
            macs: [macRef()],
            macAccountIds: ["mac_1": "acct_1"],
            pairRequestIdFactory: { "pair_request_1" }
        )
        let store = deviceStore(device)
        let phaseBox = PhaseBox()

        let approveTask = Task { @Sendable in
            while true {
                let events = await relay.eventLog
                if events.contains("submitPairRequest") { break }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            var request = try await relay.pendingPairRequests(accountId: "acct_1", macAgentId: "mac_1").first!
            request.status = .approved
            request.approvedAt = pairedAt
            _ = try await relay.updatePairRequest(request)
            let identity = try deviceMaterial.pairingIdentity
            try await relay.upsertTrustedDevice(
                TrustedDevice(
                    deviceId: deviceMaterial.deviceId,
                    displayName: deviceMaterial.displayName,
                    deviceSigningPubkey: identity.deviceSigningPubkey,
                    deviceSealingPubkey: identity.deviceSealingPubkey,
                    accountId: "acct_1",
                    macAgentId: "mac_1",
                    pairedAt: pairedAt,
                    validUntil: pairedAt.addingTimeInterval(3_600),
                    capabilities: Set(RemoteCapability.allCases)
                )
            )
        }

        let connected = try await assemble(
            relay: relay,
            store: store,
            pairing: RemoteCloudPairingOptions(pollInterval: 0.01, maxPollAttempts: 20),
            onPairingPhase: { phaseBox.append($0) }
        )
        _ = await approveTask.result

        XCTAssertEqual(connected.deviceCredentials.deviceId, "device_pending")
        XCTAssertEqual(
            phaseBox.values,
            [.checkingTrust, .requestingPairing, .awaitingApproval(macDisplayName: "Studio Mac"), .approved]
        )
    }

    private func assemble(
        relay: MockRemoteMacRelay,
        store: RemoteDeviceCredentialStore,
        pairing: RemoteCloudPairingOptions = RemoteCloudPairingOptions(pollInterval: 0.01, maxPollAttempts: 3),
        onPairingPhase: (@Sendable (RemoteCloudPairingPhase) -> Void)? = nil
    ) async throws -> RemoteCloudClientAssembly.ConnectedClient {
        let environment = RemoteSupabaseEnvironment(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "publishable",
            accessToken: "token",
            accountId: "acct_1",
            accountProvider: .apple,
            macAgentId: "mac_1"
        )
        return try await RemoteCloudClientAssembly.makeConnectedClient(
            environment: environment,
            deviceDisplayName: "Mike's iPhone",
            credentialStore: store,
            pairing: pairing,
            relay: relay,
            onPairingPhase: onPairingPhase
        )
    }

    private func deviceStore(_ device: RemoteDeviceCredentials) -> RemoteDeviceCredentialStore {
        let store = RemoteDeviceCredentialStore(
            fileURL: root.appendingPathComponent("\(device.deviceId).json")
        )
        try! store.save(device)
        return store
    }

    private func makeDevice(deviceId: String) throws -> RemoteDeviceCredentials {
        let generated = RemoteStoredKeyPair.generate()
        return RemoteDeviceCredentials(
            deviceId: deviceId,
            displayName: "Mike's iPhone",
            keys: generated.material
        )
    }

    private func macRef() -> MacAgentRef {
        MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: "mac_sign",
            agentSealingPubkey: "mac_seal",
            lastSeenAt: now
        )
    }
}

private final class PhaseBox: @unchecked Sendable {
    private var phases: [RemoteCloudPairingPhase] = []

    var values: [RemoteCloudPairingPhase] {
        phases
    }

    func append(_ phase: RemoteCloudPairingPhase) {
        phases.append(phase)
    }
}
