import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class ProjectMirrorMaterializerTests: XCTestCase {
    private var root: URL!
    private var store: ProjectMirrorStore!
    private var materializer: ProjectMirrorMaterializer!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("project-mirror-tests-\(UUID().uuidString)", isDirectory: true)
        store = ProjectMirrorStore(rootDirectory: root)
        materializer = ProjectMirrorMaterializer(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testMaterializesOnlyTypedBytesWithProvenanceAndVerifiesThem() throws {
        let mirror = try materializer.materialize(.init(
            id: "mirror-1", projectId: "prj_a", sourceCommit: "abc123",
            dirtyFingerprint: "dirty-hash",
            entries: [
                .init(path: "Sources/App.swift", data: Data("print(1)".utf8)),
                .init(path: "README.md", data: Data("read me".utf8)),
            ],
            createdAt: Date(timeIntervalSince1970: 1)
        ))

        XCTAssertEqual(mirror.files.map(\.path), ["README.md", "Sources/App.swift"])
        XCTAssertEqual(try materializer.verify(id: "mirror-1"), mirror)
        XCTAssertEqual(
            try String(contentsOf: store.workspaceDirectory(id: "mirror-1").appendingPathComponent("Sources/App.swift")),
            "print(1)"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("mirror-1/workspace/.git").path))
    }

    func testRejectsDotenvTraversalAndDuplicateFilesBeforePublishingMirror() throws {
        XCTAssertThrowsError(try materializer.materialize(.init(
            id: "mirror-env", dirtyFingerprint: "x",
            entries: [.init(path: ".env.local", data: Data())]
        ))) { XCTAssertEqual($0 as? ProjectMirrorMaterializer.Error, .environmentFile(".env.local")) }
        XCTAssertThrowsError(try materializer.materialize(.init(
            id: "mirror-traversal", dirtyFingerprint: "x",
            entries: [.init(path: "../secret", data: Data())]
        ))) { XCTAssertEqual($0 as? ProjectMirrorMaterializer.Error, .unsafePath("../secret")) }
        XCTAssertThrowsError(try materializer.materialize(.init(
            id: "mirror-dupe", dirtyFingerprint: "x",
            entries: [.init(path: "a", data: Data()), .init(path: "a", data: Data())]
        ))) { XCTAssertEqual($0 as? ProjectMirrorMaterializer.Error, .duplicatePath("a")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("mirror-env").path))
    }

    func testTamperedMirrorFailsVerification() throws {
        _ = try materializer.materialize(.init(
            id: "mirror-tampered", dirtyFingerprint: "x",
            entries: [.init(path: "file.txt", data: Data("original".utf8))]
        ))
        try Data("changed".utf8).write(to: try store.workspaceDirectory(id: "mirror-tampered").appendingPathComponent("file.txt"))
        XCTAssertThrowsError(try materializer.verify(id: "mirror-tampered"))
    }
}
