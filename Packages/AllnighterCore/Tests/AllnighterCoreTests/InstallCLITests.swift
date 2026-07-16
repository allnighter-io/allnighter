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

    private func request(
        binary: String,
        installDir: String,
        printOnly: Bool = false,
        pathEnvironment: String? = nil
    ) -> InstallCLI.Request {
        InstallCLI.Request(
            argv0: binary,
            pathOverride: installDir,
            printOnly: printOnly,
            pathEnvironment: pathEnvironment,
            homeDirectory: tempRoot,
            fileManager: fm
        )
    }

    func testInstallCreatesSymlink() throws {
        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("bin").path
        let outcome = InstallCLI.run(request(binary: binary, installDir: installDir))
        guard case .installed(let json) = outcome else {
            return XCTFail("expected installed, got \(outcome)")
        }
        XCTAssertEqual(json.action, .installed)
        XCTAssertEqual(json.target, binary)
        let link = installDir + "/alln"
        XCTAssertTrue(fm.fileExists(atPath: link))
        XCTAssertTrue(InstallCLI.sameExecutable(try fm.destinationOfSymbolicLink(atPath: link), binary))
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
    }

    func testRepairsStaleSymlink() throws {
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
        XCTAssertTrue(InstallCLI.sameExecutable(try fm.destinationOfSymbolicLink(atPath: link), binary))
    }

    func testPrintOnlyPreservesLegacyBehavior() throws {
        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("bin").path
        let outcome = InstallCLI.run(request(binary: binary, installDir: installDir, printOnly: true))
        guard case .printed(let json) = outcome else {
            return XCTFail("expected printed, got \(outcome)")
        }
        XCTAssertEqual(json.action, .printed)
        XCTAssertFalse(fm.fileExists(atPath: installDir + "/alln"))
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

    func testJSONEnvelopeShape() throws {
        let binary = try makeBinary()
        let installDir = tempRoot.appendingPathComponent("bin").path
        let outcome = InstallCLI.run(request(binary: binary, installDir: installDir))
        guard case .installed(let json) = outcome else {
            return XCTFail("expected installed")
        }
        let data = try CoreJSON.encode(json)
        let decoded = try CoreJSON.decode(InstallCLI.JSON.self, from: data)
        XCTAssertEqual(decoded.action, .installed)
        XCTAssertEqual(decoded.path, installDir + "/alln")
        XCTAssertEqual(decoded.target, binary)
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
}
