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

    func testCatalogRanksRecentAboveLaneTouched() throws {
        // FR-S08 freshness order: recently referenced ≫ recently touched (lane). Both
        // basename-contains "swift", so freshness alone breaks the tie → recent wins.
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
        XCTAssertEqual(results.first?.path, "Sources/B.swift")
        XCTAssertTrue(results.contains { $0.path == "Sources/A.swift" })
    }

    func testExactBasenameBeatsContainsAndDocTiebreak() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try "x".write(to: root.appendingPathComponent("Store.swift"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("UserStore.swift"), atomically: true, encoding: .utf8)

        // Query equals the basename stem of one file → exact basename wins over contains.
        let results = ProjectFileCatalog().candidates(rootPath: root.path, query: "store.swift")
        XCTAssertEqual(results.first?.path, "Store.swift")
    }

    func testReadableDocIsOnlyAGentleWithinTierTiebreak() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        // Both contain "guide" in the basename (same tier); the .md doc edges ahead.
        try "x".write(to: root.appendingPathComponent("guide.md"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("guide.bin"), atomically: true, encoding: .utf8)

        let results = ProjectFileCatalog().candidates(rootPath: root.path, query: "guide")
        XCTAssertEqual(results.first?.path, "guide.md")

        // But a code EXACT match still wins over a doc CONTAINS match when code-shaped.
        try "x".write(to: root.appendingPathComponent("Config.swift"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("config-notes.md"), atomically: true, encoding: .utf8)
        let code = ProjectFileCatalog().candidates(rootPath: root.path, query: "config.swift")
        XCTAssertEqual(code.first?.path, "Config.swift")
    }

    func testGeneratedAndVendorFilesSinkUnlessExact() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        // `vendor/` survives the directory walk (unlike node_modules), so it actually
        // exercises the in-ranker noise demotion.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("vendor"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("vendor/widget.js"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("src/widget.js"), atomically: true, encoding: .utf8)

        // Non-exact "widget" contains both; the clean src file outranks the vendored one.
        let contains = ProjectFileCatalog().candidates(rootPath: root.path, query: "widget")
        XCTAssertEqual(contains.first?.path, "src/widget.js")
    }

    func testFuzzyAbbreviationMatches() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        try "x".write(to: root.appendingPathComponent("SSOT_Founder_Workflow.md"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("unrelated.txt"), atomically: true, encoding: .utf8)

        // "ssotf" is not a substring but IS a subsequence of the doc basename.
        let results = ProjectFileCatalog().candidates(rootPath: root.path, query: "ssotf")
        XCTAssertEqual(results.first?.path, "SSOT_Founder_Workflow.md")
        XCTAssertFalse(results.contains { $0.path == "unrelated.txt" })
    }

    func testNoRepoSpecificVocabularyBoost() throws {
        let root = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        // A "PRD"/"SSOT"-style name gets no special boost over a plain file at the same
        // tier; with no query, recency/order decides, not the name.
        try "x".write(to: root.appendingPathComponent("PRD.md"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        let results = ProjectFileCatalog().candidates(rootPath: root.path, query: "")
        // Both are readable docs at tier 0 — neither is privileged by name. The set is
        // present and order is freshness/path, not a vocabulary boost.
        XCTAssertTrue(results.contains { $0.path == "PRD.md" })
        XCTAssertTrue(results.contains { $0.path == "notes.md" })
    }

    func testMatchTierAndHelpers() {
        XCTAssertEqual(ProjectFileCatalog.matchTier(query: "store.swift", basename: "store.swift", path: "store.swift"), .exactBasename)
        XCTAssertEqual(ProjectFileCatalog.matchTier(query: "user", basename: "userstore.swift", path: "src/userstore.swift"), .basenamePrefix)
        XCTAssertNil(ProjectFileCatalog.matchTier(query: "zzz", basename: "userstore.swift", path: "src/userstore.swift"))
        XCTAssertTrue(ProjectFileCatalog.isSubsequence("ssotf", of: "ssot_founder.md"))
        XCTAssertFalse(ProjectFileCatalog.isSubsequence("fsotf", of: "ssot_founder.md"))
        XCTAssertTrue(ProjectFileCatalog.isReadableDoc("readme.md"))
        XCTAssertFalse(ProjectFileCatalog.isReadableDoc("main.swift"))
        XCTAssertTrue(ProjectFileCatalog.isNoisy("node_modules/x/y.js"))
        XCTAssertTrue(ProjectFileCatalog.isNoisy("yarn.lock"))
        XCTAssertFalse(ProjectFileCatalog.isNoisy("src/main.swift"))
    }

    private func makeRepo() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("file-ref-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
