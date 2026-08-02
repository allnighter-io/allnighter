import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine
@testable import AllnighterCLI

/// ORS-S01b — `alln show` reconciles ownership before mapping.
///
/// Lives in AllnighterEngineTests (not AllnighterCoreTests) because `runShow` /
/// `showReadPath` are on `AllnighterCLI`, which CoreTests cannot import.
///
/// Inference bans: ownerState is independent of lastActivityAt and activityMode;
/// unknown must stay unknown.
final class OneRunSurfaceShowOwnershipTests: XCTestCase {

    // MARK: - Helpers

    private func tempStore() -> (RunStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ors-s01b-\(UUID().uuidString)", isDirectory: true)
        return (RunStore(rootDirectory: dir), dir)
    }

    private func nonTerminalRun(id: String) -> TeamRun {
        TeamRun(
            id: id, prompt: "p", status: .fanningOut,
            workers: [Agent(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0)],
            answers: [TeamAnswer(
                memberId: "model_opus#0", modelId: "model_opus", role: "answer",
                result: WorkerRunResult(status: .queued)
            )],
            createdAt: Date()
        )
    }

    private func terminalRun(id: String) -> TeamRun {
        var run = nonTerminalRun(id: id)
        run.status = .done
        run.endReason = .completed
        return run
    }

    private func liveDetachedIdentity() throws -> ProcessOwnership.OwnerIdentity {
        let pid = ProcessInfo.processInfo.processIdentifier
        let ticks = try XCTUnwrap(ProcessOwnership.processStartTimeTicks(pid))
        return ProcessOwnership.OwnerIdentity(
            pid: pid, pgid: pid, startTimeTicks: ticks, kind: .detachedRunner
        )
    }

    private func model(id: String, driverId: String) -> Model {
        Model(id: id, displayName: id, modelLabel: id, driverId: driverId)
    }

    private func streamingManifest(id: String, canStream: Bool) -> DriverManifest {
        DriverManifest(
            id: id,
            displayName: id,
            kind: .headlessCLI,
            streaming: canStream
                ? .init(supported: true, mode: .jsonlStdout)
                : .init(supported: false, mode: .none)
        )
    }

    // MARK: - (a) reconcile is non-destructive

    /// Direct process proof: terminal run + identity-alive owner is NOT signalled
    /// by the show read path (which must not pass recoverTerminalLiveOwnership).
    func testShowReconcileDoesNotSignalLiveOwner() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        // Terminal + live PG-killable identity: recoverTerminalLiveOwnership:true
        // would force-kill; show must leave the tree alone.
        let run = terminalRun(id: "live-term")
        try store.save(run, models: [])
        let runDir = try store.runDirectory(forRunId: run.id)
        let identity = try liveDetachedIdentity()
        try ProcessOwnership.writeOwnerIdentity(identity, in: runDir)
        XCTAssertTrue(
            ProcessOwnership.isIdentityAlive(identity),
            "fixture precondition: identity must be alive"
        )

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        defer { ProcessOwnership.terminateSignalHook = nil }

        let prepared = AllnighterCLI.showReadPath(run: run, models: [], store: store)

