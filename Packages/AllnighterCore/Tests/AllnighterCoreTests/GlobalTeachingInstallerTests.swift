import XCTest
@testable import AllnighterCore

final class GlobalTeachingInstallerTests: XCTestCase {
    private var root: URL!
    private var fm: FileManager!

    override func setUpWithError() throws {
        fm = .default
        root = fm.temporaryDirectory.appendingPathComponent(
            "global-teaching-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
        root = nil
    }

    private func claudeURL() -> URL {
        root.appendingPathComponent(".claude/CLAUDE.md")
    }

    private func cursorURL() -> URL {
        root.appendingPathComponent(".cursor/rules/allnighter.mdc")
    }

    private func write(_ text: String, to url: URL, crlf: Bool = false) throws {
        let parent = url.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let body = crlf
            ? text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
            : text
        try body.data(using: .utf8)!.write(to: url, options: .atomic)
    }

    private func read(_ url: URL) throws -> String {
        String(data: try Data(contentsOf: url), encoding: .utf8)!
    }

    // MARK: - Matrix

    func testHostMatrixMatchesTeachingInstalledCheck() {
        XCTAssertEqual(
            GlobalTeachingInstaller.hostMatrix,
            TeachingInstalledCheck.hostMatrix
        )
    }

    func testPreviewListsUnsupportedCodex() {
        let preview = GlobalTeachingInstaller.preview(homeDirectory: root, fileManager: fm)
        let codex = preview.hosts.first { $0.hostId == "codex" }
        XCTAssertEqual(codex?.unsupported, true)
        XCTAssertEqual(codex?.installAction, .unsupported)
        XCTAssertTrue(codex?.unsupportedReason?.contains("bootstrap --host codex") == true)
        XCTAssertTrue(preview.scopeNote.lowercased().contains("across all projects"))
    }

    // MARK: - Create / append

    func testMissingFileCreate() throws {
        let preview = GlobalTeachingInstaller.preview(homeDirectory: root, fileManager: fm)
        let claude = try XCTUnwrap(preview.hosts.first { $0.hostId == "claude" })
        XCTAssertEqual(claude.state, .absent)
        XCTAssertEqual(claude.installAction, .append)
        XCTAssertEqual(claude.contentHash, GlobalTeachingInstaller.absentContentHash)

        let result = GlobalTeachingInstaller.applyInstall(
            hostId: "claude",
            expectedContentHash: claude.contentHash,
            homeDirectory: root,
            fileManager: fm
        )
        XCTAssertTrue(result.success, result.detail)
        XCTAssertEqual(result.newState, .installed)
        XCTAssertTrue(fm.fileExists(atPath: claudeURL().path))
        let parsed = TeachingSnippet.parse(try read(claudeURL()))
        XCTAssertEqual(parsed.state, .installed)
    }

    func testAppendToExistingPreamble() throws {
        try write("# My instructions\n\nKeep this.\n", to: claudeURL())
        let preview = GlobalTeachingInstaller.preview(homeDirectory: root, fileManager: fm)
        let claude = try XCTUnwrap(preview.hosts.first { $0.hostId == "claude" })
        XCTAssertEqual(claude.installAction, .append)

        let result = GlobalTeachingInstaller.applyInstall(
            hostId: "claude",
            expectedContentHash: claude.contentHash,
            homeDirectory: root,
            fileManager: fm
        )
        XCTAssertTrue(result.success, result.detail)
        let text = try read(claudeURL())
        XCTAssertTrue(text.hasPrefix("# My instructions"))
        XCTAssertTrue(text.contains("Keep this."))
        XCTAssertEqual(TeachingSnippet.parse(text).state, .installed)
        // Exactly one open/close pair.
        XCTAssertEqual(text.components(separatedBy: TeachingSnippet.closeMarker).count - 1, 1)
    }

    // MARK: - Repair / remove

    func testRepairModified() throws {
        let tampered = TeachingSnippet.wrap(body: TeachingSnippet.body + "\n- hand edit")
        try write("Header\n\n\(tampered)\nFooter\n", to: claudeURL())
        let preview = GlobalTeachingInstaller.preview(homeDirectory: root, fileManager: fm)
        let claude = try XCTUnwrap(preview.hosts.first { $0.hostId == "claude" })
        XCTAssertEqual(claude.state, .modified)
        XCTAssertEqual(claude.installAction, .repair)
        XCTAssertNotNil(claude.diffText)
        XCTAssertTrue(claude.diffText?.contains("hand edit") == true)

        let result = GlobalTeachingInstaller.applyInstall(
            hostId: "claude",
            expectedContentHash: claude.contentHash,
            homeDirectory: root,
            fileManager: fm
        )
        XCTAssertTrue(result.success, result.detail)
        let text = try read(claudeURL())
        XCTAssertTrue(text.contains("Header"))
        XCTAssertTrue(text.contains("Footer"))
        XCTAssertFalse(text.contains("hand edit"))
        XCTAssertEqual(TeachingSnippet.parse(text).state, .installed)
    }

    func testRemoveLeavesPreamble() throws {
        try write("Keep me\n\n\(TeachingSnippet.wrap())\nAlso keep\n", to: cursorURL())
        let preview = GlobalTeachingInstaller.preview(homeDirectory: root, fileManager: fm)
        let cursor = try XCTUnwrap(preview.hosts.first { $0.hostId == "cursor" })
        XCTAssertTrue(cursor.canRemove)

        let result = GlobalTeachingInstaller.applyRemove(
            hostId: "cursor",
            expectedContentHash: cursor.contentHash,
            homeDirectory: root,
            fileManager: fm
        )
        XCTAssertTrue(result.success, result.detail)
        let text = try read(cursorURL())
        XCTAssertTrue(text.contains("Keep me"))
        XCTAssertTrue(text.contains("Also keep"))
        XCTAssertFalse(text.contains("ALLNIGHTER:TEACHING"))
        XCTAssertEqual(TeachingSnippet.parse(text).state, .absent)
    }

    // MARK: - CRLF

    func testCRLFPreservedOnAppend() throws {
        try write("# Win\nline\n", to: claudeURL(), crlf: true)
        let preview = GlobalTeachingInstaller.preview(homeDirectory: root, fileManager: fm)
        let claude = try XCTUnwrap(preview.hosts.first { $0.hostId == "claude" })
        XCTAssertTrue(claude.usesCRLF)

        let result = GlobalTeachingInstaller.applyInstall(
            hostId: "claude",
            expectedContentHash: claude.contentHash,
            homeDirectory: root,
            fileManager: fm
        )
        XCTAssertTrue(result.success, result.detail)
        let data = try Data(contentsOf: claudeURL())
        let raw = String(data: data, encoding: .utf8)!
        XCTAssertTrue(raw.contains("\r\n"), "must preserve CRLF")
        let bareLF = raw.replacingOccurrences(of: "\r\n", with: "")
        XCTAssertFalse(bareLF.contains("\n"), "must not introduce bare LF")
        XCTAssertEqual(TeachingSnippet.parse(raw.replacingOccurrences(of: "\r\n", with: "\n")).state, .installed)
    }

    // MARK: - Malformed / drift

    func testDuplicateMarkersRefuseAppendOfferRepair() throws {
        let once = TeachingSnippet.wrap()
        try write("\(once)\n\(once)\n", to: claudeURL())
        let preview = GlobalTeachingInstaller.preview(homeDirectory: root, fileManager: fm)
        let claude = try XCTUnwrap(preview.hosts.first { $0.hostId == "claude" })
        XCTAssertEqual(claude.state, .malformed)
        XCTAssertEqual(claude.installAction, .repair)
        XCTAssertNotNil(claude.error)
        XCTAssertTrue(claude.error?.contains("will not append") == true)

        let result = GlobalTeachingInstaller.applyInstall(
            hostId: "claude",
            expectedContentHash: claude.contentHash,
            homeDirectory: root,
            fileManager: fm
        )
        XCTAssertTrue(result.success, result.detail)
        let text = try read(claudeURL())
        XCTAssertEqual(text.components(separatedBy: TeachingSnippet.closeMarker).count - 1, 1)
        XCTAssertEqual(TeachingSnippet.parse(text).state, .installed)
    }

    func testDriftRefuse() throws {
        try write("old\n", to: claudeURL())
        let preview = GlobalTeachingInstaller.preview(homeDirectory: root, fileManager: fm)
        let claude = try XCTUnwrap(preview.hosts.first { $0.hostId == "claude" })

        // Mutate after preview.
        try write("changed since preview\n", to: claudeURL())

        let result = GlobalTeachingInstaller.applyInstall(
            hostId: "claude",
            expectedContentHash: claude.contentHash,
            homeDirectory: root,
            fileManager: fm
        )
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.detail.contains("drift"))
        XCTAssertEqual(try read(claudeURL()), "changed since preview\n")
    }

