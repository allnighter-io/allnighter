import XCTest
@testable import AllnighterCore

final class TeachingInstalledCheckTests: XCTestCase {
    func testHostMatrixFreezesGlobalPathsOnly() {
        let byHost = Dictionary(uniqueKeysWithValues: TeachingInstalledCheck.hostMatrix.map { ($0.host, $0.support) })
        guard case .supported(let claudePath) = byHost[.claude] else {
            return XCTFail("claude must be supported")
        }
        XCTAssertEqual(claudePath, ".claude/CLAUDE.md")
        guard case .supported(let cursorPath) = byHost[.cursor] else {
            return XCTFail("cursor must be supported")
        }
        XCTAssertEqual(cursorPath, ".cursor/rules/allnighter.mdc")
        guard case .unsupported(let reason) = byHost[.codex] else {
            return XCTFail("codex must be unsupported in v1")
        }
        XCTAssertTrue(reason.contains("no global"))
        XCTAssertTrue(reason.contains("bootstrap --host codex"))
    }

    func testCheckNameMatchesContract() {
        XCTAssertEqual(TeachingInstalledCheck.checkName, "teaching.installed")
        let names = ContractRegistry.milestone1.doctorChecks.map(\.name)
        XCTAssertTrue(names.contains("teaching.installed"))
    }

    func testNilInputsAreNotChecked() {
        let check = TeachingInstalledCheck.check(inputs: nil)
        XCTAssertEqual(check.name, "teaching.installed")
        XCTAssertEqual(check.status, .notChecked)
    }

    func testAggregateInstalledOk() {
        let marked = TeachingSnippet.wrap()
        let inputs: [TeachingInstalledCheck.TargetInput] = [
            .init(hostId: "claude", path: "/tmp/fake-claude", source: .contents(marked)),
            .init(hostId: "cursor", path: "/tmp/fake-cursor", source: .contents(marked)),
            .init(hostId: "codex", unsupported: true, unsupportedReason: "no global"),
        ]
        let check = TeachingInstalledCheck.check(inputs: inputs)
        XCTAssertEqual(check.status, .ok)
        XCTAssertTrue(check.detail.contains("claude=installed"))
        XCTAssertTrue(check.detail.contains("cursor=installed"))
        XCTAssertTrue(check.detail.contains("codex=unsupported"))
    }

    func testAggregateAbsentDegraded() {
        let inputs: [TeachingInstalledCheck.TargetInput] = [
            .init(hostId: "claude", source: .absent),
            .init(hostId: "cursor", source: .absent),
            .init(hostId: "codex", unsupported: true, unsupportedReason: "no global"),
        ]
        let check = TeachingInstalledCheck.check(inputs: inputs)
        XCTAssertEqual(check.status, .degraded)
        XCTAssertEqual(check.fixCommand, "alln bootstrap")
        XCTAssertTrue(check.detail.contains("absent"))
    }

    func testAggregateStaleAndModified() {
        let stale = TeachingSnippet.wrap(version: 0, hash: TeachingSnippet.contentHash)
        let modified = TeachingSnippet.wrap(hash: String(repeating: "00", count: 32))
        let inputs: [TeachingInstalledCheck.TargetInput] = [
            .init(hostId: "claude", source: .contents(stale)),
            .init(hostId: "cursor", source: .contents(modified)),
            .init(hostId: "codex", unsupported: true, unsupportedReason: "no global"),
        ]
        let check = TeachingInstalledCheck.check(inputs: inputs)
        XCTAssertEqual(check.status, .degraded)
        XCTAssertTrue(check.detail.contains("stale") || check.detail.contains("modified"))
    }

    func testProbeReadsTempDirNotRealHome() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teaching-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let claudeDir = root.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let claudeFile = claudeDir.appendingPathComponent("CLAUDE.md")
        try TeachingSnippet.wrap().write(to: claudeFile, atomically: true, encoding: .utf8)

        let inputs = TeachingInstalledCheck.defaultInputs(homeDirectory: root)
        let check = TeachingInstalledCheck.check(inputs: inputs)
        XCTAssertEqual(check.status, .degraded, "cursor still absent under temp home")
        XCTAssertTrue(check.detail.contains("claude=installed"))
        XCTAssertTrue(check.detail.contains("cursor=absent"))
        XCTAssertTrue(check.detail.contains("codex=unsupported"))
    }

    func testDoctorReportIncludesTeachingCheck() {
        let models = [Model(id: "m", displayName: "M", modelLabel: "m", driverId: "claude_code", role: .both)]
        let manifests = [DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI)]
        let records = [
            ToolProbeRecord(
                driverId: "claude_code",
                status: .installedNotProbed(version: "1"),
                version: "1",
                lastProbeAt: Date(timeIntervalSince1970: 0)
            ),
        ]
        var inputs = DoctorReport.Inputs(
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0",
            configDirWritable: true,
            runsDirWritable: true,
            full: false
        )
        inputs.teachingInputs = [
            .init(hostId: "claude", source: .contents(TeachingSnippet.wrap())),
            .init(hostId: "cursor", source: .contents(TeachingSnippet.wrap())),
            .init(hostId: "codex", unsupported: true, unsupportedReason: "no global"),
        ]
        let r = DoctorReport.build(models: models, manifests: manifests, records: records, inputs: inputs)
        let teaching = r.checks.first { $0.name == "teaching.installed" }
        XCTAssertEqual(teaching?.status, .ok)
    }

    func testDoctorReportDefaultsTeachingToNotChecked() {
        let models = [Model(id: "m", displayName: "M", modelLabel: "m", driverId: "claude_code", role: .both)]
        let manifests = [DriverManifest(id: "claude_code", displayName: "Claude Code", kind: .headlessCLI)]
        let records = [
            ToolProbeRecord(
                driverId: "claude_code",
                status: .installedNotProbed(version: "1"),
                version: "1",
                lastProbeAt: Date(timeIntervalSince1970: 0)
            ),
        ]
        let r = DoctorReport.build(
            models: models,
            manifests: manifests,
            records: records,
            inputs: .init(
                binaryVersion: "0.1.0",
                contractVersion: "1.0.0",
                configDirWritable: true,
                runsDirWritable: true,
                full: false
            )
        )
        XCTAssertEqual(r.checks.first { $0.name == "teaching.installed" }?.status, .notChecked)
    }
}
