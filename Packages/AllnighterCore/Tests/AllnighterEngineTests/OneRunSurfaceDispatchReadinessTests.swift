import XCTest
import AgentOSCLI
import AllnighterCore
@testable import AllnighterEngine

/// ORS-P0-DEGRADE / founder law locks: readiness informs selection and never
/// blocks an explicit `--model` pin. Dead CLIs still fail loudly at the real
/// vendor boundary (launch error / stderr), never with a silent no-op or a
/// pre-emptive `notReady` refusal.
final class OneRunSurfaceDispatchReadinessTests: XCTestCase {

    private var supportDir: URL!

    override func setUpWithError() throws {
        supportDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ors-dispatch-readiness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        setenv("ALLNIGHTER_SUPPORT_DIR", supportDir.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("ALLNIGHTER_SUPPORT_DIR")
        try? FileManager.default.removeItem(at: supportDir)
    }

    private func makeRepo() throws -> URL {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("ors-readiness-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        return repo
    }

    private func grokModel() -> Model {
        Model(
            id: "model_grok", displayName: "Grok", modelLabel: "grok",
            driverId: "grok", role: .both, enabled: true
        )
    }

    private static func settings(pin: String = "model_grok") -> DefaultModelSettings {
        DefaultModelSettings(
            defaultTier: .frontier,
            allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: [pin])
        )
    }

    // MARK: - Explicit pin + negative/stale cache still DISPATCHES

    /// Cached negative readiness (auth dead / probe failed / not probed) must
    /// not pre-emptively refuse an explicit `--model` — attempt the vendor.
    func testExplicitModelWithNegativeCachedReadinessStillDispatches() async throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let negatives: [ModelSetupStatus] = [
            .installedNotProbed(version: "0.2.117"),
            .installedNotSignedIn(LoginFlow(interactiveCommand: "grok", instructions: "Sign in.")),
            .probeFailed(reason: "smoke timed out after self-update"),
        ]

        for status in negatives {
            let probe = ToolProbeRecord(
                driverId: "grok", status: status, version: "0.2.117", lastProbeAt: .distantPast
            )
            let service = RunService(
                models: [grokModel()],
                registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
                commandRunner: MockCommandRunner(scripts: [
                    "grok": .init(stdout: "Dispatched despite \(status).", exitCode: 0),
                ]),
                writeLock: RunWriteLockRegistry(),
                defaultSettings: { Self.settings() },
                probeRecords: { [probe] }
            )

            let result = await service.run(
                RunRequest(message: "ping", repoRoot: repo.path, pinnedModelId: "model_grok"),
                origin: .cli
            )
            guard case .success(let run) = result else {
                return XCTFail("negative cache \(status) must still dispatch; got \(result)")
            }
            XCTAssertEqual(run.answers.first?.modelId, "model_grok", "status \(status)")
            XCTAssertEqual(run.executionSourceId, "grok", "status \(status)")
            XCTAssertEqual(run.status, .complete, "status \(status)")
            XCTAssertFalse(
                "\(result)".localizedCaseInsensitiveContains("notReady"),
                "must never refuse with notReady for \(status)"
            )
        }
    }

