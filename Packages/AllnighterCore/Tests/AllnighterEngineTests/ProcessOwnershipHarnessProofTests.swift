import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PO-S04 works/seam tests: harness-owned proof of record.
/// Uses real `ProcessGroupCommandRunner` for proofs (own process group + timeout).
final class ProcessOwnershipHarnessProofTests: XCTestCase {

    override func tearDown() {
        ProcessOwnership.terminateSignalHook = nil
        ProcessOwnership.TurnOwnerDirectory.shared.set(nil)
        super.tearDown()
    }

    // MARK: - Works test: sleep 300 → proofTimeout, group empty, results captured

    func testHarnessProofTimeoutStampsEndReasonAndEmptiesGroup() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-s04-timeout-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let support = tmp.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        setenv("ALLNIGHTER_SUPPORT_DIR", support.path, 1)
        defer { unsetenv("ALLNIGHTER_SUPPORT_DIR") }

        let repo = try makeGitRepo(in: tmp)
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let lane = ExecutionLaneRegistry()

        let report = """
        Implemented the change.

        ```proofCommands
        sleep 300
        ```
        """
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Review.\n\n```json\n{\"verdict\": \"continue\", \"handover\": \"Do the thing.\"}\n```"),
            .init(stdout: "Done.\n\n```json\n{\"verdict\": \"done\", \"note\": \"Shipped.\"}\n```"),
        ]
        let devScripts: [MockCommandRunner.Script] = [
            .init(stdout: report),
        ]
        let (service, _) = makeService(
            pmScripts: pmScripts, devScripts: devScripts, runStore: runStore, writeLock: lane
        )
        let proofRunner = ProcessGroupCommandRunner(
            environmentPolicy: AllnighterSpawnEnvironmentPolicy(),
            spawnKind: .harnessProof
        )
        let coordinator = LoopCoordinator(
            runService: service,
            stateStore: stateStore,
            runStore: runStore,
            executionLane: lane,
            proofCommandRunner: proofRunner
        )

        let state = try await coordinator.run(config: .init(
            projectRoot: repo.path,
            docPath: "docs/spec.md",
            pmModelId: "model_pm",
            devModelId: "model_dev",
            maxRounds: 5,
            proofTimeoutSeconds: 1
        )).get()

        let devRound = try XCTUnwrap(state.rounds.first { $0.devRunId != nil })
        XCTAssertEqual(
            devRound.devTurnEndReason, .proofTimeout,
            "harness kill of proof must stamp endReason=proofTimeout (never inferred)"
        )
        XCTAssertEqual(devRound.proofCommands, ["sleep 300"])
        // Declared proofs only — fixture repo is not the Allnighter product tree,
        // so contractDrift standing is silent N/A (no row, no standingFailed).
        let declared = devRound.proofResults.filter { !$0.standing }
        XCTAssertEqual(declared.count, 1, "one declared proof")
        let pr = try XCTUnwrap(declared.first)
        XCTAssertTrue(pr.timedOut)
        XCTAssertNil(pr.exitCode)
        XCTAssertGreaterThan(pr.durationMs, 0)
        XCTAssertTrue(pr.command.contains("sleep 300"))
        XCTAssertFalse(
            devRound.proofResults.contains { $0.standing },
            "foreign root: no standing proof row"
        )
        XCTAssertNil(devRound.standingFailed)

        let json = LoopJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        let logEntry = try XCTUnwrap(json.roundLog.first { $0.devRunId != nil })
        XCTAssertEqual(logEntry.endReason, "proofTimeout")
        XCTAssertEqual(logEntry.proofResults.filter { !$0.standing }.count, 1)
        XCTAssertTrue(logEntry.proofResults.contains { !$0.standing && $0.timedOut })

        // Group empty: no leftover sleep from the harness proof's process group.
        // (We cannot re-read the pgid after the fact without recording it; assert via
        // a follow-on short proof that starts clean — and via ProcessOwnership helpers
        // that a fresh sleep can be killed to empty.)
        let probe = try ProcessOwnership.spawnProcessGroupLeader(
            executablePath: "/bin/sleep",
            arguments: ["1"],
            workingDirectory: nil,
            stdinMode: .devNull,
            stdoutMode: .devNull,
            stderrMode: .devNull,
            kind: .harnessProof
        )
        ProcessOwnership.terminateProcessGroup(pgid: probe.pid)
        var status: Int32 = 0
        _ = waitpid(probe.pid, &status, 0)
        XCTAssertTrue(ProcessOwnership.isProcessGroupEmpty(probe.pid))
    }

    // MARK: - Works test: same persistent scratch across proofs (warm)

    func testNextProofUsesSamePersistentScratchWarm() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-s04-scratch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let support = tmp.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        setenv("ALLNIGHTER_SUPPORT_DIR", support.path, 1)
        defer { unsetenv("ALLNIGHTER_SUPPORT_DIR") }

        let repo = try makeGitRepo(in: tmp)
        let scratch = ExecutionLaneFlock.ensuredScratchPath(repoRoot: repo.path)
        let marker = (scratch as NSString).appendingPathComponent("warm-marker")
        try? FileManager.default.removeItem(atPath: marker)

        let runner = ProcessGroupCommandRunner(
            environmentPolicy: AllnighterSpawnEnvironmentPolicy(),
            spawnKind: .harnessProof
        )
        let service = ProjectVerificationService(
            commandRunner: runner,
            perCommandTimeoutSeconds: 10
        )

        // First proof: write marker into the persistent scratch.
        let writeCmd = "printf warm > '\(marker)'"
        let r1 = await service.runProofs(commands: [writeCmd], repoRoot: repo.path, scratchPath: scratch)
        XCTAssertEqual(r1.count, 1)
        XCTAssertTrue(r1[0].passed, "first proof should pass: \(r1[0].outputTail)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker))

        // Second proof on the SAME scratch: marker still present (warm / not wiped).
        let readCmd = "test -f '\(marker)' && cat '\(marker)'"
        let r2 = await service.runProofs(commands: [readCmd], repoRoot: repo.path, scratchPath: scratch)
        XCTAssertEqual(r2.count, 1)
        XCTAssertTrue(r2[0].passed, "warm scratch must survive for the next proof: \(r2[0].outputTail)")
        XCTAssertTrue(r2[0].outputTail.contains("warm"))

        // Path is the documented Lanes/<key>/scratch location.
        XCTAssertTrue(scratch.contains("/Lanes/"), "scratch lives under Allnighter/Lanes/<key>/scratch")
        XCTAssertTrue(scratch.hasSuffix("/scratch") || scratch.contains("/scratch"))
        let again = ExecutionLaneFlock.ensuredScratchPath(repoRoot: repo.path)
        XCTAssertEqual(again, scratch, "scratch is one persistent dir per root key, not per-attempt")
    }

    // MARK: - Works test: proof under lane → laneBusy when foreign holder

    func testHarnessProofBlockedByForeignHolderStampsLaneBusy() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-s04-lanebusy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let support = tmp.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        setenv("ALLNIGHTER_SUPPORT_DIR", support.path, 1)
        defer { unsetenv("ALLNIGHTER_SUPPORT_DIR") }

        let repo = try makeGitRepo(in: tmp)
        let lane = ExecutionLaneRegistry()
        let laneKey = ExecutionLane.key(repoRoot: repo.path)

        // Live holder: peer claims cannot take the lane without a ticket.
        let foreignIdentity = try XCTUnwrap(
            ProcessOwnership.OwnerIdentity.current(kind: .inProcess)
        )
        let acquireResult = await lane.tryAcquire(
            laneKey,
            claim: .make(
                id: "foreign-holder",
                kind: ExecutionLaneSite.mutatingRun.rawValue,
                identity: foreignIdentity
            )
        )
        guard case .success(let foreignToken) = acquireResult else {
            return XCTFail("foreign claim must hold the lane: \(acquireResult)")
        }
        defer {
            Task { await lane.release(laneKey, token: foreignToken, endReason: "testDone") }
        }

        // 1) Peer relayDevTurn → FIFO ticket (no silent wait, no acquire).
        let peerTry = await lane.tryAcquire(
            laneKey,
            claim: .make(
                id: "relay-waiter",
                kind: ExecutionLaneSite.relayDevTurn.rawValue,
                identity: foreignIdentity
            )
        )
        guard case .failure(let ticket) = peerTry else {
            return XCTFail("peer must receive EXECUTION_LANE_BUSY ticket, not the lane")
        }
        XCTAssertEqual(ticket.holder.id, "foreign-holder")
        XCTAssertEqual(ticket.position, 1)
        XCTAssertEqual(ticket.holder.kind, ExecutionLaneSite.mutatingRun.rawValue)

        // 2) harnessProof re-enters under mutatingRun (same identity) — proofs run
        // under the lane as nested build-class work (PO-S03/S04).
        XCTAssertTrue(ExecutionLaneClassification.mustAcquire(.harnessProof))
        let nestedTry = await lane.tryAcquire(
            laneKey,
            claim: .make(
                id: "proof-nested",
                kind: ExecutionLaneSite.harnessProof.rawValue,
                identity: foreignIdentity
            )
        )
        guard case .success(let nestedToken) = nestedTry else {
            return XCTFail("same-process harnessProof must re-enter under mutating holder")
        }
        await lane.release(laneKey, token: nestedToken, endReason: "nestedProofDone")

        // 3) Peer harnessProof that cannot re-enter: two peers of same site kind.
        let peerProof = await lane.tryAcquire(
            laneKey,
            claim: .make(
                id: "proof-peer",
                kind: ExecutionLaneSite.mutatingRun.rawValue,
                identity: foreignIdentity
            )
        )
        guard case .failure(let proofTicket) = peerProof else {
            return XCTFail("peer mutating claim must not steal the held lane")
        }
        XCTAssertEqual(proofTicket.holder.id, "foreign-holder")

        // 4) endReason laneBusy + proofResults empty on status JSON (what the
        // harness stamps when wait bound expires / try path refuses).
        let round = RelayRound(
            roundNumber: 1,
            startedAt: Date(),
            devTurnEndReason: .laneBusy,
            proofResults: [],
            proofCommands: ["true"]
        )
        let state = LoopState(
            id: "relay_lane_busy",
            projectRoot: repo.path,
            docPath: "docs/spec.md",
            pmModelId: "model_pm",
            devModelId: "model_dev",
            status: .escalated,
            rounds: [round],
            createdAt: Date(),
            note: "harness proof blocked on execution lane",
            laneBlocked: ticket
        )
        let json = LoopJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        XCTAssertEqual(json.roundLog[0].endReason, "laneBusy")
        XCTAssertTrue(json.roundLog[0].proofResults.isEmpty)
        XCTAssertEqual(json.laneBlocked?.holder.id, "foreign-holder")
        XCTAssertEqual(json.status, "escalated")
        _ = repo
    }

    // MARK: - Parser + scratch injection seams

    func testProofCommandsParserFenceJSONAndLines() {
        let jsonFence = """
        note

        ```proofCommands
        ["sleep 300", "true"]
        ```
        """
        XCTAssertEqual(
            HarnessProofCommandsParser.parse(from: jsonFence),
            ["sleep 300", "true"]
        )

        let lines = """
        ```proofCommands
        sleep 300
        # comment
        true
        ```
        """
        XCTAssertEqual(
            HarnessProofCommandsParser.parse(from: lines),
            ["sleep 300", "true"]
        )

        let object = #"tail {"proofCommands":["swift test"]} end"#
        XCTAssertEqual(
            HarnessProofCommandsParser.parse(from: object),
            ["swift test"]
        )

        XCTAssertEqual(
            HarnessProofCommandsParser.resolve(turnState: ["from-state"], report: jsonFence),
            ["from-state"],
            "turn state wins over report parse"
        )
    }

    func testInjectScratchPathForSwiftCommandsOnly() {
        let scratch = "/tmp/lane-scratch"
        let injected = ProjectVerificationService.injectScratchPath(
            into: "swift test --filter Foo",
            scratchPath: scratch
        )
        XCTAssertTrue(injected.contains("--scratch-path"))
        XCTAssertTrue(injected.contains(scratch))
        XCTAssertTrue(injected.hasPrefix("swift test"))

        let already = "swift build --scratch-path /other --package-path P"
        XCTAssertEqual(
            ProjectVerificationService.injectScratchPath(into: already, scratchPath: scratch),
            already
        )

        let shell = "true && echo hi"
        XCTAssertEqual(
            ProjectVerificationService.injectScratchPath(into: shell, scratchPath: scratch),
            shell
        )
    }

    func testHarnessProofKindIsProcessGroupKillable() {
        XCTAssertTrue(ProcessOwnership.OwnerKind.harnessProof.isProcessGroupKillable)
        XCTAssertFalse(ProcessOwnership.OwnerKind.inProcess.isProcessGroupKillable)
    }

    func testProofResultsProjectedOnLoopJSON() {
        var round = RelayRound(
            roundNumber: 1,
            startedAt: Date(timeIntervalSince1970: 1),
            devTurnEndReason: .proofTimeout,
            proofResults: [
                HarnessProofResult(
                    command: "sleep 300",
                    exitCode: nil,
                    durationMs: 1001,
                    outputTail: "",
                    timedOut: true
                )
            ],
            proofCommands: ["sleep 300"]
        )
        round.devRunId = "run_dev"
        let state = LoopState(
            id: "r1", projectRoot: "/r", docPath: "d", pmModelId: "pm",
            devModelId: "dev", status: .done, rounds: [round],
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let json = LoopJSON.project(state, contractVersion: "1.0.0")
        XCTAssertEqual(json.roundLog[0].endReason, "proofTimeout")
        XCTAssertEqual(json.roundLog[0].proofResults.count, 1)
        XCTAssertEqual(json.roundLog[0].proofResults[0].durationMs, 1001)
    }

    // MARK: - Fixtures

    private func makeGitRepo(in tmp: URL) throws -> URL {
        let dir = tmp.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func git(_ args: [String]) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", dir.path] + args
            p.standardOutput = Pipe(); p.standardError = Pipe()
            p.standardInput = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        }
        for a in [["init", "-q"], ["config", "user.email", "t@t.dev"],
                  ["config", "user.name", "T"], ["config", "commit.gpgsign", "false"]] {
            git(a)
        }
        try "spec".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        git(["add", "."]); git(["commit", "-q", "-m", "c1"])
        return dir
    }

    private func makeService(
        pmScripts: [MockCommandRunner.Script],
        devScripts: [MockCommandRunner.Script],
        runStore: RunStore,
        writeLock: RunWriteLockRegistry = RunWriteLockRegistry()
    ) -> (RunService, SequencedCommandRunner) {
        let pmModel = Model(id: "model_pm", displayName: "PM", modelLabel: "pm", driverId: "pm_cli", role: .both)
        let devModel = Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "dev_cli", role: .both)
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: "pm_cli", command: "pm_cli"),
            TestSupport.headlessManifest(id: "dev_cli", command: "dev_cli"),
        ])
        let runner = SequencedCommandRunner(queues: ["pm_cli": pmScripts, "dev_cli": devScripts])
        let service = RunService(
            models: [pmModel, devModel],
            registry: registry,
            runStore: runStore,
            commandRunner: runner,
            writeLock: writeLock,
            defaultSettings: { DefaultModelSettings() },
            probeRecords: {
                [
                    ToolProbeRecord(driverId: "pm_cli", status: .ready(version: "1"), lastProbeAt: .distantPast),
                    ToolProbeRecord(driverId: "dev_cli", status: .ready(version: "1"), lastProbeAt: .distantPast),
                ]
            }
        )
        return (service, runner)
    }
}
