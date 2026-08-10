import XCTest
@testable import AllnighterCore

final class CanonicalCLIInstallTests: XCTestCase {
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

    private func home() -> URL { tempRoot }

    private func makeCandidate(_ name: String = "alln-candidate", bytes: Data = Data("#!/bin/sh\necho ok\n".utf8)) throws -> URL {
        let url = tempRoot.appendingPathComponent(name)
        fm.createFile(atPath: url.path, contents: bytes)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    // MARK: - Path helpers

    func testCanonicalDirectoryLayout() {
        let h = home()
        let dir = CanonicalCLIInstall.canonicalDirectory(homeDirectory: h)
        XCTAssertTrue(dir.path.hasSuffix(".local/share/allnighter/bin"))
    }

    func testIdentityRecordURL() {
        let h = home()
        let url = CanonicalCLIInstall.identityRecordURL(homeDirectory: h)
        XCTAssertTrue(url.path.contains("Library/Application Support/Allnighter/installed-binary.json"))
    }

    func testRollbackBinaryURL() {
        let h = home()
        let r = CanonicalCLIInstall.rollbackBinaryURL(homeDirectory: h)
        XCTAssertTrue(r.lastPathComponent == "alln.rollback")
    }

    // MARK: - Refusal

    func testRefusesAppBundleCandidate() throws {
        let bundle = tempRoot.appendingPathComponent("SomeApp.app/Contents/MacOS/binary")
        try fm.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: bundle.path, contents: Data("x".utf8))
        guard let reason = CanonicalCLIInstall.refusalReason(forCandidate: bundle, homeDirectory: home()) else {
            return XCTFail("expected refusal for .app bundle")
        }
        XCTAssertTrue(reason.contains(".app"))
    }

    func testRefusesDocumentsCandidate() throws {
        let candidate = home().appendingPathComponent("Documents/my-binary")
        try fm.createDirectory(at: candidate.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: candidate.path, contents: Data("x".utf8))
        guard let reason = CanonicalCLIInstall.refusalReason(forCandidate: candidate, homeDirectory: home()) else {
            return XCTFail("expected refusal for ~/Documents")
        }
        XCTAssertTrue(reason.contains("Documents"))
    }

    func testRefusesDesktopCandidate() throws {
        let candidate = home().appendingPathComponent("Desktop/my-binary")
        try fm.createDirectory(at: candidate.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: candidate.path, contents: Data("x".utf8))
        guard let reason = CanonicalCLIInstall.refusalReason(forCandidate: candidate, homeDirectory: home()) else {
            return XCTFail("expected refusal for ~/Desktop")
        }
        XCTAssertTrue(reason.contains("Desktop"))
    }

    func testRefusesDownloadsCandidate() throws {
        let candidate = home().appendingPathComponent("Downloads/my-binary")
        try fm.createDirectory(at: candidate.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: candidate.path, contents: Data("x".utf8))
        guard let reason = CanonicalCLIInstall.refusalReason(forCandidate: candidate, homeDirectory: home()) else {
            return XCTFail("expected refusal for ~/Downloads")
        }
        XCTAssertTrue(reason.contains("Downloads"))
    }

    func testAcceptsLibraryDeveloperCandidate() throws {
        let candidate = home().appendingPathComponent("Library/Developer/Xcode/DerivedData/my-binary")
        try fm.createDirectory(at: candidate.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: candidate.path, contents: Data("x".utf8))
        XCTAssertNil(CanonicalCLIInstall.refusalReason(forCandidate: candidate, homeDirectory: home()))
    }

