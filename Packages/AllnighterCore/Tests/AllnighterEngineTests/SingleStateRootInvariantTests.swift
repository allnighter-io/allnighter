import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// CR-S05 proof wall: there is ONE durable state root for production hosts.
///
/// A restricted host (Codex, whose sandbox denies writes outside its workspace)
/// used to be silently redirected to a per-thread temp tree. That handed it a
/// parallel, empty product — no projects, no teams, no runs — which is how an
/// agent concludes the real repository is unreachable and starts building byte
/// transfer to explain it. The Codex redirect is deleted; a host that cannot
/// write the canonical root must fail honestly instead of being given another
/// world. See docs/archive/phases/CODE_RED_Core_Infrastructure_Repair.md.
///
/// Separately, XCTest hosts redirect to a per-process temp via
/// `AllnighterSupportRoot` so tests cannot corrupt the developer's real
/// Application Support tree. That redirect is test-only and must not be
/// confused with the deleted Codex parallel-root.
final class SingleStateRootInvariantTests: XCTestCase {
    private var saved: [String: String?] = [:]

    private func setEnv(_ key: String, _ value: String?) {
        if saved[key] == nil { saved[key] = ProcessInfo.processInfo.environment[key] }
        if let value { setenv(key, value, 1) } else { unsetenv(key) }
    }

    override func tearDownWithError() throws {
        for (key, value) in saved {
            if let value { setenv(key, value, 1) } else { unsetenv(key) }
        }
        saved = [:]
    }

    /// The exact environment a live Codex session presents.
    private func enterCodexSandbox() {
        setEnv("ALLNIGHTER_SUPPORT_DIR", nil)
        setEnv("CODEX_THREAD_ID", "0198f3ac-1111-2222-3333-444455556666")
        setEnv("CODEX_SANDBOX", "seatbelt")
    }

    func testCodexSandboxDoesNotGetItsOwnStateRoot() {
        setEnv("ALLNIGHTER_SUPPORT_DIR", nil)
        let normal = AllnighterPaths.support
        enterCodexSandbox()
        let restricted = AllnighterPaths.support

        XCTAssertEqual(restricted, normal,
                       "a restricted host must resolve the SAME durable state root")
        XCTAssertFalse(restricted.path.contains("Allnighter-Codex"),
                       "no per-thread temp state tree may be selected: \(restricted.path)")
        // Under XCTest the shared root is the process test redirect (not the
        // real Application Support tree). That is the test/real-state seam,
        // not a Codex fork — both "normal" and "restricted" still agree.
        XCTAssertTrue(
            AllnighterSupportRoot.isTestSupportRedirectActive,
            "XCTest must activate the support-root redirect"
        )
        XCTAssertEqual(
            restricted.standardizedFileURL,
            AllnighterSupportRoot.activeTestSupportRoot?.standardizedFileURL,
            "Codex env must not escape the test redirect: \(restricted.path)"
        )
    }

    /// Core mirrors Engine's resolution. They must never disagree, or catalog
    /// state and run state split under the same host.
    func testCoreAndEngineResolveTheSameRootUnderEveryHost() {
        setEnv("ALLNIGHTER_SUPPORT_DIR", nil)
        XCTAssertEqual(AllnighterSupportRoot.support.standardizedFileURL,
                       AllnighterPaths.support.standardizedFileURL)

        enterCodexSandbox()
        XCTAssertEqual(AllnighterSupportRoot.support.standardizedFileURL,
                       AllnighterPaths.support.standardizedFileURL,
                       "Core and Engine must not fork the state root inside a sandbox")

        // The explicit override still wins for both — that is how tests and
        // isolated config homes redirect, and it is never host-conditional.
        let explicit = NSTemporaryDirectory() + "alln-state-root-\(UUID().uuidString)"
        setEnv("ALLNIGHTER_SUPPORT_DIR", explicit)
        XCTAssertEqual(AllnighterPaths.support.path, explicit)
        XCTAssertEqual(AllnighterSupportRoot.support.path, explicit)
    }

    /// A project record that exists on disk but cannot be decoded must surface as
    /// an error. Reporting "you have no projects" when the truth is "I could not
    /// read them" is the misreport that seeded this incident.
    func testUnreadableProjectRecordThrowsInsteadOfVanishing() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-projectstore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ProjectStore(rootDirectory: root)
        let good = try store.add(path: NSTemporaryDirectory(), name: "Readable")
        XCTAssertEqual(try store.list().count, 1)

        // Corrupt the record in place — present, but unreadable.
        try Data("{ not json".utf8).write(to: root.appendingPathComponent("\(good.id).json"))

        XCTAssertThrowsError(try store.list(),
                             "an unreadable project record must not be silently dropped")
    }
}
