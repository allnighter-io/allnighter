import XCTest
@testable import AllnighterCore

/// PRJ-S06 Works Test (pure layer): the dirty-state dispatch gate is deterministic
/// — scope-overlapping dirt blocks until acknowledged, out-of-scope dirt is a
/// warning, no declared scope requires acknowledging the whole dirty tree, and no
/// usable root means no mutating dispatch.
final class ProjectExecutionGateTests: XCTestCase {
    private func project(root: String = "/work/A", archived: Bool = false) -> Project {
        Project(id: "prj_a", displayName: "A", localRootPath: root, normalizedRootPath: root,
                kind: .gitRepo, createdAt: Date(timeIntervalSince1970: 1), lastOpenedAt: Date(timeIntervalSince1970: 1),
                archived: archived)
    }

    private func gate(scope: [String], dirty: [String], ack: Bool = false,
                      rootState: RootState = .available, archived: Bool = false) -> ProjectDispatchGate {
        ProjectDispatchGateEvaluator.evaluate(
            project: project(archived: archived), observedRootState: rootState,
            likelyFilesOrAreas: scope, dirtyFiles: dirty, dirtyAcknowledged: ack)
    }

    // MARK: Gate

    func testNoRootBlocks() {
        XCTAssertEqual(gate(scope: ["Sources/"], dirty: [], rootState: .missing), .blockedNoProjectRoot)
        XCTAssertEqual(gate(scope: [], dirty: [], rootState: .permissionDenied), .blockedNoProjectRoot)
        XCTAssertEqual(gate(scope: [], dirty: [], archived: true), .blockedNoProjectRoot)
    }

    func testCleanTreeAllowed() {
        XCTAssertEqual(gate(scope: ["Sources/Foo.swift"], dirty: []), .allowed(warnings: []))
        XCTAssertEqual(gate(scope: [], dirty: []), .allowed(warnings: []))
    }

    func testOutOfScopeDirtIsWarningNotBlock() {
        let g = gate(scope: ["Sources/Engine/"], dirty: ["docs/README.md", "Sources/Core/X.swift"])
        XCTAssertEqual(g, .allowed(warnings: ["docs/README.md", "Sources/Core/X.swift"]))
    }

    func testOverlapBlocksUntilAcknowledged() {
        let dirty = ["Sources/Engine/Run.swift", "docs/README.md"]
        let blocked = gate(scope: ["Sources/Engine/"], dirty: dirty)
        XCTAssertEqual(blocked, .blockedDirtyScopeOverlap(files: ["Sources/Engine/Run.swift"]))
        XCTAssertFalse(blocked.allowsDispatch)

        let acked = gate(scope: ["Sources/Engine/"], dirty: dirty, ack: true)
        XCTAssertEqual(acked, .allowed(warnings: dirty))
        XCTAssertTrue(acked.allowsDispatch)
    }

    func testEmptyScopeWithDirtNeedsAcknowledgement() {
        let dirty = ["a.txt", "b/c.txt"]
        XCTAssertEqual(gate(scope: [], dirty: dirty), .needsDirtyAcknowledgement(files: dirty))
        XCTAssertEqual(gate(scope: [], dirty: dirty, ack: true), .allowed(warnings: dirty))
        // Whitespace-only scope entries count as no scope.
        XCTAssertEqual(gate(scope: ["  "], dirty: dirty), .needsDirtyAcknowledgement(files: dirty))
    }

    // MARK: Path matcher

    func testExactMatch() {
        XCTAssertTrue(PathScopeMatcher.matches(file: "Sources/Foo.swift", scopeEntry: "Sources/Foo.swift"))
        XCTAssertFalse(PathScopeMatcher.matches(file: "Sources/Foo.swift", scopeEntry: "Sources/Bar.swift"))
    }

    func testDirectoryPrefix() {
        XCTAssertTrue(PathScopeMatcher.matches(file: "area/x/y.swift", scopeEntry: "area/"))
        XCTAssertTrue(PathScopeMatcher.matches(file: "area/x/y.swift", scopeEntry: "area"))   // no trailing slash
        XCTAssertFalse(PathScopeMatcher.matches(file: "areax/y.swift", scopeEntry: "area/"))  // not a real subdir
        XCTAssertFalse(PathScopeMatcher.matches(file: "area", scopeEntry: "area/"))           // the dir itself, no child
    }

    func testGlob() {
        XCTAssertTrue(PathScopeMatcher.matches(file: "Sources/Foo.swift", scopeEntry: "Sources/*.swift"))
        XCTAssertFalse(PathScopeMatcher.matches(file: "Sources/sub/Foo.swift", scopeEntry: "Sources/*.swift")) // * stops at /
        XCTAssertTrue(PathScopeMatcher.matches(file: "Sources/sub/Foo.swift", scopeEntry: "Sources/**/*.swift"))
        XCTAssertTrue(PathScopeMatcher.matches(file: "a/b/c.txt", scopeEntry: "**/*.txt"))
        XCTAssertTrue(PathScopeMatcher.matches(file: "Foo.swift", scopeEntry: "Foo.????t"))  // ????t == swift
    }

    func testNormalizationStripsLeadingDotSlash() {
        XCTAssertTrue(PathScopeMatcher.matches(file: "./Sources/Foo.swift", scopeEntry: "Sources/Foo.swift"))
        XCTAssertTrue(PathScopeMatcher.matches(file: "/Sources/Foo.swift", scopeEntry: "Sources/"))
    }
}