    /// Unknown readiness (no probe record) still dispatches — never invents a veto.
    func testUnknownReadinessStillDispatchesExplicitModel() async throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let service = RunService(
            models: [grokModel()],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            commandRunner: MockCommandRunner(scripts: [
                "grok": .init(stdout: "Unknown is not a veto.", exitCode: 0),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { Self.settings() },
            probeRecords: { [] } // truly unknown
        )

        let result = await service.run(
            RunRequest(message: "ping", repoRoot: repo.path, pinnedModelId: "model_grok"),
            origin: .cli
        )
        guard case .success(let run) = result else {
            return XCTFail("unknown readiness must still dispatch; got \(result)")
        }
        XCTAssertEqual(run.status, .complete)
        XCTAssertEqual(run.answers.first?.modelId, "model_grok")
    }

    // MARK: - Dead CLI fails LOUDLY at the real boundary

    /// Genuinely missing binary: dispatch is attempted; failure names the binary
    /// and is typed (failed run / launch error) — not a silent no-op or notReady.
    func testMissingBinaryFailsLoudlyNamingBinary() async throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        // Cache says installed (or unknown) so we reach the real spawn boundary.
        // Binary is dead: mock surfaces the same launchError ProcessGroupCommandRunner
        // emits for PATH miss — "command not found: <binary>".
        let probe = ToolProbeRecord(
            driverId: "grok",
            status: .installedNotProbed(version: "0.2.118"),
            version: "0.2.118",
            lastProbeAt: .distantPast
        )
        let missingMessage = "command not found: grok"
        let service = RunService(
            models: [grokModel()],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            commandRunner: MockCommandRunner(scripts: [
                "grok": .init(launchError: missingMessage),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { Self.settings() },
            probeRecords: { [probe] }
        )

        let started = Date()
        let result = await service.run(
            RunRequest(message: "ping", repoRoot: repo.path, pinnedModelId: "model_grok"),
            origin: .cli
        )
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 15, "missing binary must fail promptly, not hang")

        // Dispatch happened (not AGENT_NOT_AVAILABLE / notReady at resolve).
        guard case .success(let run) = result else {
            if case .failure(let err) = result {
                XCTFail(
                    "missing binary must reach vendor boundary, not pre-empt at resolve; " +
                    "got \(err.code): \(err.description)"
                )
            }
            return
        }
        XCTAssertNotEqual(run.status, .complete, "dead CLI must not report success")
        let reason = run.answers.first?.result.errorReason
            ?? run.failedWorkerAnswers.first?.result.errorReason
            ?? run.attempts.last?.reason
            ?? ""
        XCTAssertTrue(
            reason.contains("grok") || reason.contains(missingMessage),
            "failure must name the missing binary; got \(reason)"
        )
        XCTAssertFalse(
            reason.localizedCaseInsensitiveContains("notReady"),
            "must not replace missing-binary with notReady; got \(reason)"
        )
    }

    /// Vendor exits non-zero with its own stderr (auth dead) — that text reaches
    /// the caller; Allnighter must not swallow it into a generic notReady.
    func testVendorStderrSurfacesVerbatimNotReplacedByNotReady() async throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let vendorStderr = "VENDOR_AUTH_DEAD_TOKEN: not logged in — run `grok auth login`"
        // Stale negative cache that used to veto — must not short-circuit.
        let probe = ToolProbeRecord(
            driverId: "grok",
            status: .installedNotSignedIn(
                LoginFlow(interactiveCommand: "grok", instructions: "Sign in.")
            ),
            version: "0.2.118",
            lastProbeAt: .distantPast
        )
        let service = RunService(
            models: [grokModel()],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            commandRunner: MockCommandRunner(scripts: [
                "grok": .init(stderr: vendorStderr, exitCode: 1),
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { Self.settings() },
            probeRecords: { [probe] }
        )

        let result = await service.run(
            RunRequest(message: "ping", repoRoot: repo.path, pinnedModelId: "model_grok"),
            origin: .cli
        )
        guard case .success(let run) = result else {
            return XCTFail(
                "auth-dead vendor must dispatch then fail loudly, not refuse resolve; got \(result)"
            )
        }
        XCTAssertNotEqual(run.status, .complete, "nonzero vendor exit must not look like success")

        let surfaces = [
            run.answers.first?.result.errorReason,
            run.failedWorkerAnswers.first?.result.errorReason,
            run.attempts.last?.reason,
            run.blocker?.capacityObservation?.rawSnippet,
            run.warnings.joined(separator: " "),
        ].compactMap { $0 }.joined(separator: " | ")

        XCTAssertFalse(
            surfaces.localizedCaseInsensitiveContains("notReady"),
            "vendor failure must not be replaced by notReady; surfaces=\(surfaces)"
        )
        // Prefer the vendor's own words; capacity classification may headline
        // authRequired but must not invent the old readiness veto.
        let hasVendorToken = surfaces.contains("VENDOR_AUTH_DEAD_TOKEN")
            || surfaces.contains("not logged in")
            || surfaces.localizedCaseInsensitiveContains("auth")
        XCTAssertTrue(
            hasVendorToken,
            "vendor exit reason must reach the caller; surfaces=\(surfaces)"
        )
    }

    // MARK: - Resolver canStart (dry-run twin of dispatch)

    func testResolverAllowsExplicitModelDespiteNegativeProbeCache() {
        let model = grokModel()
        let negatives: [ModelSetupStatus] = [
            .probeFailed(reason: "stale after self-update"),
            .installedNotProbed(version: "0.2.117"),
            .installedNotSignedIn(LoginFlow(interactiveCommand: "grok", instructions: "x")),
        ]
        for status in negatives {
            let invocation = RunInvocationResolver.resolve(
                RunInvocationInput(
                    message: "ping",
                    projectRoot: "/tmp/ors-readiness",
                    flagMode: .dryRun,
                    flags: .init(pinnedModelId: "model_grok", json: true)
                ),
                context: RunInvocationResolveContext(
                    models: [model],
                    readyModels: [model],
                    // readyModelIds deliberately excludes the pin — old path blocked.
                    readyModelIds: [],
                    defaultSettings: Self.settings(),
                    probeRecords: [
                        ToolProbeRecord(driverId: "grok", status: status, lastProbeAt: .distantPast),
                    ],
                    parkedDriverIds: []
                )
            )
            XCTAssertTrue(
                invocation.canStart,
                "explicit pin must canStart despite \(status); blocked=\(invocation.blockedReason ?? "nil")"
            )
            XCTAssertNil(invocation.blockedReason, "status \(status)")
            XCTAssertEqual(invocation.pinnedModelId, "model_grok")
        }
    }

    func testResolverAllowsExplicitModelWhenProbeUnknown() {
        let model = grokModel()
        let invocation = RunInvocationResolver.resolve(
            RunInvocationInput(
                message: "ping",
                projectRoot: "/tmp/ors-readiness",
                flagMode: .dryRun,
                flags: .init(pinnedModelId: "model_grok", json: true)
            ),
            context: RunInvocationResolveContext(
                models: [model],
                readyModels: [model],
                readyModelIds: [],
                defaultSettings: Self.settings(),
                probeRecords: [],
                parkedDriverIds: []
            )
        )
        XCTAssertTrue(invocation.canStart, "unknown readiness must still canStart")
        XCTAssertNil(invocation.blockedReason)
    }
}
