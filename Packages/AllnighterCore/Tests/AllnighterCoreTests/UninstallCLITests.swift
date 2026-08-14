import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

final class UninstallCLITests: XCTestCase {
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

    private func request(
        json: Bool = false,
        yes: Bool = false,
        effectiveHome: URL? = nil,
        realHome: URL? = nil,
        disableServe: (@Sendable () async -> UninstallCLI.DisableServeReport)? = nil,
        readConfirmation: (@Sendable () -> Bool)? = nil
    ) -> UninstallCLI.Request {
        let home = tempRoot!
        let fileManager = fm!
        let defaultDisable: @Sendable () async -> UninstallCLI.DisableServeReport = {
            let plistURL = UninstallCLI.launchAgentPlistURL(homeDirectory: home)
            try? FileManager.default.removeItem(at: plistURL)
            return UninstallCLI.DisableServeReport(succeeded: true, detail: "serve disabled for test")
        }
        return UninstallCLI.Request(
            json: json,
            yes: yes,
            homeDirectory: home,
            effectiveHomeDirectory: effectiveHome ?? home,
            realHomeDirectory: realHome ?? home,
            fileManager: fileManager,
            disableServe: disableServe ?? defaultDisable,
            readConfirmation: readConfirmation ?? { true }
        )
    }

    private func installFixture(
        symlinkTarget: String? = nil,
        includeUserData: Bool = true
    ) throws {
        let canonicalDir = CanonicalCLIInstall.canonicalDirectory(homeDirectory: tempRoot)
        try fm.createDirectory(at: canonicalDir, withIntermediateDirectories: true)
        let canonicalURL = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot)
        fm.createFile(atPath: canonicalURL.path, contents: Data("canonical".utf8))

        let rollbackURL = CanonicalCLIInstall.rollbackBinaryURL(homeDirectory: tempRoot)
        fm.createFile(atPath: rollbackURL.path, contents: Data("rollback".utf8))

        let symlinkURL = CanonicalCLIInstall.pathSymlinkURL(homeDirectory: tempRoot)
        try fm.createDirectory(at: symlinkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = symlinkTarget ?? canonicalURL.path
        try fm.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: target)

        let agentBundle = canonicalDir.appendingPathComponent("AgentOS_AgentOSCLI.bundle")
        try fm.createDirectory(at: agentBundle, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: symlinkURL.deletingLastPathComponent().appendingPathComponent("AgentOS_AgentOSCLI.bundle").path,
            withDestinationPath: agentBundle.path
        )

