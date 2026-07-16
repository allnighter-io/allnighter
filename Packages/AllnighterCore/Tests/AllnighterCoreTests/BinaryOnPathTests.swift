import XCTest
@testable import AllnighterCore

final class BinaryOnPathTests: XCTestCase {
    private var tempRoot: URL!
    private var fm: FileManager!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        fm = FileManager.default
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? fm.removeItem(at: tempRoot) }
    }

    func testOnPathOkWhenPATHResolvesToRunningBinary() throws {
        let binary = tempRoot.appendingPathComponent("alln-real")
        fm.createFile(atPath: binary.path, contents: Data("x".utf8))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let binDir = tempRoot.appendingPathComponent("bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: binDir.appendingPathComponent("alln").path, withDestinationPath: binary.path)

        let check = BinaryOnPath.check(
            runningBinary: binary.resolvingSymlinksInPath().path,
            pathEnvironment: binDir.path,
            fileManager: fm
        )
        XCTAssertEqual(check.status, .ok)
        XCTAssertEqual(check.name, BinaryOnPath.checkName)
    }

    func testMissingOnPathIsDegradedWithFixCommand() throws {
        let binary = tempRoot.appendingPathComponent("alln-real")
        fm.createFile(atPath: binary.path, contents: Data("x".utf8))
        let check = BinaryOnPath.check(
            runningBinary: binary.path,
            pathEnvironment: tempRoot.appendingPathComponent("empty-bin").path,
            fileManager: fm
        )
        XCTAssertEqual(check.status, .degraded)
        XCTAssertEqual(check.fixCommand, "alln install-cli")
    }

    func testNilPATHIsNotChecked() {
        let check = BinaryOnPath.check(runningBinary: "/tmp/alln", pathEnvironment: nil)
        XCTAssertEqual(check.status, .notChecked)
    }

    func testDoctorReportIncludesBinaryOnPathCheck() {
        let records = [
            ToolProbeRecord(driverId: "claude_code", status: .installedNotProbed(version: "1"), version: "1", lastProbeAt: Date()),
        ]
        let manifests = [DriverManifest(id: "claude_code", displayName: "Claude", kind: .headlessCLI)]
        let models = [Model(id: "m1", displayName: "M", modelLabel: "m", driverId: "claude_code", role: .both)]
        let inputs = DoctorReport.Inputs(
            binaryVersion: "0.1.0",
            contractVersion: "1.0.0",
            configDirWritable: true,
            runsDirWritable: true,
            full: false,
            runningBinaryPath: "/tmp/alln",
            pathEnvironment: "/tmp/bin"
        )
        let result = DoctorReport.build(models: models, manifests: manifests, records: records, inputs: inputs)
        XCTAssertNotNil(result.checks.first { $0.name == BinaryOnPath.checkName })
    }
}
