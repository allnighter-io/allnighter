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
}
