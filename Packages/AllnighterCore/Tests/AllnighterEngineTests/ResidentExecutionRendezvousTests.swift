import XCTest
import AllnighterCore
@testable import AllnighterEngine
#if canImport(Darwin)
import Darwin
#endif

final class ResidentExecutionRendezvousTests: XCTestCase {
    private func makeRendezvous() -> (URL, ResidentExecutionRendezvous) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resident-rendezvous-\(UUID().uuidString)", isDirectory: true)
        return (root, ResidentExecutionRendezvous(root: root))
    }

    private func prepare(_ rendezvous: ResidentExecutionRendezvous) throws {
        _ = try rendezvous.prepareCoordinator(
            coordinatorId: "coord-test",
            binaryVersion: "1.2.3",
            contractVersion: "1.0.0",
            nonce: "nonce-test"
        )
    }

    func testDefaultRootCanonicalizesMacOSTemporaryPathAliases() {
        let root = ResidentExecutionRendezvous.defaultRoot()
        let expected = FileManager.default.temporaryDirectory
            .appendingPathComponent("allnighter-resident-\(getuid())", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        XCTAssertEqual(root.path, expected.path)
    }

    private var health: ResidentExecutionOperation {
        .query(.init(kind: .health))
    }

    func testSubmitClaimAcceptAndReadReceipt() throws {
        let (root, rendezvous) = makeRendezvous()
        defer { try? FileManager.default.removeItem(at: root) }
        try prepare(rendezvous)

        let submitted = try rendezvous.submit(operation: health, idempotencyKey: "same-work", requestId: "request-a")
        XCTAssertEqual(submitted.coordinatorId, "coord-test")
        let claim = try XCTUnwrap(rendezvous.claimNext())
        XCTAssertEqual(claim.request.requestId, "request-a")
        let receipt = try rendezvous.accept(claim, canonicalId: "run-1")
        XCTAssertEqual(receipt.state, .accepted)
        XCTAssertEqual(receipt.canonicalId, "run-1")
        XCTAssertEqual(receipt.idempotencyKey, "same-work")
        let stored = try XCTUnwrap(rendezvous.receipt(requestId: "request-a"))
        XCTAssertEqual(stored.requestId, receipt.requestId)
        XCTAssertEqual(stored.canonicalId, receipt.canonicalId)
        XCTAssertEqual(stored.state, receipt.state)
        XCTAssertEqual(stored.idempotencyKey, "same-work")
    }

    func testReadinessRequiresExactBinaryGitSHA() throws {
        let (root, rendezvous) = makeRendezvous()
        defer { try? FileManager.default.removeItem(at: root) }
        try prepare(rendezvous)

        XCTAssertTrue(rendezvous.isReady(
            coordinatorId: "coord-test",
            binaryVersion: "1.2.3",
            binaryGitSha: AllnighterBuildInfo.gitSha,
            contractVersion: "1.0.0"
        ))
        XCTAssertFalse(rendezvous.isReady(
            coordinatorId: "coord-test",
            binaryVersion: "1.2.3",
            binaryGitSha: "stale-build-sha",
            contractVersion: "1.0.0"
        ))
    }

    func testDefaultSubmissionKeepsCurrentBuildIdentity() throws {
        let (root, rendezvous) = makeRendezvous()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try rendezvous.prepareCoordinator(
            coordinatorId: "coord-test",
            binaryVersion: AllnighterVersionIdentity.binaryVersion,
            binaryGitSha: "legacy-strict-sha",
            contractVersion: ContractRegistry.contractVersion
        )

        let submitted = try rendezvous.submit(operation: health, idempotencyKey: "exact-build")
        XCTAssertEqual(submitted.client.binaryGitSha, AllnighterBuildInfo.gitSha)
        XCTAssertEqual(submitted.client.origin, "cli")
    }

    func testCoordinatorEventIsAvailableToRestrictedClientByCursor() throws {
        let (root, rendezvous) = makeRendezvous()
        defer { try? FileManager.default.removeItem(at: root) }
        try prepare(rendezvous)
        try rendezvous.appendEvent(
            requestId: "request-a",
            runEvent: .init(id: "event-a", seq: 1, ts: Date(), kind: RunEventKind.workerAnswerDelta)
        )
        let events = try rendezvous.eventsAfter(requestId: "request-a")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.sequence, 1)
        XCTAssertEqual(events.first?.runEvent?.id, "event-a")
        XCTAssertTrue(try rendezvous.eventsAfter(requestId: "request-a", sequence: 1).isEmpty)
    }

    func testSameIdempotencyKeyReplaysCanonicalIdAndDifferentPayloadConflicts() throws {
        let (root, rendezvous) = makeRendezvous()
        defer { try? FileManager.default.removeItem(at: root) }
        try prepare(rendezvous)

        _ = try rendezvous.submit(operation: health, idempotencyKey: "same-work", requestId: "request-a")
        let first = try XCTUnwrap(rendezvous.claimNext())
        _ = try rendezvous.accept(first, canonicalId: "run-1")

        _ = try rendezvous.submit(operation: health, idempotencyKey: "same-work", requestId: "request-b")
        let replay = try XCTUnwrap(rendezvous.claimNext())
        let replayReceipt = try rendezvous.accept(replay, canonicalId: "ignored")
        XCTAssertEqual(replayReceipt.canonicalId, "run-1")
        XCTAssertEqual(replayReceipt.requestId, "request-b")
        XCTAssertEqual(replayReceipt.idempotencyKey, "same-work")
        let storedReplay = try XCTUnwrap(rendezvous.receipt(requestId: "request-b"))
        XCTAssertEqual(storedReplay.requestId, replayReceipt.requestId)
        XCTAssertEqual(storedReplay.canonicalId, replayReceipt.canonicalId)
        XCTAssertEqual(storedReplay.state, replayReceipt.state)

        _ = try rendezvous.submit(
            operation: .query(.init(kind: .runStatus, canonicalId: "different")),
            idempotencyKey: "same-work",
            requestId: "request-c"
        )
        let conflict = try XCTUnwrap(rendezvous.claimNext())
        XCTAssertThrowsError(try rendezvous.accept(conflict, canonicalId: "run-2")) {
            XCTAssertEqual($0 as? ResidentExecutionRendezvous.Error, .idempotencyConflict)
        }
    }

    func testClaimRecoversAfterCoordinatorCrashBeforeAcceptance() throws {
        let (root, rendezvous) = makeRendezvous()
        defer { try? FileManager.default.removeItem(at: root) }
        try prepare(rendezvous)
        _ = try rendezvous.submit(operation: health, idempotencyKey: "recover", requestId: "request-a")
        XCTAssertEqual(try rendezvous.claimNext()?.request.requestId, "request-a")

        let restarted = ResidentExecutionRendezvous(root: root)
        XCTAssertEqual(try restarted.claimNext()?.request.requestId, "request-a")
    }

    func testCoordinatorLeaseRejectsSecondOwnerAndOldShutdownCannotRemoveNewIdentity() throws {
        let (root, first) = makeRendezvous()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try first.prepareCoordinator(
            coordinatorId: "first", binaryVersion: "1.2.3", contractVersion: "1.0.0"
        )

        let second = ResidentExecutionRendezvous(root: root)
        XCTAssertThrowsError(try second.prepareCoordinator(
            coordinatorId: "second", binaryVersion: "1.2.3", contractVersion: "1.0.0"
        )) {
            XCTAssertEqual($0 as? ResidentExecutionRendezvous.Error, .coordinatorAlreadyRunning)
        }

        first.deactivateCoordinator()
        _ = try second.prepareCoordinator(
            coordinatorId: "second", binaryVersion: "1.2.3", contractVersion: "1.0.0"
        )
        first.deactivateCoordinator() // stale shutdown is now a no-op
        XCTAssertEqual(try second.currentIdentity().coordinatorId, "second")
        second.deactivateCoordinator()
    }

    func testInvalidProofIsRejectedBeforeAcceptance() throws {
        let (root, rendezvous) = makeRendezvous()
        defer { try? FileManager.default.removeItem(at: root) }
        try prepare(rendezvous)
        var request = try rendezvous.submit(operation: health, idempotencyKey: "proof", requestId: "request-a")
        request.clientProof.signature = "not-a-valid-proof"
        let file = rendezvous.inbox.appendingPathComponent("request-a.json")
        try CoreJSON.encode(request).write(to: file, options: .atomic)

        XCTAssertThrowsError(try rendezvous.claimNext()) {
            XCTAssertEqual($0 as? ResidentExecutionRendezvous.Error, .invalidProof)
        }
    }

    func testOversizedAndMalformedInboxEntriesFailClosed() throws {
        let (root, rendezvous) = makeRendezvous()
        defer { try? FileManager.default.removeItem(at: root) }
        try prepare(rendezvous)

        let oversized = rendezvous.inbox.appendingPathComponent("oversized.json")
        try Data(repeating: 0, count: ResidentExecutionRendezvous.maximumRequestBytes + 1).write(to: oversized)
        XCTAssertEqual(chmod(oversized.path, 0o600), 0)
        XCTAssertThrowsError(try rendezvous.claimNext()) {
            XCTAssertEqual($0 as? ResidentExecutionRendezvous.Error,
                           .requestTooLarge(ResidentExecutionRendezvous.maximumRequestBytes + 1))
        }

        try FileManager.default.removeItem(at: rendezvous.claimed.appendingPathComponent("oversized.json"))
        let malformed = rendezvous.inbox.appendingPathComponent("malformed.json")
        try Data("not-json".utf8).write(to: malformed)
        XCTAssertEqual(chmod(malformed.path, 0o600), 0)
        XCTAssertThrowsError(try rendezvous.claimNext()) {
            XCTAssertEqual($0 as? ResidentExecutionRendezvous.Error, .malformedRequest)
        }
    }

    func testSymlinkAndWrongModeRendezvousRootsFailClosed() throws {
        let parent = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resident-rendezvous-hostile-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let target = parent.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let symlink = parent.appendingPathComponent("symlink", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        XCTAssertThrowsError(try ResidentExecutionRendezvous(root: symlink).prepareCoordinator(
            coordinatorId: "coord", binaryVersion: "1", contractVersion: "1"
        ))

        let wrongMode = parent.appendingPathComponent("wrong-mode", isDirectory: true)
        try FileManager.default.createDirectory(at: wrongMode, withIntermediateDirectories: true)
        XCTAssertEqual(chmod(wrongMode.path, 0o755), 0)
        XCTAssertThrowsError(try ResidentExecutionRendezvous(root: wrongMode).prepareCoordinator(
            coordinatorId: "coord", binaryVersion: "1", contractVersion: "1"
        ))
    }
}