    func testInstallRefusesAppBundle() throws {
        let bundle = tempRoot.appendingPathComponent("Foo.app/Contents/MacOS/foo")
        try fm.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: bundle.path, contents: Data("x".utf8))
        let result = CanonicalCLIInstall.install(candidateURL: bundle, homeDirectory: home(), fileManager: fm)
        guard case .failure(let f) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(f.code, "INSTALL_CANDIDATE_REFUSED")
    }

    func testInstallRefusesDocuments() throws {
        let candidate = home().appendingPathComponent("Documents/my-binary")
        try fm.createDirectory(at: candidate.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: candidate.path, contents: Data("x".utf8))
        let result = CanonicalCLIInstall.install(candidateURL: candidate, homeDirectory: home(), fileManager: fm)
        guard case .failure(let f) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(f.code, "INSTALL_CANDIDATE_REFUSED")
    }

    // MARK: - Fresh install

    func testFreshInstallCreatesCanonicalBinaryNoRollback() throws {
        let candidate = try makeCandidate()
        let h = home()
        let result = CanonicalCLIInstall.install(candidateURL: candidate, homeDirectory: h, fileManager: fm)
        guard case .success(let report) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertFalse(report.alreadyCanonical)
        XCTAssertNil(report.rollbackURL)
        let canonical = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: h)
        XCTAssertEqual(report.canonicalURL, canonical)
        XCTAssertTrue(fm.fileExists(atPath: canonical.path))
        XCTAssertTrue(fm.isExecutableFile(atPath: canonical.path))
    }

    func testFreshInstallWritesIdentityRecord() throws {
        let candidate = try makeCandidate()
        let h = home()
        let pr = makeProcessRunner(cdhash: "abc123")
        _ = CanonicalCLIInstall.install(candidateURL: candidate, homeDirectory: h, fileManager: fm, processRunner: pr)
        let identityURL = CanonicalCLIInstall.identityRecordURL(homeDirectory: h)
        XCTAssertTrue(fm.fileExists(atPath: identityURL.path))
        let data = try Data(contentsOf: identityURL)
        let record = try JSONDecoder().decode(IdentityRecordProbe.self, from: data)
        XCTAssertEqual(record.identity.cdhash, "abc123")
    }

    // MARK: - Re-install

    func testReinstallPreservesRollback() throws {
        let candidate1 = try makeCandidate(bytes: Data("version-one\n".utf8))
        let candidate2 = try makeCandidate("alln-candidate-2", bytes: Data("version-two\n".utf8))
        let h = home()

        _ = CanonicalCLIInstall.install(candidateURL: candidate1, homeDirectory: h, fileManager: fm)
        let result = CanonicalCLIInstall.install(candidateURL: candidate2, homeDirectory: h, fileManager: fm)
        guard case .success(let report) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertFalse(report.alreadyCanonical)
        XCTAssertNotNil(report.rollbackURL)
        XCTAssertTrue(fm.fileExists(atPath: report.rollbackURL!.path))

        let rollbackBytes = try Data(contentsOf: report.rollbackURL!)
        XCTAssertEqual(rollbackBytes, Data("version-one\n".utf8))

        let canonicalBytes = try Data(contentsOf: report.canonicalURL)
        XCTAssertEqual(canonicalBytes, Data("version-two\n".utf8))
    }

    func testReinstallLeavesRollbackPresent() throws {
        let candidate1 = try makeCandidate(bytes: Data("v1\n".utf8))
        let candidate2 = try makeCandidate("alln-candidate-2", bytes: Data("v2\n".utf8))
        let h = home()

        _ = CanonicalCLIInstall.install(candidateURL: candidate1, homeDirectory: h, fileManager: fm)
        let result = CanonicalCLIInstall.install(candidateURL: candidate2, homeDirectory: h, fileManager: fm)
        guard case .success(let report) = result else { return XCTFail("expected success") }
        XCTAssertTrue(fm.fileExists(atPath: report.rollbackURL!.path),
                      "rollback should still be on disk after re-install")
    }

    // MARK: - beforeBytesChange hook

    func testBeforeBytesChangeCalledAfterRollbackBeforeRename() throws {
        let candidate1 = try makeCandidate(bytes: Data("original\n".utf8))
        let candidate2 = try makeCandidate("alln-candidate-2", bytes: Data("replacement\n".utf8))
        let h = home()
        let canonicalURL = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: h)
        let rollbackURL = CanonicalCLIInstall.rollbackBinaryURL(homeDirectory: h)

        _ = CanonicalCLIInstall.install(candidateURL: candidate1, homeDirectory: h, fileManager: fm)

        var hookCalled = false
        var rollbackExisted = false
        var canonicalAbsentAfterRollbackMove = false

        let result = CanonicalCLIInstall.install(
            candidateURL: candidate2,
            homeDirectory: h,
            fileManager: fm,
            beforeBytesChange: {
                hookCalled = true
                rollbackExisted = self.fm.fileExists(atPath: rollbackURL.path)
                canonicalAbsentAfterRollbackMove = !self.fm.fileExists(atPath: canonicalURL.path)
                return .success(())
            }
        )

        guard case .success = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertTrue(hookCalled, "beforeBytesChange must be called")
        XCTAssertTrue(rollbackExisted, "rollback must exist before hook fires")
        XCTAssertTrue(canonicalAbsentAfterRollbackMove, "canonical must be absent after rollback move and before rename")
    }

    func testBeforeBytesChangeFailureAbortsWithBytesUnchanged() throws {
        let candidate1 = try makeCandidate(bytes: Data("original\n".utf8))
        let candidate2 = try makeCandidate("alln-candidate-2", bytes: Data("replacement\n".utf8))
        let h = home()
        let canonicalURL = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: h)

        _ = CanonicalCLIInstall.install(candidateURL: candidate1, homeDirectory: h, fileManager: fm)

        let hookFailure = CanonicalCLIInstall.Failure(code: "HOOK_ABORT", message: "test abort")
        let result = CanonicalCLIInstall.install(
            candidateURL: candidate2,
            homeDirectory: h,
            fileManager: fm,
            beforeBytesChange: { .failure(hookFailure) }
        )

        guard case .failure(let f) = result else { return XCTFail("expected failure, got \(result)") }
        XCTAssertEqual(f.code, hookFailure.code)

        let canonicalBytes = try Data(contentsOf: canonicalURL)
        XCTAssertEqual(canonicalBytes, Data("original\n".utf8), "canonical bytes must be byte-for-byte unchanged after hook failure")
    }

    // MARK: - Already canonical

    func testAlreadyCanonicalNoCopy() throws {
        let candidate = try makeCandidate()
        let h = home()
        let canonicalURL = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: h)

        try fm.createDirectory(at: canonicalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: candidate, to: canonicalURL)

        let result = CanonicalCLIInstall.install(candidateURL: canonicalURL, homeDirectory: h, fileManager: fm)
        guard case .success(let report) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertTrue(report.alreadyCanonical)
        XCTAssertNil(report.rollbackURL)
    }

    // MARK: - Rename failure / rollback

    func testFailedRenameRestoresPriorBytes() throws {
        let candidate1 = try makeCandidate(bytes: Data("original\n".utf8))
        let candidate2 = try makeCandidate("alln-candidate-2", bytes: Data("replacement\n".utf8))
        let h = home()
        let canonicalURL = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: h)

        _ = CanonicalCLIInstall.install(candidateURL: candidate1, homeDirectory: h, fileManager: fm)

        // The install moves: temp -> canonical. After the rollback is already created,
        // we need moveItem(at: srcURL(== temp), to: dstURL(== canonicalURL)) to fail.
        // Use a FileManager subclass that fails on the rename (third moveItem: 1=canonical->rollback, 2=??? restore first fail, wait.
        // Actually: #1 canonical->rollback, #2 (restore rollback->canonical in failure path), #3 temp->canonical
        // But hook succeeds, so no restore. Then #1 is canonical->rollback, #2 is temp->canonical.
        // We fail on #2.

        let failingFM = RenameFailingFileManager()
        failingFM.failOnCallIndex = 2
        try fm.createDirectory(at: canonicalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Set up the existing canonical
        try Data("original\n".utf8).write(to: canonicalURL)
        try failingFM.setAttributes([.posixPermissions: 0o755], ofItemAtPath: canonicalURL.path)

        let result = CanonicalCLIInstall.install(
            candidateURL: candidate2,
            homeDirectory: h,
            fileManager: failingFM,
            beforeBytesChange: { .success(()) }
        )

        guard case .failure(let f) = result else { return XCTFail("expected failure, got \(result)") }
        XCTAssertEqual(f.code, "SERVE_INSTALL_FAILED")
        XCTAssertTrue(f.message.contains("prior bytes restored"))
        let canonicalBytes = try Data(contentsOf: canonicalURL)
        XCTAssertEqual(canonicalBytes, Data("original\n".utf8), "canonical bytes must be restored after rename failure")
    }

    func testFailedRestoreReturnsRollbackFailedAndLeavesRollback() throws {
        let candidate1 = try makeCandidate(bytes: Data("original\n".utf8))
        let candidate2 = try makeCandidate("alln-candidate-2", bytes: Data("replacement\n".utf8))
        let h = home()
        let canonicalURL = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: h)
        let rollbackURL = CanonicalCLIInstall.rollbackBinaryURL(homeDirectory: h)

        _ = CanonicalCLIInstall.install(candidateURL: candidate1, homeDirectory: h, fileManager: fm)

        // Need: moveItem #1 (canonical->rollback) succeeds, moveItem #2 (temp->canonical) fails,
        // moveItem #3 (rollback->canonical restore) also fails.
        let failingFM = RenameFailingFileManager()
        failingFM.failOnCalls = [2, 3]
        try fm.createDirectory(at: canonicalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original\n".utf8).write(to: canonicalURL)
        try failingFM.setAttributes([.posixPermissions: 0o755], ofItemAtPath: canonicalURL.path)

        let result = CanonicalCLIInstall.install(
            candidateURL: candidate2,
            homeDirectory: h,
            fileManager: failingFM,
            beforeBytesChange: { .success(()) }
        )

        guard case .failure(let f) = result else { return XCTFail("expected failure, got \(result)") }
        XCTAssertEqual(f.code, "SERVE_ROLLBACK_FAILED")
        XCTAssertTrue(fm.fileExists(atPath: rollbackURL.path), "rollback must remain on disk after failed restore")
    }

    // MARK: - Identity

    func testDifferentCandidatesSameVersionDifferentCDHash() throws {
        let candidate1 = try makeCandidate(bytes: Data("a\n".utf8))
        let candidate2 = try makeCandidate("alln-candidate-2", bytes: Data("b\n".utf8))
        let h = home()
        let v = "1.0.0"

        let pr1 = makeProcessRunner(cdhash: "aaa111")
        let pr2 = makeProcessRunner(cdhash: "bbb222")

        _ = CanonicalCLIInstall.install(candidateURL: candidate1, homeDirectory: h, version: v, fileManager: fm, processRunner: pr1)
        let record1 = try readIdentityRecord(homeDirectory: h)
        XCTAssertEqual(record1.identity.cdhash, "aaa111")
        XCTAssertEqual(record1.identity.version, v)

        // Re-install with different candidate
        let result2 = CanonicalCLIInstall.install(candidateURL: candidate2, homeDirectory: h, version: v, fileManager: fm, processRunner: pr2)
        guard case .success = result2 else { return XCTFail("expected success") }
        let record2 = try readIdentityRecord(homeDirectory: h)
        XCTAssertEqual(record2.identity.cdhash, "bbb222")
        XCTAssertEqual(record2.identity.version, v)
        XCTAssertNotEqual(record1.identity.cdhash, record2.identity.cdhash)
    }

    func testNilCDHashStaysNil() throws {
        let candidate = try makeCandidate()
        let h = home()
        let pr = makeProcessRunner(cdhash: nil)
        _ = CanonicalCLIInstall.install(candidateURL: candidate, homeDirectory: h, version: "2.0", fileManager: fm, processRunner: pr)
        let record = try readIdentityRecord(homeDirectory: h)
        XCTAssertNil(record.identity.cdhash)
        XCTAssertEqual(record.identity.version, "2.0")
    }

    func testNilVersionStaysNil() throws {
        let candidate = try makeCandidate()
        let h = home()
        let pr = makeProcessRunner(cdhash: "hash123")
        _ = CanonicalCLIInstall.install(candidateURL: candidate, homeDirectory: h, version: nil, fileManager: fm, processRunner: pr)
        let record = try readIdentityRecord(homeDirectory: h)
        XCTAssertNil(record.identity.version)
        XCTAssertEqual(record.identity.cdhash, "hash123")
    }

    // MARK: - CDHash

    func testComputeCDHashExtractsCDHashLine() {
        let pr: (String, [String]) -> (stdout: String, stderr: String, exitCode: Int32) = { _, _ in
            (stdout: "", stderr: "Executable=...\nCDHash=abc123def456\nSignature Size=...\n", exitCode: 0)
        }
        let result = CanonicalCLIInstall.computeCDHash(candidateURL: URL(fileURLWithPath: "/tmp/test"), processRunner: pr)
        XCTAssertEqual(result, "abc123def456")
    }

    func testComputeCDHashReturnsNilOnNonZeroExit() {
        let pr: (String, [String]) -> (stdout: String, stderr: String, exitCode: Int32) = { _, _ in
            (stdout: "", stderr: "not signed\n", exitCode: 1)
        }
        let result = CanonicalCLIInstall.computeCDHash(candidateURL: URL(fileURLWithPath: "/tmp/test"), processRunner: pr)
        XCTAssertNil(result)
    }

    func testComputeCDHashReturnsNilWhenNoCDHashLine() {
        let pr: (String, [String]) -> (stdout: String, stderr: String, exitCode: Int32) = { _, _ in
            (stdout: "", stderr: "no cdhash\n", exitCode: 0)
        }
        let result = CanonicalCLIInstall.computeCDHash(candidateURL: URL(fileURLWithPath: "/tmp/test"), processRunner: pr)
        XCTAssertNil(result)
    }

    // MARK: - Edge cases

    func testInstallAcceptsLibraryDeveloperPath() throws {
        let developerDir = home().appendingPathComponent("Library/Developer/Xcode/DerivedData/build")
        try fm.createDirectory(at: developerDir, withIntermediateDirectories: true, attributes: nil)
        let candidate = developerDir.appendingPathComponent("alln")
        fm.createFile(atPath: candidate.path, contents: Data("dev-build\n".utf8))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: candidate.path)

        let result = CanonicalCLIInstall.install(candidateURL: candidate, homeDirectory: home(), fileManager: fm)
        guard case .success(let report) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertFalse(report.alreadyCanonical)
    }

    // MARK: - Helpers

    private func makeProcessRunner(cdhash: String?) -> (String, [String]) -> (stdout: String, stderr: String, exitCode: Int32) {
        return { _, _ in
            if let cdhash {
                (stdout: "", stderr: "CDHash=\(cdhash)\n", exitCode: 0)
            } else {
                (stdout: "", stderr: "not signed\n", exitCode: 1)
            }
        }
    }

    private func readIdentityRecord(homeDirectory: URL) throws -> IdentityRecordProbe {
        let url = CanonicalCLIInstall.identityRecordURL(homeDirectory: homeDirectory)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(IdentityRecordProbe.self, from: data)
    }
}

// MARK: - Test fixtures

private struct IdentityRecordProbe: Codable {
    let schemaVersion: Int
    let canonicalPath: String
    let identity: IdentityProbe
    let updatedAt: String
}

private struct IdentityProbe: Codable, Equatable {
    let cdhash: String?
    let version: String?
}

private final class RenameFailingFileManager: FileManager {
    var moveItemCount = 0
    var failOnCallIndex: Int?
    var failOnCalls: Set<Int> = []

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        moveItemCount += 1
        if let index = failOnCallIndex, moveItemCount == index {
            throw NSError(domain: "TestRenameFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "injected moveItem failure"])
        }
        if failOnCalls.contains(moveItemCount) {
            throw NSError(domain: "TestRenameFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "injected moveItem failure"])
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}
