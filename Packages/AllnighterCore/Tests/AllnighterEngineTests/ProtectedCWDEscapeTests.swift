import XCTest
@testable import AllnighterEngine

final class ProtectedCWDEscapeTests: XCTestCase {

    private static let homePath = "/Users/tester"
    private static let scratchPath = "/Users/tester/Library/Application Support/Allnighter/ProbeScratch"

    private func seams(
        cwd: String,
        ensureScratch: String? = scratchPath,
        onChange: @escaping @Sendable (String) -> Bool = { _ in true }
    ) -> (ProtectedCWDEscape.Seams, () -> String?) {
        let home = URL(fileURLWithPath: Self.homePath)
        final class ChangedToBox: @unchecked Sendable {
            var value: String?
        }
        let changedTo = ChangedToBox()
        let seams = ProtectedCWDEscape.Seams(
            currentDirectory: { cwd },
            homeDirectory: { home },
            ensureProbeScratch: { ensureScratch },
            changeCurrentDirectory: { path in
                changedTo.value = path
                return onChange(path)
            }
        )
        return (seams, { changedTo.value })
    }

    func testIsProtectedDocumentsCheckout() {
        XCTAssertTrue(ProtectedCWDEscape.isProtected(
            currentDirectory: "\(Self.homePath)/Documents/GitHub/Allnighter",
            homeDirectory: URL(fileURLWithPath: Self.homePath)
        ))
    }

    func testIsProtectedDocumentsRoot() {
        XCTAssertTrue(ProtectedCWDEscape.isProtected(
            currentDirectory: "\(Self.homePath)/Documents",
            homeDirectory: URL(fileURLWithPath: Self.homePath)
        ))
    }

    func testIsProtectedDesktop() {
        XCTAssertTrue(ProtectedCWDEscape.isProtected(
            currentDirectory: "\(Self.homePath)/Desktop",
            homeDirectory: URL(fileURLWithPath: Self.homePath)
        ))
    }

    func testIsProtectedDownloads() {
        XCTAssertTrue(ProtectedCWDEscape.isProtected(
            currentDirectory: "\(Self.homePath)/Downloads/inbox",
            homeDirectory: URL(fileURLWithPath: Self.homePath)
        ))
    }

    func testIsNotProtectedTmp() {
        XCTAssertFalse(ProtectedCWDEscape.isProtected(
            currentDirectory: "/tmp/work",
            homeDirectory: URL(fileURLWithPath: Self.homePath)
        ))
    }

    func testIsNotProtectedApplicationSupport() {
        XCTAssertFalse(ProtectedCWDEscape.isProtected(
            currentDirectory: "\(Self.homePath)/Library/Application Support/Allnighter",
            homeDirectory: URL(fileURLWithPath: Self.homePath)
        ))
    }

    func testDocumentsCWDEscapesToProbeScratch() {
        let (seams, changedTo) = seams(cwd: "\(Self.homePath)/Documents/GitHub/Allnighter")
        XCTAssertTrue(ProtectedCWDEscape.escapeIfNeeded(seams: seams))
        XCTAssertEqual(changedTo(), Self.scratchPath)
    }

    func testDesktopCWDEscapesToProbeScratch() {
        let (seams, changedTo) = seams(cwd: "\(Self.homePath)/Desktop")
        XCTAssertTrue(ProtectedCWDEscape.escapeIfNeeded(seams: seams))
        XCTAssertEqual(changedTo(), Self.scratchPath)
    }

    func testDownloadsCWDEscapesToProbeScratch() {
        let (seams, changedTo) = seams(cwd: "\(Self.homePath)/Downloads/pkg")
        XCTAssertTrue(ProtectedCWDEscape.escapeIfNeeded(seams: seams))
        XCTAssertEqual(changedTo(), Self.scratchPath)
    }

    func testSafeCWDIsNoOp() {
        let (seams, changedTo) = seams(cwd: "/tmp/build")
        XCTAssertFalse(ProtectedCWDEscape.escapeIfNeeded(seams: seams))
        XCTAssertNil(changedTo())
    }

    func testApplicationSupportCWDIsNoOp() {
        let (seams, changedTo) = seams(cwd: "\(Self.homePath)/Library/Application Support/Allnighter")
        XCTAssertFalse(ProtectedCWDEscape.escapeIfNeeded(seams: seams))
        XCTAssertNil(changedTo())
    }

    func testFallsBackToHomeWhenScratchUnavailable() {
        let (seams, changedTo) = seams(
            cwd: "\(Self.homePath)/Documents/repo",
            ensureScratch: nil
        )
        XCTAssertTrue(ProtectedCWDEscape.escapeIfNeeded(seams: seams))
        XCTAssertEqual(changedTo(), Self.homePath)
    }

    /// 2026-08-14: bare `alln` from a Documents checkout. `escapeIfNeeded`
    /// getcwd's first — that read *is* the prompt. `adoptNeutral` must not.
    func testAdoptNeutralDoesNotReadCurrentDirectory() {
        final class ReadBox: @unchecked Sendable { var read = false }
        let readCwd = ReadBox()
        let (seams, changedTo) = seams(cwd: "\(Self.homePath)/Documents/GitHub/Allnighter")
        let noRead = ProtectedCWDEscape.Seams(
            currentDirectory: {
                readCwd.read = true
                return "\(Self.homePath)/Documents/GitHub/Allnighter"
            },
            homeDirectory: { URL(fileURLWithPath: Self.homePath) },
            ensureProbeScratch: { Self.scratchPath },
            changeCurrentDirectory: seams.changeCurrentDirectory
        )
        XCTAssertTrue(ProtectedCWDEscape.adoptNeutral(seams: noRead))
        XCTAssertFalse(readCwd.read, "adoptNeutral must not getcwd")
        XCTAssertEqual(changedTo(), Self.scratchPath)
    }

    func testAdoptNeutralFallsBackToHomeWhenScratchUnavailable() {
        let (seams, changedTo) = seams(
            cwd: "\(Self.homePath)/Documents/repo",
            ensureScratch: nil
        )
        XCTAssertTrue(ProtectedCWDEscape.adoptNeutral(seams: seams))
        XCTAssertEqual(changedTo(), Self.homePath)
    }

    func testBareAllnDoesNotPreserveCallerCWD() {
        XCTAssertFalse(ProtectedCWDEscape.preservesCallerWorkingDirectory(command: "help"))
        XCTAssertFalse(ProtectedCWDEscape.preservesCallerWorkingDirectory(command: "version"))
        XCTAssertFalse(ProtectedCWDEscape.preservesCallerWorkingDirectory(command: "menu"))
        XCTAssertFalse(ProtectedCWDEscape.preservesCallerWorkingDirectory(command: "bootstrap"))
        XCTAssertFalse(ProtectedCWDEscape.preservesCallerWorkingDirectory(command: "serve"))
        XCTAssertFalse(ProtectedCWDEscape.preservesCallerWorkingDirectory(command: "doctor"))
    }

    func testRepoScopedCommandsPreserveCallerCWD() {
        XCTAssertTrue(ProtectedCWDEscape.preservesCallerWorkingDirectory(command: "run"))
        XCTAssertTrue(ProtectedCWDEscape.preservesCallerWorkingDirectory(command: "loop"))
        XCTAssertTrue(ProtectedCWDEscape.preservesCallerWorkingDirectory(command: "project"))
        XCTAssertTrue(ProtectedCWDEscape.preservesCallerWorkingDirectory(command: "ps"))
        XCTAssertTrue(ProtectedCWDEscape.preservesCallerWorkingDirectory(
            command: "doctor", args: ["handoff"]
        ))
    }
}
