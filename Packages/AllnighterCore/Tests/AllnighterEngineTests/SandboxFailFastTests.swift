import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// A team run inside a sandboxing host must abandon the local attempt as soon as
/// the FIRST seat is refused, instead of waiting for the seats that happen to work.
///
/// Measured from a live founder run on 2026-07-25: a three-seat team inside Codex
/// knew at 1.2s that two seats could not start, then waited another 63s for the one
/// seat that could — and the entire run was handed to the app and re-run anyway.
/// The caller paid 64 seconds for a result that was thrown away, which is why a
/// ~75-second team took nearly three minutes.
final class SandboxFailFastTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-failfast-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        // The whole behavior is gated on a restricted host, and the coordinator reads
        // the process environment. Verified both ways: with this set the run abandons
        // in ~0.15s; without it the same test takes the full slow-seat 6s and fails,
        // which is the proof that ordinary terminals are untouched.
        setenv("CODEX_SANDBOX", "workspace-write", 1)
    }

    override func tearDownWithError() throws {
        unsetenv("CODEX_SANDBOX")
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Two seats: one refused by the sandbox immediately, one that would take a long
    /// time to succeed. The run must not pay for the slow one.
    func testARefusedSeatAbandonsTheLocalRunWithoutWaitingForTheSlowSeat() async throws {
        let repo = tmp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs", isDirectory: true))

        let slowSeconds = 6.0
        let team = TeamPreset(
            id: "test_failfast", displayName: "Fail Fast", lane: .code, outputKind: .plan,
            defaultEffort: .low,
            workerSpecs: [
                TeamWorkerSpec(id: "seat_blocked", skillId: SkillCatalog.directChatSkillId,
                               purpose: .answer, preferredModelId: "model_blocked"),
                TeamWorkerSpec(id: "seat_slow", skillId: SkillCatalog.directChatSkillId,
                               purpose: .answer, preferredModelId: "model_slow"),
            ],
            lead: TeamLeadSpec(skillId: "plan_writer_build"))

        let service = RunService(
            models: [
                Model(id: "model_blocked", displayName: "Blocked", modelLabel: "blocked",
                      driverId: "blocked_driver", role: .both),
                Model(id: "model_slow", displayName: "Slow", modelLabel: "slow",
                      driverId: "slow_driver", role: .both),
            ],
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "blocked_driver", command: "blocked"),
                TestSupport.headlessManifest(id: "slow_driver", command: "slow"),
            ]),
            teams: [team],
            runStore: runStore,
            commandRunner: MockCommandRunner(scripts: [
                // The exact shape observed live from cursor-agent inside the sandbox.
                "blocked": .init(stderr: "ERROR: SecItemCopyMatching failed -67674", exitCode: 11),
                "slow": .init(stdout: "eventually", exitCode: 0,
                              delay: .milliseconds(Int(slowSeconds * 1000))),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(defaultTier: .flagship, allowHealthySubstitutions: false,
                                     tiers: TierMembership(flagship: ["model_blocked", "model_slow"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "blocked_driver", status: .ready(version: "1"),
                                 lastProbeAt: .distantPast),
                 ToolProbeRecord(driverId: "slow_driver", status: .ready(version: "1"),
                                 lastProbeAt: .distantPast)]
            })


        let started = Date()
        let result = await service.run(
            RunRequest(message: "go", repoRoot: repo.path, presetId: team.id),
            origin: RunOrigin.cli)
        let elapsed = Date().timeIntervalSince(started)

        guard case .success(let run) = result else {
            return XCTFail("expected a run, got \(result)")
        }
        XCTAssertLessThan(
            elapsed, slowSeconds,
            "the local attempt must be abandoned on the first refused seat, not carried "
            + "to the end of the slowest one (took \(elapsed)s of a \(slowSeconds)s seat)")
        XCTAssertFalse(
            run.workerAnswers.isEmpty,
            "the refusal must still be recorded — the hand-off decision reads it")
    }
}
