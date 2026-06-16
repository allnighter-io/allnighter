import XCTest
@testable import AllnighterCore

/// Mapper tests for `DoctorReport` — all mock/fixture, no live probes. Proves the
/// quota-free default honestly reports auth/readiness as `notChecked` (never
/// inferred), and that `--full` reflects real probe outcomes.
final class DoctorReportTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 0)
    private let models = [
        Model(id: "model_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code", role: .both),
        Model(id: "model_codex", displayName: "GPT-5 Codex", modelLabel: "gpt", driverId: "codex", role: .answerer),
    ]
    private let manifests = [
        DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI),
        DriverManifest(id: "codex", displayName: "Codex", kind: .headlessCLI),
    ]

    private func inputs(full: Bool, configOK: Bool = true, runsOK: Bool = true) -> DoctorReport.Inputs {
        .init(binaryVersion: "0.1.0", contractVersion: "1.0.0", configDirWritable: configOK, runsDirWritable: runsOK, full: full)
    }
    private func check(_ r: DoctorResult, _ name: String) -> DoctorResult.Check? { r.checks.first { $0.name == name } }

    func testDefaultIsQuotaFreeAndReportsNotChecked() {
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .installedNotProbed(version: "1.2"), version: "1.2", lastProbeAt: t),
            ToolProbeRecord(driverId: "codex", status: .installedNotProbed(version: "0.9"), version: "0.9", lastProbeAt: t),
        ]
        let r = DoctorReport.build(models: models, manifests: manifests, records: records, inputs: inputs(full: false))

        XCTAssertEqual(r.status, .ok, "all installed, no detected problems → ok even though readiness is unverified")
        // Readiness/auth honestly not checked, with a next action to --full.
        XCTAssertEqual(check(r, "source.claude_code.auth")?.status, .notChecked)
        XCTAssertEqual(check(r, "source.claude_code.auth")?.fixCommand, "alln doctor --full")
        XCTAssertEqual(check(r, "benchReadyCount")?.status, .notChecked)
        XCTAssertEqual(check(r, "planWriterReady")?.status, .notChecked)
        XCTAssertEqual(check(r, "source.claude_code.installed")?.status, .ok)
        // No readiness inferred: every model is unknown.
        XCTAssertTrue(r.models.allSatisfy { $0.status == .unknown })
        XCTAssertFalse(r.coordinator.available)
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
        XCTAssertEqual(auth?.fixCommand, "claude")
        XCTAssertTrue(auth?.requiresManual ?? false)
        // Codex is ready, so a minimal team can run → degraded, not critical.
        XCTAssertEqual(r.status, .degraded)
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
}
