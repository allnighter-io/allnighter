import XCTest
@testable import AllnighterCore

/// Mapper tests for `DoctorReport` — all mock/fixture, no live probes. Proves the
/// quota-free default honestly reports auth/readiness as `notChecked` (never
/// inferred), and that `--full` reflects real probe outcomes.
final class DoctorReportTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 0)
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    private let models = [
        Model(id: "model_opus", displayName: "Opus 5", modelLabel: "opus", driverId: "claude_code", role: .both),
        Model(id: "model_codex", displayName: "GPT-5 Codex", modelLabel: "gpt", driverId: "codex", role: .answerer),
    ]
    private let manifests = [
        DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI),
        DriverManifest(id: "codex", displayName: "Codex", kind: .headlessCLI),
    ]

    private func inputs(full: Bool, configOK: Bool = true, runsOK: Bool = true, coordinator: DoctorResult.Coordinator? = nil) -> DoctorReport.Inputs {
        .init(binaryVersion: "0.1.0", contractVersion: "1.0.0", configDirWritable: configOK, runsDirWritable: runsOK, coordinator: coordinator, full: full)
    }
    private func check(_ r: DoctorResult, _ name: String) -> DoctorResult.Check? { r.checks.first { $0.name == name } }

    func testDefaultIsQuotaFreeAndReportsNotChecked() {
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .installedNotProbed(version: "1.2"), version: "1.2", lastProbeAt: t),
            ToolProbeRecord(driverId: "codex", status: .installedNotProbed(version: "0.9"), version: "0.9", lastProbeAt: t),
        ]
        let coord = DoctorResult.Coordinator(state: .foregroundOnly, detail: "foreground CLI only")
        let r = DoctorReport.build(models: models, manifests: manifests, records: records,
                                   inputs: inputs(full: false, coordinator: coord))

        XCTAssertEqual(r.status, .ok, "all installed, no detected problems → ok even though readiness is unverified")
        // Readiness/auth honestly not checked, with a next action to --full.
        XCTAssertEqual(check(r, "source.claude_code.auth")?.status, .notChecked)
        XCTAssertEqual(check(r, "source.claude_code.auth")?.fixCommand, "alln doctor --full")
        XCTAssertEqual(check(r, "benchReadyCount")?.status, .notChecked)
        XCTAssertEqual(check(r, "planWriterReady")?.status, .notChecked)
        XCTAssertEqual(check(r, "source.claude_code.installed")?.status, .ok)
        // Cursor shell allowlist: nil path in unit inputs → notChecked (never hits real ~/.cursor).
        XCTAssertEqual(check(r, "source.cursor_agent.shellAllowlist")?.status, .notChecked)
        // No readiness inferred: every model is unknown.
        XCTAssertTrue(r.models.allSatisfy { $0.status == .unknown })
        XCTAssertFalse(r.coordinator.available)
        XCTAssertEqual(r.coordinator.state, .foregroundOnly)
    }

    func testNeverScannedDoctorEmitsDetectNextAction() {
        let r = DoctorReport.build(
            models: models,
            manifests: manifests,
            records: [],
            inputs: inputs(full: false)
        )
        XCTAssertEqual(check(r, "benchReadyCount")?.status, .notChecked)
        XCTAssertEqual(check(r, "benchReadyCount")?.fixCommand, "alln detect")
        XCTAssertEqual(r.nextActions.first?.command, "alln detect")
        XCTAssertEqual(r.nextActions.first?.kind, "detectCLIs")
    }

    func testFullReflectsRealProbeOutcomes() {
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1.2"), version: "1.2", lastProbeAt: t),
            ToolProbeRecord(driverId: "codex", status: .ready(version: "0.9"), version: "0.9", lastProbeAt: t),
        ]
        let r = DoctorReport.build(models: models, manifests: manifests, records: records, inputs: inputs(full: true))
        XCTAssertEqual(r.status, .ok)
        XCTAssertEqual(check(r, "source.claude_code.auth")?.status, .ok)
        XCTAssertEqual(check(r, "benchReadyCount")?.status, .ok)
        XCTAssertEqual(check(r, "planWriterReady")?.status, .ok)
        XCTAssertEqual(r.models.first { $0.id == "model_opus" }?.status, .ready)
    }

    func testFullSurfacesAuthFailureWithFix() {
        let flow = LoginFlow(interactiveCommand: "claude", instructions: "Run `claude`, then `/login`.")
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .installedNotSignedIn(flow), version: "1.2", lastProbeAt: t),
            ToolProbeRecord(driverId: "codex", status: .ready(version: "0.9"), version: "0.9", lastProbeAt: t),
        ]
        let r = DoctorReport.build(models: models, manifests: manifests, records: records, inputs: inputs(full: true))
        let auth = check(r, "source.claude_code.auth")
        XCTAssertEqual(auth?.status, .degraded)
        XCTAssertNil(auth?.fixCommand, "Claude /login is not a shell command")
        XCTAssertTrue(auth?.detail.contains("/login") ?? false, auth?.detail ?? "")
        XCTAssertTrue(auth?.requiresManual ?? false)
        // Codex is ready, so a minimal team can run → degraded, not critical.
        XCTAssertEqual(r.status, .degraded)
        XCTAssertEqual(r.nextActions.first?.kind, "signInClaude")
        XCTAssertEqual(r.nextActions.first?.command, "alln help get setup_and_auth")
    }

    func testFullMapsOpaqueClaudeSmokeToSignIn() {
        let records = [
            ToolProbeRecord(
                driverId: "claude_code",
                status: .probeFailed(reason: "smoke exited 1"),
                version: "1.2",
                lastProbeAt: t
            ),
            ToolProbeRecord(driverId: "codex", status: .ready(version: "0.9"), version: "0.9", lastProbeAt: t),
        ]
        let r = DoctorReport.build(models: models, manifests: manifests, records: records, inputs: inputs(full: true))
        let auth = check(r, "source.claude_code.auth")
        XCTAssertEqual(auth?.status, .degraded)
        XCTAssertTrue(auth?.detail.contains("/login") ?? false, auth?.detail ?? "")
        XCTAssertNil(auth?.fixCommand)
    }

    func testOpenCodeGoCheckIsInformationalWhenDisconnected() {
        OpenCodeModelGate.overrideGoConnectedForTesting(false)
        defer { OpenCodeModelGate.overrideGoConnectedForTesting(nil) }
        let records = [
            ToolProbeRecord(driverId: "opencode", status: .ready(version: "1.0"), version: "1.0", lastProbeAt: t),
            ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1.2"), version: "1.2", lastProbeAt: t),
        ]
        let manifestsWithOC = manifests + [
            DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI)
        ]
        let r = DoctorReport.build(
            models: models, manifests: manifestsWithOC, records: records, inputs: inputs(full: true))
        let go = check(r, "source.opencode.goConnected")
        XCTAssertEqual(go?.status, .ok)
        XCTAssertTrue(go?.detail.contains("$10") ?? false, go?.detail ?? "")
        XCTAssertEqual(go?.fixCommand, OpenCodeModelGate.goPlanURL.absoluteString)
        XCTAssertEqual(r.status, .ok, "missing Go must not fail doctor overall")
    }

    func testDoctorBenchTallyHonorsParkedSet() {
        var base = inputs(full: true)
        base.parked = ["codex"]
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1.2"), version: "1.2", lastProbeAt: t),
            ToolProbeRecord(driverId: "codex", status: .notInstalled, lastProbeAt: t),
        ]
        let r = DoctorReport.build(models: models, manifests: manifests, records: records, inputs: base)
        // Parked Codex is excluded from supported — one ready of one supported → allReady.
        XCTAssertEqual(check(r, "benchReadyCount")?.detail, "1 CLI ready (allReady)")
    }

    func testDoctorKeepsDistinctRepairNextActions() {
        let records = [
            ToolProbeRecord(
                driverId: "claude_code",
                status: .probeFailed(reason: "smoke exited 1"),
                version: "1",
                lastProbeAt: t
            ),
            ToolProbeRecord(
                driverId: "opencode",
                status: .probeFailed(reason: "opencode smoke: messageFailed"),
                version: "1",
                lastProbeAt: t
            ),
        ]
        let manifestsWithOC = manifests + [
            DriverManifest(id: "opencode", displayName: "OpenCode", kind: .headlessCLI)
        ]
        let r = DoctorReport.build(
            models: models, manifests: manifestsWithOC, records: records, inputs: inputs(full: true))
        let kinds = Set(r.nextActions.map(\.kind))
        let commands = Set(r.nextActions.map(\.command))
        XCTAssertTrue(kinds.contains("signInClaude"))
        XCTAssertTrue(kinds.contains("repairProbe") || commands.contains("alln detect"))
        XCTAssertGreaterThanOrEqual(r.nextActions.count, 2)
    }

    func testFullWithZeroReadyIsCritical() {
        // Probed, and no source can run → critical (contract: no runnable team).
        let flow = LoginFlow(interactiveCommand: "claude", instructions: "Sign in.")
        let records = [ToolProbeRecord(driverId: "claude_code", status: .installedNotSignedIn(flow), version: "1.2", lastProbeAt: t)]
        let r = DoctorReport.build(models: [models[0]], manifests: manifests, records: records, inputs: inputs(full: true))
        XCTAssertEqual(r.status, .critical)
        XCTAssertEqual(check(r, "source.claude_code.auth")?.status, .degraded)   // still actionable
    }

    func testNothingInstalledIsCritical() {
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .notInstalled, lastProbeAt: t),
            ToolProbeRecord(driverId: "codex", status: .notInstalled, lastProbeAt: t),
        ]
        let r = DoctorReport.build(models: models, manifests: manifests, records: records, inputs: inputs(full: false))
        XCTAssertEqual(r.status, .critical)
        XCTAssertEqual(check(r, "source.claude_code.installed")?.status, .degraded)
    }

    func testUnwritableDirsAreCritical() {
        let records = [ToolProbeRecord(driverId: "claude_code", status: .installedNotProbed(version: "1.2"), version: "1.2", lastProbeAt: t)]
        let r = DoctorReport.build(models: [models[0]], manifests: manifests, records: records, inputs: inputs(full: false, runsOK: false))
        XCTAssertEqual(r.status, .critical)
        XCTAssertEqual(check(r, "runsDir")?.status, .critical)
    }

    func testResultConformsToSchemaEnumsAndRoundTrips() throws {
        let records = [ToolProbeRecord(driverId: "claude_code", status: .installedNotProbed(version: "1.2"), version: "1.2", lastProbeAt: t)]
        let r = DoctorReport.build(models: [models[0]], manifests: manifests, records: records, inputs: inputs(full: false))
        let data = try CoreJSON.encode(r)
        XCTAssertEqual(try CoreJSON.decode(DoctorResult.self, from: data), r)
        // The schema's Check.status enum must allow every value the mapper emits.
        let defs = try XCTUnwrap(ContractSchema.doctorResultSchema()["$defs"] as? [String: Any])
        let checkDef = try XCTUnwrap(defs["Check"] as? [String: Any])
        let props = try XCTUnwrap(checkDef["properties"] as? [String: Any])
        let statusEnum = Set(try XCTUnwrap((props["status"] as? [String: Any])?["enum"] as? [String]))
        XCTAssertTrue(Set(r.checks.map { $0.status.rawValue }).isSubset(of: statusEnum))
    }

    func testPilotCheckOkWhenDriverInstalledAndSeatRemembered() {
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .installedNotProbed(version: "1.2"), version: "1.2", lastProbeAt: t),
        ]
        var base = inputs(full: false)
        base.pilot = .init(
            projectLabel: "Allnighter (prj_abc)",
            devModelId: "model_sonnet",
            devWorkerLabel: "model_sonnet (Sonnet)",
            driverInstalled: true,
            driverReady: nil
        )
        let r = DoctorReport.build(models: models, manifests: manifests, records: records, inputs: base)
        let pilot = check(r, "pilot")
        XCTAssertEqual(pilot?.status, .ok)
        XCTAssertTrue(pilot?.detail.contains("can start") ?? false)
        XCTAssertEqual(pilot?.fixCommand, "alln doctor --full")
    }

    func testPilotCheckCriticalWhenNoProject() {
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .installedNotProbed(version: "1.2"), version: "1.2", lastProbeAt: t),
        ]
        var base = inputs(full: false)
        base.pilot = .init(projectLabel: nil, devModelId: nil, driverInstalled: false)
        let r = DoctorReport.build(models: models, manifests: manifests, records: records, inputs: base)
        XCTAssertEqual(check(r, "pilot")?.status, .critical)
    }

    /// Rate-limited = healthy install, temporary quota wall — degraded auth copy
    /// with a reset time when known, not the same bucket as a broken CLI.
    func testFullSurfacesRateLimitedAsDegradedWithReset() {
        let reset = Date().addingTimeInterval(9_900)
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "codex",
            sourceConfidence: .structured,
            rawSnippet: "weekly limit reached",
            observedAt: t,
            observedResetAt: reset,
            wakeAfter: reset
        )
        let records = [
            ToolProbeRecord(
                driverId: "codex",
                status: .rateLimited(observation: observation),
                version: "0.9",
                lastProbeAt: t
            ),
            ToolProbeRecord(
                driverId: "claude_code",
                status: .ready(version: "1.2"),
                version: "1.2",
                lastProbeAt: t
            ),
        ]
        let r = DoctorReport.build(
            models: models, manifests: manifests, records: records, inputs: inputs(full: true)
        )
        XCTAssertEqual(check(r, "source.codex.installed")?.status, .ok)
        let auth = check(r, "source.codex.auth")
        XCTAssertEqual(auth?.status, .degraded)
        XCTAssertTrue(auth?.detail.contains("Rate limited") ?? false)
        XCTAssertTrue(auth?.detail.contains("resets") ?? false)
        // Claude still ready → overall degraded, not critical.
        XCTAssertEqual(r.status, .degraded)
    }

    func testRateLimitedDetailWithoutWakeSaysRetrySoon() {
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "codex",
            sourceConfidence: .messageFallback,
            rawSnippet: "rate limit",
            observedAt: t
        )
        XCTAssertEqual(
            DoctorReport.rateLimitedDetail(observation: observation),
            "Rate limited — reset time unknown"
        )
    }

    func testLocalPolicyWithoutResetSaysUnknown() {
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "codex",
            sourceConfidence: .localPolicy,
            rawSnippet: "rate limit",
            observedAt: t,
            retryAfterSeconds: 3600,
            wakeAfter: t.addingTimeInterval(3600)
        )
        XCTAssertEqual(
            DoctorReport.rateLimitedDetail(observation: observation),
            "Rate limited — reset time unknown"
        )
    }

    func testRateLimitedCountdownUnder24h() {
        let future = fixedNow.addingTimeInterval(23 * 3_600 + 59 * 60)
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "codex",
            sourceConfidence: .structured,
            rawSnippet: "rate limit",
            observedAt: fixedNow,
            observedResetAt: future
        )
        let detail = DoctorReport.rateLimitedDetail(observation: observation, now: fixedNow)
        XCTAssertTrue(detail.contains("in "))
    }

    func testRateLimitedDateFormatBeyond24h() {
        let future = fixedNow.addingTimeInterval(24 * 3_600 + 60)
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "codex",
            sourceConfidence: .structured,
            rawSnippet: "rate limit",
            observedAt: fixedNow,
            observedResetAt: future
        )
        let detail = DoctorReport.rateLimitedDetail(observation: observation, now: fixedNow)
        XCTAssertTrue(detail.contains("Rate limited — resets "))
        XCTAssertFalse(detail.contains("in "))
    }

    /// PF-S02. This assertion used to run the other way: a `.localPolicy` limit
    /// plus a crawler reset window rendered a confident countdown. The limit is
    /// inferred by us and the reset is vendor-read — splicing them states as one
    /// fact something no vendor ever said.
    func testVendorResetDoesNotDressAnInferredLimitInAVendorTime() {
        let vendorReset = fixedNow.addingTimeInterval(2 * 3_600)
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "codex",
            sourceConfidence: .localPolicy,
            rawSnippet: "rate limit",
            observedAt: fixedNow,
            observedResetAt: nil
        )
        let detail = DoctorReport.rateLimitedDetail(observation: observation, vendorReset: vendorReset, now: fixedNow)
        XCTAssertEqual(detail, "Rate limited — reset time unknown")
        XCTAssertFalse(detail.contains("in "), "inferred limit must not carry a countdown")
    }

    /// The control: `vendorReset` still does its job when the limit itself is
    /// vendor-stated. PF-S02 withholds the splice, not the feature.
    func testVendorResetStillSuppliesCountdownForAVendorStatedLimit() {
        let vendorReset = fixedNow.addingTimeInterval(2 * 3_600)
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "codex",
            sourceConfidence: .structured,
            rawSnippet: "rate limit",
            observedAt: fixedNow,
            observedResetAt: nil
        )
        let detail = DoctorReport.rateLimitedDetail(observation: observation, vendorReset: vendorReset, now: fixedNow)
        XCTAssertTrue(detail.contains("in "), "should show countdown, got: \(detail)")
        XCTAssertFalse(detail.contains("reset time unknown"))
    }

    func testVendorResetNilPreservesCurrentBehavior() {
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "codex",
            sourceConfidence: .localPolicy,
            rawSnippet: "rate limit",
            observedAt: fixedNow,
            observedResetAt: nil
        )
        let detail = DoctorReport.rateLimitedDetail(observation: observation, vendorReset: nil, now: fixedNow)
        XCTAssertEqual(detail, "Rate limited — reset time unknown")
    }

    func testRateLimitedPastResetHidesTime() {
        let past = fixedNow.addingTimeInterval(-3 * 3_600)
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "codex",
            sourceConfidence: .structured,
            rawSnippet: "rate limit",
            observedAt: fixedNow,
            observedResetAt: past
        )
        XCTAssertEqual(
            DoctorReport.rateLimitedDetail(observation: observation, now: fixedNow),
            "Rate limited"
        )
    }
}