        XCTAssertTrue(
            signals.isEmpty,
            "show read-path reconcile must not signal; got pgids \(signals)"
        )
        XCTAssertTrue(
            ProcessOwnership.isIdentityAlive(identity),
            "recorded owner must still be identity-alive after show reconcile"
        )
        // ownerState still reflects the live identity (not reaped/cleared).
        XCTAssertEqual(prepared.ownerState, .alive)
        XCTAssertEqual(prepared.run.status, .done, "terminal status must not be rewritten")
    }

    // MARK: - (b)(c)(d) ownerState from identity only

    func testLiveOwnerMapsToAlive() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var run = nonTerminalRun(id: "alive-owner")
        run.lastActivityAt = nil  // silence must not affect ownerState
        try store.save(run, models: [])
        let runDir = try store.runDirectory(forRunId: run.id)
        try ProcessOwnership.writeOwnerIdentity(try liveDetachedIdentity(), in: runDir)

        let prepared = AllnighterCLI.showReadPath(run: run, models: [], store: store)
        XCTAssertEqual(prepared.ownerState, .alive)
    }

    func testDeadRecordedIdentityMapsToDead() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var run = nonTerminalRun(id: "dead-owner")
        // Fresh activity must not promote a dead owner to alive.
        run.lastActivityAt = Date()
        try store.save(run, models: [])
        let runDir = try store.runDirectory(forRunId: run.id)
        let dead = ProcessOwnership.OwnerIdentity(
            pid: 2_000_000, pgid: 2_000_000, startTimeTicks: 1, kind: .detachedRunner
        )
        try ProcessOwnership.writeOwnerIdentity(dead, in: runDir)
        XCTAssertFalse(ProcessOwnership.isIdentityAlive(dead))

        let prepared = AllnighterCLI.showReadPath(run: run, models: [], store: store)
        // Reconcile may reap a dead non-terminal; ownerState is still from identity.
        XCTAssertEqual(prepared.ownerState, .dead)
    }

    func testNoRecordedIdentityMapsToUnknown() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var run = nonTerminalRun(id: "no-owner")
        run.lastActivityAt = Date()  // activity must never invent ownerState
        try store.save(run, models: [])
        // save stamps inProcess owner; strip it to model an unobserved run.
        let runDir = try store.runDirectory(forRunId: run.id)
        try FileManager.default.removeItem(at: ProcessOwnership.ownerURL(in: runDir))
        try? FileManager.default.removeItem(at: ProcessOwnership.legacyOwnerURL(in: runDir))
        XCTAssertNil(ProcessOwnership.readOwnerIdentity(in: runDir))

        let prepared = AllnighterCLI.showReadPath(run: run, models: [], store: store)
        XCTAssertEqual(
            prepared.ownerState, .unknown,
            "unobserved ownership must emit unknown, never masquerade as fine"
        )
        XCTAssertNotEqual(prepared.ownerState, .alive)
        XCTAssertNotEqual(prepared.ownerState, .dead)
    }

    // MARK: - (e) healthy terminalOnly + nil activity + alive

    func testAliveTerminalOnlyNilActivityIsHealthyRoundTrip() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var run = nonTerminalRun(id: "healthy-silence")
        run.lastActivityAt = nil
        try store.save(run, models: [])
        let runDir = try store.runDirectory(forRunId: run.id)
        try ProcessOwnership.writeOwnerIdentity(try liveDetachedIdentity(), in: runDir)

        let prepared = AllnighterCLI.showReadPath(run: run, models: [], store: store)
        XCTAssertEqual(prepared.ownerState, .alive)

        let driverId = "batch_driver"
        let modelId = prepared.run.workers.first?.modelId ?? "model_opus"
        let models = [model(id: modelId, driverId: driverId)]
        let manifests = [streamingManifest(id: driverId, canStream: false)]

        let context = AllnighterCLI.defaultRunContext(
            prepared.run, models: models, manifests: manifests,
            ownerState: prepared.ownerState
        )
        XCTAssertEqual(context.ownerState, .alive)

        let trj = TeamRunJSONMapper.map(
            prepared.run, models: models, manifests: manifests, context: context
        )
        XCTAssertEqual(
            trj.observation,
            TeamRunJSON.Observation(
                ownerState: .alive, activityMode: .terminalOnly, lastActivityAt: nil),
            "alive + terminalOnly + null activity is HEALTHY — owner independent of activity"
        )

        // Round-trip: all three fields present; unknown not silently upgraded.
        let data = try CoreJSON.encode(trj)
        let back = try CoreJSON.decode(TeamRunJSON.self, from: data)
        XCTAssertEqual(back.observation.ownerState, .alive)
        XCTAssertEqual(back.observation.activityMode, .terminalOnly)
        XCTAssertNil(back.observation.lastActivityAt)

        let rootJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let obs = try XCTUnwrap(rootJSON["observation"] as? [String: Any])
        XCTAssertEqual(obs["ownerState"] as? String, "alive")
        XCTAssertEqual(obs["activityMode"] as? String, "terminalOnly")
    }

    // MARK: - ORS-S03b negative proof: retired read verbs never touch a run

    /// Packet proof: old commands exit usage error without touching a run
    /// (no forward, no alias, no execution).
    func testRetiredTeamStatusAndResultExitUsageWithoutTouchingRun() throws {
        let alln = try locateAllnBinary()
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("ors-s03b-retired-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }

        let store = RunStore(rootDirectory: support.appendingPathComponent("Runs", isDirectory: true))
        let runId = "run_retired_cmd"
        var run = nonTerminalRun(id: runId)
        run.prompt = "do not mutate me"
        try store.save(run, models: [])
        let runJSON = try store.runDirectory(forRunId: runId).appendingPathComponent("run.json")
        let before = try Data(contentsOf: runJSON)
        let beforeMod = try FileManager.default.attributesOfItem(atPath: runJSON.path)[.modificationDate] as? Date

        let env = [
            "ALLNIGHTER_SUPPORT_DIR": support.path,
            "ALLNIGHTER_SKIP_LOGIN_PATH_BOOTSTRAP": "1",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": support.path,
        ]

        for args in [
            ["team", "status", runId, "--json"],
            ["team", "result", runId, "--json"],
        ] {
            let result = try runAlln(alln, args, env: env)
            XCTAssertEqual(
                result.status, ExitCode.usageError,
                "\(args.joined(separator: " ")) must exit CLI usage (2), got \(result.status)"
            )
            let blob = result.stdout + result.stderr
            XCTAssertTrue(
                blob.contains("CLI_USAGE_ERROR") || blob.contains("retired"),
                "expected usage/retired failure for \(args): \(blob.prefix(400))"
            )
            XCTAssertFalse(
                blob.contains("\"runId\""),
                "retired command must not emit a run snapshot: \(blob.prefix(400))"
            )
            // Must name the replacement without executing it.
            XCTAssertTrue(
                blob.contains("alln show") || blob.lowercased().contains("show"),
                "error may name alln show as replacement: \(blob.prefix(400))"
            )
        }

        let after = try Data(contentsOf: runJSON)
        XCTAssertEqual(before, after, "retired commands must not mutate the journal")
        let afterMod = try FileManager.default.attributesOfItem(atPath: runJSON.path)[.modificationDate] as? Date
        XCTAssertEqual(beforeMod, afterMod, "retired commands must not touch run mtime")
    }

    private func locateAllnBinary() throws -> URL {
        let buildDir = Bundle(for: OneRunSurfaceShowOwnershipTests.self).bundleURL.deletingLastPathComponent()
        let binary = buildDir.appendingPathComponent("alln")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: binary.path),
            "alln binary missing at \(binary.path) — build the alln product first"
        )
        return binary
    }

    private struct ProcessResult { var status: Int32; var stdout: String; var stderr: String }

    private func runAlln(_ alln: URL, _ arguments: [String], env: [String: String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = alln
        process.arguments = arguments
        process.environment = env
        let out = Pipe(); let err = Pipe()
        process.standardOutput = out; process.standardError = err
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}