    func testInstallAllSupported() throws {
        let preview = GlobalTeachingInstaller.preview(homeDirectory: root, fileManager: fm)
        let results = GlobalTeachingInstaller.installAllSupported(
            preview: preview,
            homeDirectory: root,
            fileManager: fm
        )
        XCTAssertEqual(results.count, 2) // claude + cursor
        XCTAssertTrue(results.allSatisfy(\.success))
        XCTAssertEqual(TeachingSnippet.parse(try read(claudeURL())).state, .installed)
        XCTAssertEqual(TeachingSnippet.parse(try read(cursorURL())).state, .installed)
    }

    func testNoOpWhenInstalled() throws {
        try write(TeachingSnippet.wrap(), to: claudeURL())
        let preview = GlobalTeachingInstaller.preview(homeDirectory: root, fileManager: fm)
        let claude = try XCTUnwrap(preview.hosts.first { $0.hostId == "claude" })
        XCTAssertEqual(claude.installAction, .noOp)

        let result = GlobalTeachingInstaller.applyInstall(
            hostId: "claude",
            expectedContentHash: claude.contentHash,
            homeDirectory: root,
            fileManager: fm
        )
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.action, .noOp)
    }

    func testUnsupportedCodexNeverWrites() {
        let preview = GlobalTeachingInstaller.preview(homeDirectory: root, fileManager: fm)
        let codex = preview.hosts.first { $0.hostId == "codex" }!
        let result = GlobalTeachingInstaller.applyInstall(
            hostId: "codex",
            expectedContentHash: codex.contentHash,
            homeDirectory: root,
            fileManager: fm
        )
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.action, .unsupported)
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("AGENTS.md").path))
    }
}
