import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PRJ-S05 Works Test: per-Project worker readiness is detected by running ONLY a
/// driver-declared, non-mutating safe probe in the Project root, and classifying
/// its output into the canonical `WorkerReadinessStatus` list. Drivers with no
/// safe probe (every shipped manifest today) report `unsafeToProbe` — never a
/// guessed `ready`. No real CLIs run; the command runner is a fake.
final class ProjectWorkerReadinessDetectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let projectId = "prj_test01"
    private let rootPath = "/tmp/some/project"

    // A fake driver that declares a safe, non-mutating probe.
    private func probeDriver(
        readyExpectation: String? = "ready",
        auth: [String] = ["please run /login", "not signed in"],
        projectAuth: [String] = ["do you trust the files in this folder"],
        blocked: [String] = ["usage limit reached"]
    ) -> DriverManifest {
        DriverManifest(
            id: "fake_probe",
            displayName: "Fake Probe CLI",
            kind: .headlessCLI,
            setup: SetupBlock(bins: ["fakecli"], installHint: "brew install fakecli",
                              loginFlow: LoginFlow(interactiveCommand: "fakecli",
                                                   instructions: "Run `fakecli`, then `/login`.")),
            projectProbe: ProjectProbe(
                mode: .safeCommand,
                command: "fakecli",
                args: ["doctor", "--no-input"],
                timeoutSeconds: 10,
                readyExpectation: readyExpectation,
                authErrorPatterns: auth,
                projectAuthorizationPatterns: projectAuth,
                blockedPatterns: blocked,
                declaredNonMutating: true
            )
        )
    }

    private func detect(_ manifest: DriverManifest, runner: MockCommandRunner) async -> ProjectWorkerReadiness {
        await ProjectWorkerReadinessDetector(runner: runner)
            .detect(projectId: projectId, rootPath: rootPath, manifest: manifest, workerId: "w1", now: now)
    }

    func testMissingProbeIsUnsafeToProbe() async throws {
        // A shipped-style manifest with no projectProbe must never be guessed ready.
        let manifest = DriverManifest(id: "legacy", displayName: "Legacy", kind: .headlessCLI,
                                      setup: SetupBlock(bins: ["legacy"]))
        let r = await detect(manifest, runner: MockCommandRunner(scripts: [:]))
        XCTAssertEqual(r.status, .unsafeToProbe)
        XCTAssertFalse(r.status.canRunInProject)
        XCTAssertNil(r.probeCommandLabel)
        XCTAssertNil(r.setupHint, "honest detail is projected at emit time, not in the cache")
    }

    func testDeclaredButMutatingProbeIsUnsafeToProbe() async throws {
        var manifest = probeDriver()
        manifest.projectProbe?.declaredNonMutating = false   // not safe for silent detection
        let runner = MockCommandRunner(scripts: ["fakecli": .init(stdout: "ready", exitCode: 0)])
        let r = await detect(manifest, runner: runner)
        XCTAssertEqual(r.status, .unsafeToProbe)
    }

    func testReadyWhenExitZeroAndExpectationMet() async throws {
        let runner = MockCommandRunner(scripts: ["fakecli": .init(stdout: "all systems ready\n", exitCode: 0)])
        let r = await detect(probeDriver(), runner: runner)
        XCTAssertEqual(r.status, .ready)
        XCTAssertTrue(r.status.canRunInProject)
        XCTAssertEqual(r.probeCommandLabel, "fakecli doctor --no-input")
        XCTAssertNil(r.lastError)
    }

    func testExitZeroWithoutExpectationIsUnknownNotReady() async throws {
        let runner = MockCommandRunner(scripts: ["fakecli": .init(stdout: "hello\n", exitCode: 0)])
        let r = await detect(probeDriver(), runner: runner)
        XCTAssertEqual(r.status, .unknown)   // ran cleanly but did not confirm — never claim ready
        XCTAssertFalse(r.status.canRunInProject)
    }

    func testReadyWhenNoExpectationDeclared() async throws {
        let runner = MockCommandRunner(scripts: ["fakecli": .init(stdout: "", exitCode: 0)])
        let r = await detect(probeDriver(readyExpectation: nil), runner: runner)
        XCTAssertEqual(r.status, .ready)
    }

    func testNotInstalledOnLaunchError() async throws {
        let runner = MockCommandRunner(scripts: ["fakecli": .init(launchError: "command not found: fakecli")])
        let r = await detect(probeDriver(), runner: runner)
        XCTAssertEqual(r.status, .notInstalled)
        XCTAssertEqual(r.setupHint, "brew install fakecli")
    }

    func testAuthRequiredFromStderrPattern() async throws {
        let runner = MockCommandRunner(scripts: ["fakecli": .init(stderr: "Error: not signed in", exitCode: 1)])
        let r = await detect(probeDriver(), runner: runner)
        XCTAssertEqual(r.status, .authRequired)
        XCTAssertEqual(r.setupHint, "Run `fakecli`, then `/login`.")
        XCTAssertEqual(r.lastError, "Error: not signed in")
    }

    func testNeedsProjectAuthorizationWinsOverExitZero() async throws {
        // A trust prompt can surface even on exit 0 — authorization signal must win.
        let runner = MockCommandRunner(scripts: ["fakecli": .init(
            stdout: "ready\nDo you trust the files in this folder?", exitCode: 0)])
        let r = await detect(probeDriver(), runner: runner)
        XCTAssertEqual(r.status, .needsProjectAuthorization)
        XCTAssertFalse(r.status.canRunInProject)
    }

    func testBlockedFromQuotaPattern() async throws {
        let runner = MockCommandRunner(scripts: ["fakecli": .init(stderr: "Usage limit reached", exitCode: 1)])
        let r = await detect(probeDriver(), runner: runner)
        XCTAssertEqual(r.status, .blocked)
    }

    func testTimeoutClassifiesAsInteractiveRequired() async throws {
        let runner = MockCommandRunner(scripts: ["fakecli": .init(forcesTimeout: true)])
        let r = await detect(probeDriver(), runner: runner)
        XCTAssertEqual(r.status, .interactiveRequired)
        XCTAssertNotNil(r.lastError)
    }

    func testNonZeroExitNoPatternIsUnknown() async throws {
        let runner = MockCommandRunner(scripts: ["fakecli": .init(stderr: "weird failure", exitCode: 3)])
        let r = await detect(probeDriver(), runner: runner)
        XCTAssertEqual(r.status, .unknown)
        XCTAssertEqual(r.lastError, "weird failure")
    }

    func testProbeKindIsRecorded() async throws {
        let runner = MockCommandRunner(scripts: ["fakecli": .init(stdout: "ready", exitCode: 0)])
        let r = await ProjectWorkerReadinessDetector(runner: runner)
            .detect(projectId: projectId, rootPath: rootPath, manifest: probeDriver(),
                    workerId: "w1", probeKind: .explicitRecheck, now: now)
        XCTAssertEqual(r.probeKind, .explicitRecheck)
        XCTAssertEqual(r.checkedAt, now)
    }
}
