import XCTest
@testable import AllnighterCore

/// PO-F6: `alln dev export-contracts [--check]` must resolve the generated
/// dir from the repo root, not raw `currentDirectoryPath`. Exercises
/// `ContractExport.check`/`write`/`findRepoRoot` directly (the CLI layer is a
/// thin wrapper that just prints/exits based on these results).
final class ContractExportCwdRobustnessTests: XCTestCase {
    private var tmpRoot: URL!

    override func setUpWithError() throws {
        tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("po-f6-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpRoot)
    }

    // MARK: - Helpers

    /// Marks `tmpRoot` as a repo root the way git would (no real repo needed —
    /// `findRepoRoot` only checks for the directory's existence).
    private func markAsRepoRoot() throws {
        try FileManager.default.createDirectory(at: tmpRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    }

    private func subdir(_ path: String = "sub/deeper") -> URL {
        let dir = tmpRoot.appendingPathComponent(path, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func generatedDirURL() -> URL {
        tmpRoot.appendingPathComponent(ContractExport.generatedDir, isDirectory: true)
    }

    // MARK: - findRepoRoot

    func testFindRepoRootAscendsFromNestedSubdirectory() throws {
        try markAsRepoRoot()
        let nested = subdir()
        XCTAssertEqual(ContractExport.findRepoRoot(from: nested.path)?.standardizedFileURL,
                        tmpRoot.standardizedFileURL)
    }

    func testFindRepoRootReturnsNilWhenNoMarkerExists() throws {
        // tmpRoot has neither .git nor docs/generated/alln, and nothing above
        // NSTemporaryDirectory() is expected to carry either marker.
        XCTAssertNil(ContractExport.findRepoRoot(from: tmpRoot.path))
    }

    // MARK: - write: repo root vs subdirectory parity, no stray dir

    func testWriteFromRepoRootAndSubdirectoryProduceIdenticalResults() throws {
        try markAsRepoRoot()
        let nested = subdir()

        let fromRoot = try ContractExport.write(from: tmpRoot.path)
        let rootContents = try String(contentsOf: generatedDirURL().appendingPathComponent("error-codes.json"), encoding: .utf8)

        // Mutate on disk, then re-write from the subdirectory — must land in the
        // same place and produce the same content, not a stray copy.
        try "mutated".write(to: generatedDirURL().appendingPathComponent("error-codes.json"), atomically: true, encoding: .utf8)

        let fromSub = try ContractExport.write(from: nested.path)
        let subContents = try String(contentsOf: generatedDirURL().appendingPathComponent("error-codes.json"), encoding: .utf8)

        XCTAssertEqual(fromRoot.count, fromSub.count)
        XCTAssertEqual(fromRoot.path, fromSub.path)
        XCTAssertEqual(rootContents, subContents)

        // No stray <subdir>/docs/generated/alln was created.
        let strayDir = nested.appendingPathComponent(ContractExport.generatedDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: strayDir.path),
                        "write from a subdirectory must not litter a stray generated dir under it")
    }

    func testWriteRefusesInsteadOfLitteringWhenNoRepoRootFound() throws {
        // No .git, no docs/generated/alln anywhere up the chain from tmpRoot.
        XCTAssertThrowsError(try ContractExport.write(from: tmpRoot.path)) { error in
            guard case ContractExport.NotFoundError.repoRootNotFound = error else {
                return XCTFail("expected repoRootNotFound, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: generatedDirURL().path),
                        "write must not create docs/generated/alln when no repo root is found")
    }

    // MARK: - check: repo root vs subdirectory parity

    func testCheckFromRepoRootAndSubdirectoryAgreeWhenUpToDate() throws {
        try markAsRepoRoot()
        _ = try ContractExport.write(from: tmpRoot.path)
        let nested = subdir()

        let fromRoot = try ContractExport.check(from: tmpRoot.path)
        let fromSub = try ContractExport.check(from: nested.path)
        XCTAssertEqual(fromRoot, fromSub)
        guard case .upToDate = fromRoot else { return XCTFail("expected upToDate, got \(fromRoot)") }
    }

    func testCheckStillReportsContentDriftFromSubdirectory() throws {
        try markAsRepoRoot()
        _ = try ContractExport.write(from: tmpRoot.path)
        try "drifted-content".write(to: generatedDirURL().appendingPathComponent("error-codes.json"), atomically: true, encoding: .utf8)
        let nested = subdir()

        let outcome = try ContractExport.check(from: nested.path)
        guard case .drifted(let files) = outcome else { return XCTFail("expected drifted, got \(outcome)") }
        XCTAssertEqual(files, ["error-codes.json"])
    }

    // MARK: - check: missing must never be reported as drift

    func testCheckReportsGeneratedDirMissingNotDrift() throws {
        try markAsRepoRoot()
        // Never wrote docs/generated/alln at all.
        XCTAssertThrowsError(try ContractExport.check(from: tmpRoot.path)) { error in
            guard case ContractExport.NotFoundError.generatedDirMissing = error else {
                return XCTFail("expected generatedDirMissing, not drift — got \(error)")
            }
        }
    }

    func testCheckReportsArtifactsMissingNotDriftWhenDirPartiallyPopulated() throws {
        try markAsRepoRoot()
        _ = try ContractExport.write(from: tmpRoot.path)
        try FileManager.default.removeItem(at: generatedDirURL().appendingPathComponent("error-codes.json"))

        XCTAssertThrowsError(try ContractExport.check(from: tmpRoot.path)) { error in
            guard case ContractExport.NotFoundError.artifactsMissing(_, let filenames) = error else {
                return XCTFail("expected artifactsMissing, not drift — got \(error)")
            }
            XCTAssertEqual(filenames, ["error-codes.json"])
        }
    }

    func testCheckReportsRepoRootNotFoundWhenNoMarkerExists() throws {
        XCTAssertThrowsError(try ContractExport.check(from: tmpRoot.path)) { error in
            guard case ContractExport.NotFoundError.repoRootNotFound = error else {
                return XCTFail("expected repoRootNotFound, got \(error)")
            }
        }
    }
}
