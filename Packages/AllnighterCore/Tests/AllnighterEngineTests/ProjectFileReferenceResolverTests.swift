import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

final class ProjectFileReferenceResolverTests: XCTestCase {
    func testResolvesTextFileWithLineRangeAndMetadata() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Sources/App.swift")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "one\ntwo\nthree\nfour\n".write(to: file, atomically: true, encoding: .utf8)

        let resolver = ProjectFileReferenceResolver()
        let resolved = try resolver.resolve(
            inputs: [FileReferenceInput(path: "Sources/App.swift", lineRange: FileLineRange(startLine: 2, endLine: 3))],
            rootPath: root.path,
            projectId: "proj1",
            idFactory: { "ref1" }
        )

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].turnRef, TurnFileReferenceRef(referenceId: "ref1", sequence: 0))
        XCTAssertEqual(resolved[0].attachedFile.rootRelativePath, "Sources/App.swift")
        XCTAssertEqual(resolved[0].attachedFile.preloadedText, "two\nthree")
        XCTAssertEqual(resolved[0].attachedFile.projectId, "proj1")
        XCTAssertEqual(resolved[0].attachedFile.languageHint, "swift")
        XCTAssertEqual(resolved[0].attachedFile.byteSize, "one\ntwo\nthree\nfour\n".utf8.count)
        XCTAssertNotNil(resolved[0].attachedFile.storedSha256)
    }

    func testRejectsOutsideProject() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try ProjectFileReferenceResolver().resolve(
            inputs: [FileReferenceInput(path: "../secrets.txt")],
            rootPath: root.path,
            projectId: nil
        )) { error in
            XCTAssertEqual(error as? FileReferenceError, .outsideProject("../secrets.txt"))
        }
    }

    func testRejectsSensitiveFiles() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try "API_KEY=secret\n".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ProjectFileReferenceResolver().resolve(
            inputs: [FileReferenceInput(path: ".env")],
            rootPath: root.path,
            projectId: nil
        )) { error in
            XCTAssertEqual(error as? FileReferenceError, .sensitiveBlocked(".env"))
        }
    }

    func testRejectsBinaryFiles() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0, 1, 2, 3]).write(to: root.appendingPathComponent("image.bin"))

        XCTAssertThrowsError(try ProjectFileReferenceResolver().resolve(
            inputs: [FileReferenceInput(path: "image.bin")],
            rootPath: root.path,
            projectId: nil
        )) { error in
            XCTAssertEqual(error as? FileReferenceError, .binaryUnsupported("image.bin"))
        }
    }

    func testRejectsInvalidLineRange() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try "one\ntwo\n".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ProjectFileReferenceResolver().resolve(
            inputs: [FileReferenceInput(path: "notes.txt", lineRange: FileLineRange(startLine: 3, endLine: 4))],
            rootPath: root.path,
            projectId: nil
        )) { error in
            XCTAssertEqual(error as? FileReferenceError, .invalidLineRange("notes.txt"))
        }
    }

    func testParsesAtTokensAndRanges() {
        let refs = FileReferenceTokenParser.parse(message: "read @Sources/App.swift:10-20 and ignore @mike")
        XCTAssertEqual(refs, [
            FileReferenceInput(path: "Sources/App.swift", lineRange: FileLineRange(startLine: 10, endLine: 20))
        ])
    }

    func testCatalogRanksLaneTouchedAndRecency() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "a".write(to: root.appendingPathComponent("Sources/A.swift"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appendingPathComponent("Sources/B.swift"), atomically: true, encoding: .utf8)

        let results = ProjectFileCatalog().candidates(
            rootPath: root.path,
            query: "swift",
            recentlyReferenced: ["Sources/B.swift"],
            laneTouched: ["Sources/A.swift"]
        )
        XCTAssertEqual(results.first?.path, "Sources/A.swift")
        XCTAssertTrue(results.contains { $0.path == "Sources/B.swift" })
    }

    private func makeRepo() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("file-ref-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
