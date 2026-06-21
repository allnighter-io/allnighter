import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class DirectModePairingSessionStoreTests: XCTestCase {
    private var root: URL!
    private var store: DirectModePairingSessionStore!
    private let now = Date(timeIntervalSince1970: 1_750_500_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("direct-mode-pairing-\(UUID().uuidString)", isDirectory: true)
        store = DirectModePairingSessionStore(
            fileURL: root.appendingPathComponent("direct_pairing_sessions.json"),
            idFactory: { "session_1" }
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testArmPersistsOnlyDigestsAndCanRebuildPayloadForCarrierOutput() throws {
        let pairingToken = "secret_pairing_token"
        let manualCode = "864209"
        let payload = pairingPayload(pairingToken: pairingToken, expiresAt: now.addingTimeInterval(120))

        let session = try store.arm(payload: payload, manualCode: manualCode, now: now)

        XCTAssertEqual(session.status, .armed)
        XCTAssertEqual(session.failedAttempts, 0)
        XCTAssertNotEqual(session.pairingTokenSHA256, pairingToken)
        XCTAssertNotEqual(session.manualCodeSHA256, manualCode)
        XCTAssertEqual(session.pairingPayload(pairingToken: pairingToken), payload)

        let encodedRegistry = String(decoding: try CoreJSON.encode(store.load()), as: UTF8.self)
        XCTAssertFalse(encodedRegistry.contains(pairingToken))
        XCTAssertFalse(encodedRegistry.contains(manualCode))
    }

    func testPairingTokenIsSingleUse() throws {
        let payload = pairingPayload(pairingToken: "token_once", expiresAt: now.addingTimeInterval(120))
        _ = try store.arm(payload: payload, now: now)

        let consumed = try store.consume(pairingToken: " token_once ", now: now.addingTimeInterval(1))

        XCTAssertEqual(consumed.status, .consumed)
        XCTAssertEqual(consumed.consumedAt, now.addingTimeInterval(1))
        XCTAssertThrowsError(try store.consume(pairingToken: "token_once", now: now.addingTimeInterval(2))) { error in
            XCTAssertEqual(error as? DirectModePairingSessionStoreError, .sessionConsumed("session_1"))
        }
    }

    func testExpiredSessionCannotBeConsumed() throws {
        let payload = pairingPayload(pairingToken: "token_expired", expiresAt: now.addingTimeInterval(1))
        _ = try store.arm(payload: payload, now: now)

        XCTAssertThrowsError(try store.consume(pairingToken: "token_expired", now: now.addingTimeInterval(2))) { error in
            XCTAssertEqual(error as? DirectModePairingSessionStoreError, .sessionExpired("session_1"))
        }
        XCTAssertEqual(store.load().sessions.first?.status, .expired)
    }

    func testBadPairingTokenAttemptsLockOutActiveSession() throws {
        let payload = pairingPayload(pairingToken: "token_good", expiresAt: now.addingTimeInterval(120))
        _ = try store.arm(payload: payload, now: now, maxFailedAttempts: 2)

        XCTAssertThrowsError(try store.consume(pairingToken: "wrong_1", now: now.addingTimeInterval(1))) { error in
            XCTAssertEqual(error as? DirectModePairingSessionStoreError, .invalidPairingToken)
        }
        XCTAssertEqual(store.load().sessions.first?.failedAttempts, 1)
        XCTAssertEqual(store.load().sessions.first?.status, .armed)

        XCTAssertThrowsError(try store.consume(pairingToken: "wrong_2", now: now.addingTimeInterval(2))) { error in
            XCTAssertEqual(error as? DirectModePairingSessionStoreError, .invalidPairingToken)
        }
        let locked = store.load().sessions.first
        XCTAssertEqual(locked?.failedAttempts, 2)
        XCTAssertEqual(locked?.status, .lockedOut)
        XCTAssertEqual(locked?.lockedOutAt, now.addingTimeInterval(2))

        XCTAssertThrowsError(try store.consume(pairingToken: "token_good", now: now.addingTimeInterval(3))) { error in
            XCTAssertEqual(error as? DirectModePairingSessionStoreError, .sessionLockedOut("session_1"))
        }
    }

    func testManualCodeNormalizesSeparatorsAndConsumesSession() throws {
        let payload = pairingPayload(pairingToken: "token_manual", expiresAt: now.addingTimeInterval(120))
        _ = try store.arm(payload: payload, manualCode: "123456", now: now)

        let consumed = try store.consume(manualCode: "123-456", now: now.addingTimeInterval(1))

        XCTAssertEqual(consumed.status, .consumed)
        XCTAssertEqual(consumed.consumedAt, now.addingTimeInterval(1))
    }

    func testNewArmedWindowExpiresPreviousActiveWindow() throws {
        let ids = IDSequence(["session_1", "session_2"])
        store = DirectModePairingSessionStore(
            fileURL: root.appendingPathComponent("direct_pairing_sessions.json"),
            idFactory: { ids.next() }
        )
        _ = try store.arm(
            payload: pairingPayload(pairingToken: "token_old", expiresAt: now.addingTimeInterval(120)),
            now: now
        )
        _ = try store.arm(
            payload: pairingPayload(pairingToken: "token_new", expiresAt: now.addingTimeInterval(180)),
            now: now.addingTimeInterval(10)
        )

        let sessions = store.load().sessions
        XCTAssertEqual(sessions.map(\.id), ["session_1", "session_2"])
        XCTAssertEqual(sessions.map(\.status), [.expired, .armed])
        XCTAssertEqual(store.active(now: now.addingTimeInterval(11)).map(\.id), ["session_2"])
    }

    private func pairingPayload(pairingToken: String, expiresAt: Date) -> RemotePairingPayload {
        RemotePairingPayload(
            endpoints: [
                RemotePairingEndpoint(url: "https://studio.tail123.ts.net", transportMode: .tailscaleDirect),
            ],
            agentSigningPubkey: "agent_signing_pub",
            agentSealingPubkey: "agent_sealing_pub",
            tailnetName: "tail123.ts.net",
            pairingToken: pairingToken,
            expiresAt: expiresAt
        )
    }
}

private final class IDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String]

    init(_ ids: [String]) {
        self.ids = ids
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard !ids.isEmpty else { return "fallback" }
        return ids.removeFirst()
    }
}
