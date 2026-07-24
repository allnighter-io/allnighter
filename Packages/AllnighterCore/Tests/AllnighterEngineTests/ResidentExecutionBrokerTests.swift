import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class ResidentExecutionBrokerTests: XCTestCase {
    func testBrokerReceiptsDetachedTeamBeforeRunnerHandshake() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resident-broker-admission-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let rendezvous = ResidentExecutionRendezvous(root: root.appendingPathComponent("rendezvous", isDirectory: true))
        _ = try rendezvous.prepareCoordinator(
            coordinatorId: "coord", binaryVersion: AllnighterVersionIdentity.binaryVersion, contractVersion: ContractRegistry.contractVersion
        )
        let model = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let team = TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan, defaultEffort: .low,
            isDefaultForLane: true,
            workerSpecs: [.init(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: .init(skillId: "plan_writer_build"), builtIn: true
        )
        let runStore = RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true))
        let service = AsyncTeamService(
            models: [model], registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            teams: [team], runStore: runStore,
            governor: TeamGovernor(directory: root.appendingPathComponent("gov"), capacity: 1),
            idempotency: IdempotencyStore(fileURL: root.appendingPathComponent("idempotency.json")),
            environment: [:], idFactory: { "run-pre-spawn" }
        )
        let cancelled = BrokerCancellation()
        let broker = ResidentExecutionBroker(
            rendezvous: rendezvous,
            dependencies: .init(
                asyncTeam: service, models: [model], readyModels: { [model] }, executablePath: { "/usr/bin/false" }
            )
        )
        let task = Task { await broker.run(isCancelled: { cancelled.value }) }
        defer { cancelled.value = true; task.cancel() }

        let submitted = try rendezvous.submit(
            operation: .teamRun(.init(question: "hello", lane: .code, teamPresetId: "code_test", effort: .low, idempotencyKey: "same-key")),
            idempotencyKey: "same-key", requestId: "detached-admission"
        )
        let maybeReceipt = try await rendezvous.waitForReceipt(requestId: submitted.requestId, timeout: 2)
        let receipt = try XCTUnwrap(maybeReceipt)
        XCTAssertEqual(receipt.state, .accepted)
        XCTAssertEqual(receipt.idempotencyKey, "same-key")
        guard case let .teamStart(response) = receipt.result else { return XCTFail("expected Team acceptance") }
        let directory = try runStore.runDirectory(forRunId: response.runId)
        XCTAssertNotNil(ProcessOwnership.readStageLease(in: directory), "receipt must precede runner ownership handshake")
    }

    func testBrokerAcceptsHealthAndRejectsUnrunnableTeamWithoutForegroundFallback() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resident-broker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let rendezvous = ResidentExecutionRendezvous(root: root.appendingPathComponent("rendezvous", isDirectory: true))
        _ = try rendezvous.prepareCoordinator(
            coordinatorId: "coord", binaryVersion: AllnighterVersionIdentity.binaryVersion, contractVersion: ContractRegistry.contractVersion
        )
        let service = AsyncTeamService(
            models: [], registry: DefaultConfig.registry,
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true))
        )
        let cancelled = BrokerCancellation()
        let broker = ResidentExecutionBroker(
            rendezvous: rendezvous,
            dependencies: .init(
                asyncTeam: service,
                readyModels: { [] },
                executablePath: { "/usr/bin/false" },
                coordinatorHealth: {
                    CoordinatorHealth(
                        state: .available,
                        coordinatorId: "coord",
                        pid: 42,
                        contractVersion: ContractRegistry.contractVersion,
                        binaryVersion: AllnighterVersionIdentity.binaryVersion,
                        journal: .init(incrementalDurable: true, orphanRecovery: true, runsDirWritable: true),
                        loopback: .init(listening: true),
                        broker: .init(ready: true)
                    )
                }
            )
        )
        let task = Task { await broker.run(isCancelled: { cancelled.value }) }
        defer {
            cancelled.value = true
            task.cancel()
        }

        let health = try rendezvous.submit(
            operation: .query(.init(kind: .health)), idempotencyKey: "health", requestId: "health-request"
        )
        let healthMaybeReceipt = try await rendezvous.waitForReceipt(requestId: health.requestId)
        let healthReceipt = try XCTUnwrap(healthMaybeReceipt)
        XCTAssertEqual(healthReceipt.state, .accepted)
        XCTAssertEqual(healthReceipt.canonicalId, "coord")
        guard case let .coordinatorHealth(healthSnapshot) = healthReceipt.result else {
            return XCTFail("expected coordinator health over rendezvous")
        }
        XCTAssertEqual(healthSnapshot.state, .available)
        XCTAssertTrue(healthSnapshot.broker.ready)

        // A source probe is coordinator-scoped. Letting a restricted caller
        // attach its repo path reintroduces the Documents-TCC prompt the broker
        // exists to prevent, even though no worker has been dispatched.
        let workspaceProbe = try rendezvous.submit(
            operation: .sourceProbe(.init(
                sourceId: "codex",
                full: false,
                workingDirectory: "/Users/example/Documents/repo"
            )),
            idempotencyKey: "workspace-probe",
            requestId: "workspace-probe-request"
        )
        let workspaceProbeMaybeReceipt = try await rendezvous.waitForReceipt(requestId: workspaceProbe.requestId)
        let workspaceProbeReceipt = try XCTUnwrap(workspaceProbeMaybeReceipt)
        XCTAssertEqual(workspaceProbeReceipt.state, .rejected)
        XCTAssertEqual(workspaceProbeReceipt.rejection?.code, "RESIDENT_REQUEST_REJECTED")

        let mismatched = try rendezvous.submit(
            operation: .query(.init(kind: .health)),
            idempotencyKey: "mismatched-build",
            requestId: "mismatched-build-request",
            client: .init(
                binaryVersion: AllnighterVersionIdentity.binaryVersion,
                binaryGitSha: "stale-build-sha",
                contractVersion: "incompatible-contract",
                pid: 1
            )
        )
        let mismatchedMaybeReceipt = try await rendezvous.waitForReceipt(requestId: mismatched.requestId)
        let mismatchedReceipt = try XCTUnwrap(mismatchedMaybeReceipt)
        XCTAssertEqual(mismatchedReceipt.state, .rejected)
        XCTAssertEqual(mismatchedReceipt.rejection?.code, "COORDINATOR_VERSION_MISMATCH")

        let ownership = try rendezvous.submit(
            operation: .query(.init(kind: .processSnapshot, scopeRoot: root.path)),
            idempotencyKey: "ownership", requestId: "ownership-request"
        )
        let ownershipMaybeReceipt = try await rendezvous.waitForReceipt(requestId: ownership.requestId)
        let ownershipReceipt = try XCTUnwrap(ownershipMaybeReceipt)
        guard case let .ownership(snapshot) = ownershipReceipt.result else {
            return XCTFail("expected resident ownership snapshot")
        }
        XCTAssertTrue(snapshot.processes.isEmpty)

        let missingStatus = try rendezvous.submit(
            operation: .query(.init(kind: .runStatus, canonicalId: "missing")),
            idempotencyKey: "missing-status", requestId: "missing-status-request"
        )
        let missingStatusMaybeReceipt = try await rendezvous.waitForReceipt(requestId: missingStatus.requestId)
        let missingStatusReceipt = try XCTUnwrap(missingStatusMaybeReceipt)
        XCTAssertEqual(missingStatusReceipt.state, .rejected)
        XCTAssertEqual(missingStatusReceipt.rejection?.code, "RUN_NOT_FOUND")

        // The remaining public Team lifecycle verbs use this same resident
        // authority. A reconcile may legitimately find nothing, while cancel
        // reports a normal typed not-found receipt instead of consulting a
        // client-local RunStore.
        let reconcile = try rendezvous.submit(
            operation: .teamReconcile(.init(scopeRoot: root.path)),
            idempotencyKey: "reconcile", requestId: "reconcile-request"
        )
        let reconcileMaybeReceipt = try await rendezvous.waitForReceipt(requestId: reconcile.requestId)
        let reconcileReceipt = try XCTUnwrap(reconcileMaybeReceipt)
        XCTAssertEqual(reconcileReceipt.state, .accepted)
        guard case let .teamReconcile(reconcileResponse) = reconcileReceipt.result else {
            return XCTFail("expected resident Team reconcile response")
        }
        XCTAssertEqual(reconcileResponse.reapedCount, 0)

        let cancel = try rendezvous.submit(
            operation: .teamCancel(.init(runId: "missing")),
            idempotencyKey: "cancel", requestId: "cancel-request"
        )
        let cancelMaybeReceipt = try await rendezvous.waitForReceipt(requestId: cancel.requestId)
        let cancelReceipt = try XCTUnwrap(cancelMaybeReceipt)
        XCTAssertEqual(cancelReceipt.state, .rejected)
        XCTAssertEqual(cancelReceipt.rejection?.code, "RUN_NOT_FOUND")

        let firstAdmission = try rendezvous.submit(
            operation: .admissionProbe(.init()),
            idempotencyKey: "same-admission-key", requestId: "admission-one"
        )
        let firstAdmissionMaybe = try await rendezvous.waitForReceipt(requestId: firstAdmission.requestId)
        let firstAdmissionReceipt = try XCTUnwrap(firstAdmissionMaybe)
        let secondAdmission = try rendezvous.submit(
            operation: .admissionProbe(.init()),
            idempotencyKey: "same-admission-key", requestId: "admission-two"
        )
        let secondAdmissionMaybe = try await rendezvous.waitForReceipt(requestId: secondAdmission.requestId)
        let secondAdmissionReceipt = try XCTUnwrap(secondAdmissionMaybe)
        XCTAssertEqual(firstAdmissionReceipt.canonicalId, secondAdmissionReceipt.canonicalId)
        XCTAssertEqual(firstAdmissionReceipt.acceptedAt, secondAdmissionReceipt.acceptedAt)
        guard case let .admissionProbe(probe)? = secondAdmissionReceipt.result else {
            return XCTFail("expected idempotent admission probe")
        }
        XCTAssertEqual(probe.reservationCount, 1)
        XCTAssertEqual(probe.vendorStarts, 0)

        let boost = try rendezvous.submit(
            operation: .boostSeed(.init(sourceId: "missing-source")),
            idempotencyKey: "boost", requestId: "boost-request"
        )
        let boostMaybeReceipt = try await rendezvous.waitForReceipt(requestId: boost.requestId)
        let boostReceipt = try XCTUnwrap(boostMaybeReceipt)
        XCTAssertEqual(boostReceipt.state, .rejected)
        XCTAssertEqual(boostReceipt.rejection?.code, "UTILIZATION_SOURCE_NOT_FOUND")

        let team = try rendezvous.submit(
            operation: .teamRun(.init(question: "hello", repoRoot: root.path)),
            idempotencyKey: "team", requestId: "team-request"
        )
        let teamMaybeReceipt = try await rendezvous.waitForReceipt(requestId: team.requestId)
        let teamReceipt = try XCTUnwrap(teamMaybeReceipt)
        XCTAssertEqual(teamReceipt.state, .rejected)
        XCTAssertNotNil(teamReceipt.rejection, "unrunnable request is classified, never executed in the client")
    }
}

private final class BrokerCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
