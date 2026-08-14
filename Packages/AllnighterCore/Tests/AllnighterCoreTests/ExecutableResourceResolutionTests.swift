import XCTest
import AgentOSCLI

final class ExecutableResourceResolutionTests: XCTestCase {
    func testCurrentExecutablePathIsAbsolute() throws {
        let path = try XCTUnwrap(ExecutableResource.currentExecutablePath())
        XCTAssertTrue(path.hasPrefix("/"), "got \(path)")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path))
    }

    func testOSPathWinsOverBareArgv0AfterChdirDecoy() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("argv0-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let probe = root.appendingPathComponent("ProbeScratch")
        let canonical = root.appendingPathComponent("share/bin")
        try fm.createDirectory(at: probe, withIntermediateDirectories: true)
        try fm.createDirectory(at: canonical, withIntermediateDirectories: true)
        fm.createFile(atPath: probe.appendingPathComponent("alln").path, contents: Data("decoy".utf8))
        let real = canonical.appendingPathComponent("alln")
        fm.createFile(atPath: real.path, contents: Data("real".utf8))

        let dir = ExecutableResource.directoryURL(
            osExecutablePath: real.path,
            argv0: "alln",
            pathEnvironment: probe.path,
            currentDirectory: probe.path,
            fileManager: fm
        )
        XCTAssertEqual(
            dir.resolvingSymlinksInPath().path,
            canonical.resolvingSymlinksInPath().path
        )
    }

    func testBareNameDoesNotFabricateCwdPath() {
        let fm = FileManager.default
        let cwd = fm.temporaryDirectory.appendingPathComponent("cwd-\(UUID().uuidString)")
        let dir = ExecutableResource.directoryURL(
            osExecutablePath: nil,
            argv0: "alln",
            pathEnvironment: nil,
            currentDirectory: cwd.path,
            fileManager: fm
        )
        XCTAssertNotEqual(dir.path, cwd.path)
        XCTAssertFalse(dir.path.hasPrefix(cwd.path + "/"))
    }

    func testBundledCatalogLoadsOnThisTestHost() throws {
        let catalog = try CatalogLoader.bundled()
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertFalse(catalog.models.isEmpty)
    }

    func testXctestHostWalksUpToSiblingSidecar() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("xctest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let debug = root.appendingPathComponent("debug")
        let macos = debug.appendingPathComponent("Host.xctest/Contents/MacOS")
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        let bundle = debug.appendingPathComponent(ExecutableResource.agentOSCLIBundleName)
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)

        let found = try XCTUnwrap(ExecutableResource.resolveBundleRoot(
            bundleName: ExecutableResource.agentOSCLIBundleName,
            executableDirectory: macos,
            fileManager: fm
        ))
        XCTAssertEqual(
            found.resolvingSymlinksInPath().path,
            bundle.resolvingSymlinksInPath().path
        )
    }

    func testInstalledCLISearchRootsDoNotIncludeDocuments() {
        let bin = URL(fileURLWithPath: "/Users/mike/.local/share/allnighter/bin")
        for root in ExecutableResource.sidecarSearchRoots(executableDirectory: bin) {
            XCTAssertFalse(root.path.contains("/Documents"))
            XCTAssertFalse(root.path.contains("/Desktop"))
            XCTAssertFalse(root.path.contains("/Downloads"))
        }
    }
}
