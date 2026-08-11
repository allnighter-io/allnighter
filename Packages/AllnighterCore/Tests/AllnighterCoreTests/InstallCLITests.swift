import XCTest
@testable import AllnighterCore

final class InstallCLITests: XCTestCase {
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

    private func makeBinary() throws -> String {
        let binary = tempRoot.appendingPathComponent("alln-bin")
        fm.createFile(atPath: binary.path, contents: Data("#!/bin/sh\necho ok\n".utf8))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        return binary.resolvingSymlinksInPath().path
    }

    private func defaultCanonicalInstall(
        homeDirectory: URL,
        fileManager: FileManager
    ) -> (URL, URL, String?, FileManager) -> Result<CanonicalCLIInstall.Report, CanonicalCLIInstall.Failure> {
        return { candidateURL, home, version, fm in
            let canonicalDir = CanonicalCLIInstall.canonicalDirectory(homeDirectory: home)
            try? fileManager.createDirectory(at: canonicalDir, withIntermediateDirectories: true)

            let canonicalURL = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: home)
            let resolvedCandidate = candidateURL.resolvingSymlinksInPath().standardizedFileURL.path
            let resolvedCanonical = canonicalURL.resolvingSymlinksInPath().standardizedFileURL.path

            if resolvedCandidate == resolvedCanonical {
                return .success(CanonicalCLIInstall.Report(canonicalURL: canonicalURL, alreadyCanonical: true, rollbackURL: nil))
            }

            guard let data = try? Data(contentsOf: candidateURL) else {
                return .failure(CanonicalCLIInstall.Failure(code: "SERVE_INSTALL_FAILED", message: "could not read candidate"))
            }
            let tempURL = canonicalDir.appendingPathComponent(".alln.staging.\(UUID().uuidString)")
            try? data.write(to: tempURL)
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)

            let oldExists = fileManager.fileExists(atPath: canonicalURL.path)
            let rollbackURL = CanonicalCLIInstall.rollbackBinaryURL(homeDirectory: home)
            if oldExists {
                try? fileManager.removeItem(at: rollbackURL)
                try? fileManager.moveItem(at: canonicalURL, to: rollbackURL)
            }

            try? fileManager.moveItem(at: tempURL, to: canonicalURL)

