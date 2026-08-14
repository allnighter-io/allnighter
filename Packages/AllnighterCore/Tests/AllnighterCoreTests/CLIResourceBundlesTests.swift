import XCTest
@testable import AllnighterCore

final class CLIResourceBundlesTests: XCTestCase {
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

    private func makeBundle(named name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        fm.createFile(atPath: url.appendingPathComponent("marker").path, contents: Data(name.utf8))
        return url
    }

    func testSiblingBundlesIgnoresFilesAndFindsDirectories() throws {
        let binDir = tempRoot.appendingPathComponent("stage")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        let binary = binDir.appendingPathComponent("alln")
        fm.createFile(atPath: binary.path, contents: Data("x".utf8))
        _ = try makeBundle(named: "AgentOS_AgentOSCLI.bundle", in: binDir)
        fm.createFile(atPath: binDir.appendingPathComponent("notes.bundle").path, contents: Data("file".utf8))

        let found = CLIResourceBundles.siblingBundles(nextTo: binary, fileManager: fm)
        XCTAssertEqual(found.map(\.lastPathComponent), ["AgentOS_AgentOSCLI.bundle"])
    }

    func testCopySiblingsReplacesDestination() throws {
        let srcDir = tempRoot.appendingPathComponent("src")
        let dstDir = tempRoot.appendingPathComponent("dst")
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        let binary = srcDir.appendingPathComponent("alln")
        fm.createFile(atPath: binary.path, contents: Data("x".utf8))
        _ = try makeBundle(named: "AgentOS_AgentOSCLI.bundle", in: srcDir)

        let stale = dstDir.appendingPathComponent("AgentOS_AgentOSCLI.bundle")
        try fm.createDirectory(at: stale, withIntermediateDirectories: true)
        fm.createFile(atPath: stale.appendingPathComponent("old").path, contents: Data("old".utf8))

        try CLIResourceBundles.copySiblings(from: binary, into: dstDir, fileManager: fm)
        XCTAssertTrue(fm.fileExists(atPath: dstDir.appendingPathComponent("AgentOS_AgentOSCLI.bundle/marker").path))
        XCTAssertFalse(fm.fileExists(atPath: stale.appendingPathComponent("old").path))
    }

    func testLinkSiblingsPointsAtCanonicalBundles() throws {
        let canonical = tempRoot.appendingPathComponent("canonical")
        let pathDir = tempRoot.appendingPathComponent("bin")
        try fm.createDirectory(at: canonical, withIntermediateDirectories: true)
        try fm.createDirectory(at: pathDir, withIntermediateDirectories: true)
        _ = try makeBundle(named: "AllnighterCore_AllnighterCore.bundle", in: canonical)

        try CLIResourceBundles.linkSiblings(from: canonical, into: pathDir, fileManager: fm)
        let link = pathDir.appendingPathComponent("AllnighterCore_AllnighterCore.bundle")
        let dest = try fm.destinationOfSymbolicLink(atPath: link.path)
        XCTAssertEqual(
            URL(fileURLWithPath: dest).resolvingSymlinksInPath().path,
            canonical.appendingPathComponent("AllnighterCore_AllnighterCore.bundle").path
        )
    }

    func testRequiredNamesCoverTheProductionCrash() {
        XCTAssertEqual(
            CLIResourceBundles.requiredNames,
            ["AgentOS_AgentOSCLI.bundle", "AllnighterCore_AllnighterCore.bundle"]
        )
    }
}
