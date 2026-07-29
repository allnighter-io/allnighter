import XCTest
@testable import AllnighterCore

/// PRJ-S00 contract-packet tests: Codable round-trip (the JSON schema), root
/// normalization law, enum closedness, and model-level invariants from
/// `Project_Spine_And_Project_Manager.md`.
final class ProjectSpineTests: XCTestCase {

    // Whole-second timestamps so ISO-8601 (.iso8601) round-trips are exact.
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    private func roundTrip<T: Codable & Equatable>(_ value: T, _ file: StaticString = #filePath, _ line: UInt = #line) throws {
        let data = try CoreJSON.encode(value)
        let decoded = try CoreJSON.decode(T.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }

    private func sampleProject(kind: ProjectKind = .gitRepo, rootState: RootState = .available, archived: Bool = false) -> Project {
        Project(
            id: "prj_1", displayName: "Allnighter", localRootPath: "/Users/x/Allnighter",
            normalizedRootPath: "/Users/x/Allnighter", kind: kind, rootState: rootState,
            gitBranch: "feat/x", gitHead: "abc123", createdAt: t, lastOpenedAt: t,
            archived: archived, docsEntrypoints: ["AGENTS.md"], proofCommands: ["bash scripts/check.sh"],
            defaultCodeTeamId: "code_plan", managerThreadId: "thr_mgr", managerModelId: "model_opus"
        )
    }

    // MARK: - Codable round-trip (the schema contract; enum-keyed/nested are the risk)

    func testAllModelsRoundTrip() throws {
        try roundTrip(sampleProject())
        try roundTrip(ProjectWorkerReadiness(projectId: "prj_1", sourceId: "claude", workerId: "w1",
                                             status: .needsProjectAuthorization, checkedAt: t, probeKind: .silent,
                                             setupHint: "Trust the folder in Claude Code."))
        try roundTrip(ProjectContextPacket(
            id: "pkt_1", projectId: "prj_1", generatedAt: t,
            root: .init(localRootPath: "/Users/x/Allnighter", kind: .gitRepo, rootState: .available),
            git: .init(branch: "feat/x", head: "abc", recentCommits: ["abc tidy"]),
            docs: .init(entrypoints: ["AGENTS.md"], staleCandidates: ["OLD.md"]),
            threads: .init(managerThreadId: "thr_mgr", unresolvedQuestions: ["which lane?"]),
            work: .init(pendingItems: ["pend_1"]),
            workers: .init(readinessSummary: "2 ready", readyWorkerIds: ["w1"], blockedWorkerSummaries: ["grok: authRequired"]),
            proof: .init(commands: ["swift test"]), warnings: ["dirty tree"]))
        try roundTrip(ProjectNextAction(kind: .projectContext, label: "Project context"))
    }

    // MARK: - Root normalization law

    func testRootNormalizationCollapsesAndExpands() {
        let n = RootNormalization.normalize("/a/b/../c/./d")
        XCTAssertEqual(n.displayPath, "/a/c/d")
        let home = RootNormalization.normalize("~/proj")
        XCTAssertTrue(home.displayPath.hasPrefix("/"))
        XCTAssertTrue(home.displayPath.hasSuffix("/proj"))
        XCTAssertFalse(home.displayPath.contains("~"))
    }

    func testSameRootIsTheDuplicateKey() {
        XCTAssertTrue(RootNormalization.sameRoot("/a/b", "/a/b/"))      // trailing slash
        XCTAssertTrue(RootNormalization.sameRoot("/a/b/../b", "/a/b"))  // collapse
        XCTAssertFalse(RootNormalization.sameRoot("/a/b", "/a/b/c"))    // nested != same Project
    }

    func testSymlinkResolvesIntoTheKeyButNotTheDisplay() throws {
        // Real symlink: the key resolves it (so symlink and target are the same
        // Project); the display preserves the path the user typed.
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-\(UUID().uuidString)")
        let real = base.appendingPathComponent("real")
        let link = base.appendingPathComponent("link")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? fm.removeItem(at: base) }

        XCTAssertTrue(RootNormalization.sameRoot(link.path, real.path))      // same Project root
        let n = RootNormalization.normalize(link.path)
        XCTAssertTrue(n.displayPath.hasSuffix("/link"))                       // display keeps the symlink
        XCTAssertTrue(n.key.hasSuffix("/real"))                              // key resolves it
    }

    func testObserveRootStateIsObservedNotInvented() throws {
        let dir = NSTemporaryDirectory()
        XCTAssertEqual(RootNormalization.observeRootState(key: RootNormalization.normalize(dir).key), .available)
        XCTAssertEqual(RootNormalization.observeRootState(key: "/no/such/root/\(UUID().uuidString)"), .missing)
    }

    // MARK: - Enum closedness (hard cutover: canonical machine values only)

    func testCanonicalEnumRawValues() {
        XCTAssertEqual(NextActionKind.allCases.map(\.rawValue),
                       ["addProject", "projectContext", "listThreads", "listPending", "recheckModels", "openProject"])
        XCTAssertEqual(WorkerReadinessStatus.allCases.count, 8)
    }

    func testMissingOrArchivedRootBlocksMutatingRun() {
        XCTAssertTrue(sampleProject().allowsMutatingRun)
        XCTAssertFalse(sampleProject(rootState: .missing).allowsMutatingRun)
        XCTAssertFalse(sampleProject(rootState: .permissionDenied).allowsMutatingRun)
        XCTAssertFalse(sampleProject(archived: true).allowsMutatingRun)
    }
}