        let plistURL = UninstallCLI.launchAgentPlistURL(homeDirectory: tempRoot)
        try fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: plistURL.path, contents: Data("<plist/>".utf8))

        let desiredURL = UninstallCLI.desiredStateURL(homeDirectory: tempRoot)
        try fm.createDirectory(at: desiredURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: desiredURL.path, contents: Data("{\"state\":\"enabled\"}".utf8))

        let runtimeURL = UninstallCLI.runtimeReceiptURL(homeDirectory: tempRoot)
        try fm.createDirectory(at: runtimeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: runtimeURL.path, contents: Data("{\"daemonId\":\"d1\"}".utf8))

        let logDir = UninstallCLI.serveLogDirectory(homeDirectory: tempRoot)
        try fm.createDirectory(at: logDir, withIntermediateDirectories: true)
        fm.createFile(atPath: logDir.appendingPathComponent("alln-serve-stdout.log").path, contents: Data("out".utf8))
        fm.createFile(atPath: logDir.appendingPathComponent("serve.log.1").path, contents: Data("rot".utf8))

        if includeUserData {
            let runsDir = tempRoot
                .appendingPathComponent("Library/Application Support/Allnighter/Runs", isDirectory: true)
            try fm.createDirectory(at: runsDir, withIntermediateDirectories: true)
            fm.createFile(atPath: runsDir.appendingPathComponent("run-1.json").path, contents: Data("{\"id\":\"run-1\"}".utf8))
        }
    }

    func testJSONWithoutYesRefuses() async {
        let outcome = await UninstallCLI.run(request(json: true, yes: false))
        guard case .refused(let code, let message) = outcome else {
            return XCTFail("expected refused, got \(outcome)")
        }
        XCTAssertEqual(code, "CLI_USAGE_ERROR")
        XCTAssertTrue(message.contains("--json"))
        XCTAssertTrue(message.contains("--yes"))
    }

    func testForeignHomeRefusesBeforeMutation() async throws {
        try installFixture()
        let foreignHome = tempRoot.appendingPathComponent("foreign")
        try fm.createDirectory(at: foreignHome, withIntermediateDirectories: true)

        let outcome = await UninstallCLI.run(request(
            yes: true,
            effectiveHome: foreignHome,
            realHome: tempRoot
        ))

        guard case .refused(let code, let message) = outcome else {
            return XCTFail("expected refused, got \(outcome)")
        }
        XCTAssertEqual(code, "SERVE_FOREIGN_HOME")
        XCTAssertTrue(message.contains(foreignHome.path))
        XCTAssertTrue(message.contains(tempRoot.path))
        XCTAssertTrue(fm.fileExists(atPath: CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot).path))
    }

    func testConfirmationRequiredWithoutYes() async throws {
        try installFixture()
        let outcome = await UninstallCLI.run(request(
            yes: false,
            readConfirmation: { false }
        ))
        guard case .refused(let code, _) = outcome else {
            return XCTFail("expected refused, got \(outcome)")
        }
        XCTAssertEqual(code, "CLI_USAGE_ERROR")
        XCTAssertTrue(fm.fileExists(atPath: CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot).path))
    }

    func testDisableFailureStopsBeforeArtifactDeletion() async throws {
        try installFixture()
        let outcome = await UninstallCLI.run(request(
            yes: true,
            disableServe: {
                UninstallCLI.DisableServeReport(
                    succeeded: false,
                    detail: "bootout failed",
                    errorCode: "SERVE_INSTALL_FAILED"
                )
            }
        ))
        guard case .failed(let code, let message) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(code, "SERVE_INSTALL_FAILED")
        XCTAssertTrue(message.contains("bootout failed"))
        XCTAssertTrue(fm.fileExists(atPath: CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot).path))
        XCTAssertTrue(fm.fileExists(atPath: UninstallCLI.desiredStateURL(homeDirectory: tempRoot).path))
    }

    func testSuccessfulUninstallRemovesInstallArtifactsAndRetainsUserData() async throws {
        try installFixture()
        let outcome = await UninstallCLI.run(request(yes: true))
        guard case .completed(let json) = outcome else {
            return XCTFail("expected completed, got \(outcome)")
        }
        XCTAssertTrue(json.success)
        XCTAssertEqual(json.userDataRetainedPath, UninstallCLI.userDataRetainedDirectory(homeDirectory: tempRoot).path)

        XCTAssertFalse(fm.fileExists(atPath: CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot).path))
        XCTAssertFalse(fm.fileExists(atPath: CanonicalCLIInstall.rollbackBinaryURL(homeDirectory: tempRoot).path))
        XCTAssertFalse(fm.fileExists(atPath: CanonicalCLIInstall.pathSymlinkURL(homeDirectory: tempRoot).path))
        XCTAssertFalse(fm.fileExists(atPath: CanonicalCLIInstall.canonicalDirectory(homeDirectory: tempRoot)
            .appendingPathComponent("AgentOS_AgentOSCLI.bundle").path))
        XCTAssertFalse(fm.fileExists(atPath: CanonicalCLIInstall.pathSymlinkURL(homeDirectory: tempRoot)
            .deletingLastPathComponent()
            .appendingPathComponent("AgentOS_AgentOSCLI.bundle").path))
        XCTAssertFalse(fm.fileExists(atPath: UninstallCLI.desiredStateURL(homeDirectory: tempRoot).path))
        XCTAssertFalse(fm.fileExists(atPath: UninstallCLI.runtimeReceiptURL(homeDirectory: tempRoot).path))
        XCTAssertFalse(fm.fileExists(atPath: UninstallCLI.serveLogDirectory(homeDirectory: tempRoot)
            .appendingPathComponent("alln-serve-stdout.log").path))

        let runsFile = tempRoot
            .appendingPathComponent("Library/Application Support/Allnighter/Runs/run-1.json")
        XCTAssertTrue(fm.fileExists(atPath: runsFile.path))

        XCTAssertTrue(json.artifacts.contains { $0.name == "canonical-binary" && $0.disposition == .removed })
        XCTAssertTrue(json.artifacts.contains { $0.name == "canonical-rollback" && $0.disposition == .removed })
        XCTAssertTrue(json.artifacts.contains { $0.name == "path-symlink" && $0.disposition == .removed })
        XCTAssertTrue(json.artifacts.contains {
            $0.name == "canonical-bundle:AgentOS_AgentOSCLI.bundle" && $0.disposition == .removed
        })
        XCTAssertTrue(json.artifacts.contains {
            $0.name == "path-bundle:AgentOS_AgentOSCLI.bundle" && $0.disposition == .removed
        })
        XCTAssertTrue(json.artifacts.contains { $0.name == "desired-state" && $0.disposition == .removed })
        XCTAssertTrue(json.artifacts.contains { $0.name == "runtime-receipt" && $0.disposition == .removed })
        XCTAssertTrue(json.artifacts.contains { $0.name == "launchagent-plist" && $0.disposition == .removed })

        let human = UninstallCLI.humanReport(json)
        XCTAssertTrue(human.contains("user data retained at"))
        XCTAssertTrue(human.contains("canonical-binary: removed"))
    }

    func testForeignHomeRefusedViaInjectedDisableStillReportsCode() async {
        let outcome = await UninstallCLI.run(request(
            yes: true,
            disableServe: {
                UninstallCLI.DisableServeReport(
                    succeeded: false,
                    detail: "SERVE_FOREIGN_HOME: refusing serve lifecycle",
                    errorCode: "SERVE_FOREIGN_HOME"
                )
            }
        ))
        guard case .failed(let code, _) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(code, "SERVE_FOREIGN_HOME")
    }

    func testPathSymlinkKeptWhenPointingElsewhere() async throws {
        let otherBinary = tempRoot.appendingPathComponent("other-alln")
        fm.createFile(atPath: otherBinary.path, contents: Data("other".utf8))
        try installFixture(symlinkTarget: otherBinary.path)

        let outcome = await UninstallCLI.run(request(yes: true))
        guard case .completed(let json) = outcome else {
            return XCTFail("expected completed, got \(outcome)")
        }
        XCTAssertTrue(json.success)
        XCTAssertTrue(fm.fileExists(atPath: CanonicalCLIInstall.pathSymlinkURL(homeDirectory: tempRoot).path))

        let symlinkReport = json.artifacts.first { $0.name == "path-symlink" }
        XCTAssertEqual(symlinkReport?.disposition, .kept)
        XCTAssertTrue(symlinkReport?.reason?.contains("resolves elsewhere") == true)
    }

    func testAbsentArtifactsReportedAbsent() async throws {
        let outcome = await UninstallCLI.run(request(yes: true))
        guard case .completed(let json) = outcome else {
            return XCTFail("expected completed, got \(outcome)")
        }
        XCTAssertTrue(json.success)
        XCTAssertTrue(json.artifacts.contains { $0.name == "canonical-binary" && $0.disposition == .absent })
        XCTAssertTrue(json.artifacts.contains { $0.name == "launchagent-plist" && $0.disposition == .absent })
    }

    func testPlistStillPresentAfterDisableStopsBeforeArtifactDeletion() async throws {
        try installFixture()
        let plistURL = UninstallCLI.launchAgentPlistURL(homeDirectory: tempRoot)
        let canonicalURL = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot)
        let outcome = await UninstallCLI.run(request(
            yes: true,
            disableServe: {
                UninstallCLI.DisableServeReport(succeeded: true, detail: "disable claimed success")
            }
        ))
        guard case .failed(let code, let message) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(code, "SERVE_INSTALL_FAILED")
        XCTAssertTrue(message.contains("plist still present"))
        XCTAssertTrue(fm.fileExists(atPath: plistURL.path))
        XCTAssertTrue(fm.fileExists(atPath: canonicalURL.path))
    }
}
