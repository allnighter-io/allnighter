import XCTest
@testable import AllnighterCore

final class HostSidecarBundleTests: XCTestCase {
    func testFindsWrappedXcodeBundleLayout() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("sidecar-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let wrapped = root
            .appendingPathComponent("AgentOS_AgentOSCLI.bundle")
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
        try fm.createDirectory(at: wrapped, withIntermediateDirectories: true)
        let expected = wrapped.appendingPathComponent("catalog.json")
        try Data("{\"schemaVersion\":1}".utf8).write(to: expected)

        let found = HostSidecarBundle.resourceURL(
            bundleName: "AgentOS_AgentOSCLI.bundle",
            resourceFile: "catalog.json",
            searchRoots: [root]
        )
        XCTAssertEqual(found?.resolvingSymlinksInPath().path, expected.resolvingSymlinksInPath().path)

        let data = HostSidecarBundle.data(
            bundleName: "AgentOS_AgentOSCLI.bundle",
            resourceFile: "catalog.json",
            searchRoots: [root]
        )
        XCTAssertEqual(data, Data("{\"schemaVersion\":1}".utf8))
    }

    func testPrefersFlatCLISidecarWhenBothExist() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("sidecar-flat-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let bundle = root.appendingPathComponent("AgentOS_AgentOSCLI.bundle")
        try fm.createDirectory(
            at: bundle.appendingPathComponent("Contents/Resources"),
            withIntermediateDirectories: true
        )
        try Data("wrapped".utf8).write(
            to: bundle.appendingPathComponent("Contents/Resources/catalog.json")
        )
        try Data("flat".utf8).write(to: bundle.appendingPathComponent("catalog.json"))

        let data = HostSidecarBundle.data(
            bundleName: "AgentOS_AgentOSCLI.bundle",
            resourceFile: "catalog.json",
            searchRoots: [root]
        )
        XCTAssertEqual(data, Data("flat".utf8))
    }

    func testDefaultSearchRootsStayOutOfDocuments() {
        for root in HostSidecarBundle.defaultSearchRoots() {
            XCTAssertFalse(root.path.contains("/Documents"))
            XCTAssertFalse(root.path.contains("/Desktop"))
            XCTAssertFalse(root.path.contains("/Downloads"))
        }
    }
}