            let rb: URL? = oldExists ? rollbackURL : nil
            return .success(CanonicalCLIInstall.Report(canonicalURL: canonicalURL, alreadyCanonical: false, rollbackURL: rb))
        }
    }

    private func request(
        binary: String,
        installDir: String,
        printOnly: Bool = false,
        pathEnvironment: String? = nil,
        canonicalInstall: ((URL, URL, String?, FileManager) -> Result<CanonicalCLIInstall.Report, CanonicalCLIInstall.Failure>)? = nil,
        version: String? = nil
    ) -> InstallCLI.Request {
        InstallCLI.Request(
            argv0: binary,
            pathOverride: installDir,
            printOnly: printOnly,
            pathEnvironment: pathEnvironment,
            homeDirectory: tempRoot,
            fileManager: fm,
            canonicalInstall: canonicalInstall ?? defaultCanonicalInstall(homeDirectory: tempRoot, fileManager: fm),
            version: version
        )
    }

    func testInstallCreatesSymlinkToCanonicalPath() throws {
        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("bin").path
        let outcome = InstallCLI.run(request(binary: binary, installDir: installDir))
        guard case .installed(let json) = outcome else {
            return XCTFail("expected installed, got \(outcome)")
        }
        XCTAssertEqual(json.action, .installed)
        XCTAssertEqual(json.schemaVersion, 2)

        let canonicalPath = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot).path
        XCTAssertEqual(json.target, canonicalPath)
        XCTAssertEqual(json.canonicalPath, canonicalPath)
        XCTAssertEqual(json.target, json.canonicalPath)

        let link = installDir + "/alln"
        XCTAssertTrue(fm.fileExists(atPath: link))
        XCTAssertTrue(InstallCLI.sameExecutable(try fm.destinationOfSymbolicLink(atPath: link), canonicalPath))
    }

    func testSecondRunIsAlreadyInstalled() throws {
        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("bin").path
        _ = InstallCLI.run(request(binary: binary, installDir: installDir))
        let outcome = InstallCLI.run(request(binary: binary, installDir: installDir))
        guard case .installed(let json) = outcome else {
            return XCTFail("expected installed, got \(outcome)")
        }
        XCTAssertEqual(json.action, .alreadyInstalled)
        let canonicalPath = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot).path
        XCTAssertEqual(json.target, canonicalPath)
        let line = InstallCLI.humanLine(json)
        XCTAssertTrue(line.contains("already installed"))
        XCTAssertTrue(line.contains("alln menu --json"))
        XCTAssertTrue(line.contains("benchTally.nextAction"))
        XCTAssertTrue(line.contains("Canonical binary: \(canonicalPath)"))
    }

    func testRepairsStaleSymlinkToCanonicalPath() throws {
        let binary = try makeBinary()
        let stale = tempRoot.appendingPathComponent("stale-bin")
        fm.createFile(atPath: stale.path, contents: Data("x".utf8))
        let installDir = tempRoot.appendingPathComponent("bin").path
        try fm.createDirectory(atPath: installDir, withIntermediateDirectories: true)
        let link = installDir + "/alln"
        try fm.createSymbolicLink(atPath: link, withDestinationPath: stale.path)

        let outcome = InstallCLI.run(request(binary: binary, installDir: installDir))
        guard case .installed(let json) = outcome else {
            return XCTFail("expected installed, got \(outcome)")
        }
        XCTAssertEqual(json.action, .repaired)

        let canonicalPath = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot).path
        XCTAssertEqual(json.target, canonicalPath)
        XCTAssertTrue(InstallCLI.sameExecutable(try fm.destinationOfSymbolicLink(atPath: link), canonicalPath))
    }

    func testPrintOnlyPerformsNoInstall() throws {
        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("bin").path
        let outcome = InstallCLI.run(request(binary: binary, installDir: installDir, printOnly: true))
        guard case .printed(let json) = outcome else {
            return XCTFail("expected printed, got \(outcome)")
        }
        XCTAssertEqual(json.action, .printed)
        XCTAssertFalse(fm.fileExists(atPath: installDir + "/alln"))
        let canonicalPath = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot).path
        XCTAssertFalse(fm.fileExists(atPath: canonicalPath))
    }

    func testUnwritableDirectoryReturnsCatalogError() throws {
        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("locked").path
        try fm.createDirectory(atPath: installDir, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: installDir)

        let outcome = InstallCLI.run(request(binary: binary, installDir: installDir))
        guard case .failed(let code, let message) = outcome else {
            return XCTFail("expected failure, got \(outcome)")
        }
        XCTAssertEqual(code, "INSTALL_CLI_TARGET_UNWRITABLE")
        XCTAssertTrue(message.contains("--path"))
    }

    func testJSONEnvelopeShapeV2() throws {
        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("bin").path
        let outcome = InstallCLI.run(request(binary: binary, installDir: installDir))
        guard case .installed(let json) = outcome else {
            return XCTFail("expected installed")
        }
        let data = try CoreJSON.encode(json)
        let decoded = try CoreJSON.decode(InstallCLI.JSON.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.action, .installed)
        XCTAssertEqual(decoded.path, installDir + "/alln")
        let canonicalPath = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot).path
        XCTAssertEqual(decoded.target, canonicalPath)
        XCTAssertEqual(decoded.canonicalPath, canonicalPath)
        XCTAssertNil(decoded.rollbackPath)
        XCTAssertNil(decoded.codeIdentity)
        XCTAssertNil(decoded.version)
    }

    func testInstallRefusalPropagatesAsFailed() throws {
        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("bin").path

        let mockInstall: (URL, URL, String?, FileManager) -> Result<CanonicalCLIInstall.Report, CanonicalCLIInstall.Failure> = { _, _, _, _ in
            .failure(CanonicalCLIInstall.Failure(code: "INSTALL_CANDIDATE_REFUSED", message: "candidate is inside an .app bundle"))
        }
        let outcome = InstallCLI.run(request(binary: binary, installDir: installDir, canonicalInstall: mockInstall))
        guard case .failed(let code, let message) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(code, "INSTALL_CANDIDATE_REFUSED")
        XCTAssertTrue(message.contains(".app bundle"))
    }

    func testServeInstallFailedPropagatesAsFailed() throws {
        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("bin").path

        let mockInstall: (URL, URL, String?, FileManager) -> Result<CanonicalCLIInstall.Report, CanonicalCLIInstall.Failure> = { _, _, _, _ in
            .failure(CanonicalCLIInstall.Failure(code: "SERVE_INSTALL_FAILED", message: "could not write temp binary"))
        }
        let outcome = InstallCLI.run(request(binary: binary, installDir: installDir, canonicalInstall: mockInstall))
        guard case .failed(let code, _) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(code, "SERVE_INSTALL_FAILED")
    }

    func testServeRollbackFailedRecoveryMessage() throws {
        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("bin").path

        let mockInstall: (URL, URL, String?, FileManager) -> Result<CanonicalCLIInstall.Report, CanonicalCLIInstall.Failure> = { _, home, _, _ in
            let errMsg = "rename to /tmp/canonical/alln failed: no space; rollback restore also failed at /tmp/canonical/alln.rollback: no device"
            return .failure(CanonicalCLIInstall.Failure(code: "SERVE_ROLLBACK_FAILED", message: errMsg))
        }
        let outcome = InstallCLI.run(request(binary: binary, installDir: installDir, canonicalInstall: mockInstall))
        guard case .failed(let code, let message) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(code, "SERVE_ROLLBACK_FAILED")
        XCTAssertTrue(message.contains("To recover:"))
        XCTAssertTrue(message.contains("cp \""))

        let afterRecovery = message.components(separatedBy: "To recover:").last ?? ""
        let recoveryLines = afterRecovery.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        let firstRecoveryLine = recoveryLines.first ?? ""
        XCTAssertFalse(firstRecoveryLine.contains("alln "), "first recovery step must not require alln on PATH, got: \(firstRecoveryLine)")
        let joinedRecovery = recoveryLines.joined(separator: "\n")
        XCTAssertTrue(joinedRecovery.contains("cold-start faucet"), "second option must mention cold-start faucet")
    }

    func testCanonicalBinaryAlreadyCanonicalStillGuaranteesSymlink() throws {
        let binary = try makeBinary()
        let canonicalDir = CanonicalCLIInstall.canonicalDirectory(homeDirectory: tempRoot)
        try fm.createDirectory(at: canonicalDir, withIntermediateDirectories: true)
        let canonicalURL = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot)
        try fm.copyItem(atPath: binary, toPath: canonicalURL.path)

        let installDir = tempRoot.appendingPathComponent("bin").path
        let outcome = InstallCLI.run(request(binary: canonicalURL.path, installDir: installDir))
        guard case .installed(let json) = outcome else {
            return XCTFail("expected installed, got \(outcome)")
        }
        XCTAssertEqual(json.action, .installed)
        XCTAssertEqual(json.canonicalPath, json.target)

        let link = installDir + "/alln"
        XCTAssertTrue(fm.fileExists(atPath: link))
        XCTAssertTrue(InstallCLI.sameExecutable(try fm.destinationOfSymbolicLink(atPath: link), canonicalURL.path))
    }

    func testStaleSymlinkPointingAtOldBuildRepairedToCanonical() throws {
        let binary = try makeBinary()
        let targetDir = CanonicalCLIInstall.canonicalDirectory(homeDirectory: tempRoot)
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let canonicalTarget = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot)

        let installDir = tempRoot.appendingPathComponent("bin").path
        try fm.createDirectory(atPath: installDir, withIntermediateDirectories: true)
        let link = installDir + "/alln"

        let staleTarget = tempRoot.appendingPathComponent("old-build-bin")
        fm.createFile(atPath: staleTarget.path, contents: Data("old".utf8))
        try fm.createSymbolicLink(atPath: link, withDestinationPath: staleTarget.path)

        let outcome = InstallCLI.run(request(binary: binary, installDir: installDir))
        guard case .installed(let json) = outcome else {
            return XCTFail("expected installed, got \(outcome)")
        }
        XCTAssertEqual(json.action, .repaired)
        XCTAssertTrue(fm.fileExists(atPath: canonicalTarget.path))
        XCTAssertTrue(InstallCLI.sameExecutable(try fm.destinationOfSymbolicLink(atPath: link), canonicalTarget.path))
    }

    func testResolvedRunningBinaryAbsolutePath() throws {
        let binary = try makeBinary()
        let resolved = InstallCLI.resolvedRunningBinary(argv0: binary, fileManager: fm)
        XCTAssertEqual(resolved, binary)
    }

    func testResolvedRunningBinaryRelativeWithSlashUsesCwd() throws {
        let binary = try makeBinary()
        let cwd = tempRoot.path
        let relative = "subdir/alln-bin"
        let subdir = tempRoot.appendingPathComponent("subdir")
        try fm.createDirectory(at: subdir, withIntermediateDirectories: true)
        try fm.copyItem(atPath: binary, toPath: subdir.appendingPathComponent("alln-bin").path)

        let resolved = InstallCLI.resolvedRunningBinary(
            argv0: relative,
            currentDirectory: cwd,
            fileManager: fm
        )
        XCTAssertEqual(resolved, subdir.appendingPathComponent("alln-bin").resolvingSymlinksInPath().path)
    }

    func testResolvedRunningBinaryBareNameSearchesPATH() throws {
        let binary = try makeBinary()
        let binDir = tempRoot.appendingPathComponent("bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: binDir.appendingPathComponent("alln").path,
            withDestinationPath: binary
        )

        let resolved = InstallCLI.resolvedRunningBinary(
            argv0: "alln",
            pathEnvironment: binDir.path,
            currentDirectory: tempRoot.appendingPathComponent("elsewhere").path,
            fileManager: fm
        )
        XCTAssertEqual(resolved, binary)
    }

    func testBareNameDoesNotFabricateCwdPath() throws {
        let elsewhere = tempRoot.appendingPathComponent("websitemd.studio")
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let fake = elsewhere.appendingPathComponent("alln")
        fm.createFile(atPath: fake.path, contents: Data("not the real binary".utf8))

        let resolved = InstallCLI.resolvedRunningBinary(
            argv0: "alln",
            pathEnvironment: tempRoot.appendingPathComponent("empty-bin").path,
            currentDirectory: elsewhere.path,
            fileManager: fm
        )
        XCTAssertNil(resolved, "bare name must not resolve to cwd/alln when PATH misses")
    }

    func testDefaultInstallDirectoryReturnsLocalBin() throws {
        let fm = FileManager.default
        let dir = InstallCLI.defaultInstallDirectory(homeDirectory: tempRoot, fileManager: fm)
        XCTAssertTrue(dir.hasSuffix(".local/bin"), "default must be ~/.local/bin, got '\(dir)'")
    }

    func testDefaultInstallDirectoryIgnoresUsrLocalBinWritability() throws {
        let homeDir = tempRoot.appendingPathComponent("home")
        try fm.createDirectory(at: homeDir, withIntermediateDirectories: true)
        let dir = InstallCLI.defaultInstallDirectory(homeDirectory: homeDir, fileManager: fm)
        XCTAssertFalse(dir.contains("/usr/local/bin"), "must not return /usr/local/bin even if writable")
        XCTAssertEqual(dir, homeDir.appendingPathComponent(".local/bin").path)
    }

    func testBootstrapLiveContextBareNameOnPATH() throws {
        let binary = try makeBinary()
        let binDir = tempRoot.appendingPathComponent("bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: binDir.appendingPathComponent("alln").path,
            withDestinationPath: binary
        )
        let cwd = tempRoot.appendingPathComponent("other-cwd")
        try fm.createDirectory(at: cwd, withIntermediateDirectories: true)

        let ctx = Bootstrap.liveContext(
            argv0: "alln",
            pathEnvironment: binDir.path,
            fileManager: fm
        )
        XCTAssertEqual(ctx.binaryPath, binary)
        XCTAssertTrue(ctx.onPath)
    }

    func testResolvedHomeDirectoryWithExistingAbsDirWins() throws {
        let workHome = tempRoot.appendingPathComponent("work-home")
        try fm.createDirectory(at: workHome, withIntermediateDirectories: true)
        let result = InstallCLI.resolvedHomeDirectory(
            environment: ["HOME": workHome.path],
            fileManager: fm
        )
        XCTAssertEqual(result.path, workHome.path)
    }

    func testResolvedHomeDirectoryUnsetFallsBack() throws {
        let result = InstallCLI.resolvedHomeDirectory(
            environment: [:],
            fileManager: fm
        )
        XCTAssertEqual(result.path, fm.homeDirectoryForCurrentUser.path)
    }

    func testResolvedHomeDirectoryEmptyFallsBack() throws {
        let result = InstallCLI.resolvedHomeDirectory(
            environment: ["HOME": ""],
            fileManager: fm
        )
        XCTAssertEqual(result.path, fm.homeDirectoryForCurrentUser.path)
    }

    func testResolvedHomeDirectoryRelativeFallsBack() throws {
        let relativeHome = tempRoot.appendingPathComponent("rel-home")
        try fm.createDirectory(at: relativeHome, withIntermediateDirectories: true)
        let result = InstallCLI.resolvedHomeDirectory(
            environment: ["HOME": "rel-home"],
            fileManager: fm
        )
        XCTAssertEqual(result.path, fm.homeDirectoryForCurrentUser.path)
    }

    func testResolvedHomeDirectoryNonexistentFallsBack() throws {
        let result = InstallCLI.resolvedHomeDirectory(
            environment: ["HOME": "/nonexistent/deadbeef"],
            fileManager: fm
        )
        XCTAssertEqual(result.path, fm.homeDirectoryForCurrentUser.path)
    }

    func testInstallWithScratchHomePlacesCanonicalUnderScratch() throws {
        let scratchHome = tempRoot.appendingPathComponent("scratch-home")
        try fm.createDirectory(at: scratchHome, withIntermediateDirectories: true)

        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("bin").path

        let request = InstallCLI.Request(
            argv0: binary,
            pathOverride: installDir,
            printOnly: false,
            pathEnvironment: nil,
            homeDirectory: URL(fileURLWithPath: scratchHome.path),
            fileManager: fm,
            canonicalInstall: defaultCanonicalInstall(homeDirectory: URL(fileURLWithPath: scratchHome.path), fileManager: fm)
        )

        let outcome = InstallCLI.run(request)
        guard case .installed(let json) = outcome else {
            return XCTFail("expected installed, got \(outcome)")
        }
        XCTAssertEqual(json.action, .installed)

        let expectedCanonical = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: URL(fileURLWithPath: scratchHome.path)).path
        XCTAssertEqual(json.target, expectedCanonical)
        XCTAssertTrue(fm.fileExists(atPath: expectedCanonical), "canonical binary must exist at \(expectedCanonical)")
    }

    // MARK: - beforeBytesChange wiring (ASR-S02d Step 4)

    func testBeforeBytesChangeWiredThroughCanonicalInstall() throws {
        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("bin").path

        var beforeBytesCalled = false

        let mockInstall: (URL, URL, String?, FileManager) -> Result<CanonicalCLIInstall.Report, CanonicalCLIInstall.Failure> = { candidate, home, _, fm in
            let result = CanonicalCLIInstall.install(
                candidateURL: candidate,
                homeDirectory: home,
                fileManager: fm,
                beforeBytesChange: {
                    beforeBytesCalled = true
                    return .success(())
                }
            )
            return result
        }

        let outcome = InstallCLI.run(request(
            binary: binary,
            installDir: installDir,
            canonicalInstall: mockInstall
        ))
        guard case .installed = outcome else {
            return XCTFail("expected installed, got \(outcome)")
        }
        XCTAssertTrue(beforeBytesCalled, "beforeBytesChange must be called through canonicalInstall wiring")
    }

    func testBeforeBytesChangeFailureAbortsInstallBytesUnchanged() throws {
        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("bin").path
        let canonicalURL = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: tempRoot)

        var beforeBytesCalled = false

        let mockInstall: (URL, URL, String?, FileManager) -> Result<CanonicalCLIInstall.Report, CanonicalCLIInstall.Failure> = { candidate, home, _, fm in
            let result = CanonicalCLIInstall.install(
                candidateURL: candidate,
                homeDirectory: home,
                fileManager: fm,
                beforeBytesChange: {
                    beforeBytesCalled = true
                    return .failure(CanonicalCLIInstall.Failure(code: "SERVE_INSTALL_FAILED", message: "hook abort"))
                }
            )
            return result
        }

        let outcome = InstallCLI.run(request(
            binary: binary,
            installDir: installDir,
            canonicalInstall: mockInstall
        ))
        guard case .failed(let code, _) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(code, "SERVE_INSTALL_FAILED")
        XCTAssertTrue(beforeBytesCalled)
        XCTAssertFalse(fm.fileExists(atPath: canonicalURL.path), "canonical bytes must not exist when beforeBytesChange fails")
    }
}
