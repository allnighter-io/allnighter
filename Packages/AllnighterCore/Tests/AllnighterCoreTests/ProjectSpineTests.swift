import XCTest
@testable import AllnighterCore

/// PRJ-S00 contract-packet tests: Codable round-trip (the JSON schema), root
/// normalization law, the proposal state machine, enum closedness, and the
/// model-level inference bans from `Project_Spine_And_Project_Manager.md`.
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
            defaultCodeTeamId: "code_core", managerThreadId: "thr_mgr", managerModelId: "model_opus"
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
            work: .init(pendingItems: ["pend_1"], openProposals: ["prop_1"]),
            workers: .init(readinessSummary: "2 ready", readyWorkerIds: ["w1"], blockedWorkerSummaries: ["grok: authRequired"]),
            proof: .init(commands: ["swift test"]), warnings: ["dirty tree"]))
        try roundTrip(ProjectManagerTurn(id: "turn_1", projectId: "prj_1", threadId: "thr_mgr",
                                         userMessageId: "msg_1", createdAt: t, mode: .propose,
                                         proposals: ["prop_1"],
                                         nextActions: [ProjectNextAction(kind: .approve, label: "Approve")]))
        try roundTrip(sampleProposal())
        try roundTrip(sampleWorkOrder())
        try roundTrip(WorkReturn(id: "ret_1", projectId: "prj_1", workOrderId: "wo_1", runId: "run_1",
                                 summary: "done", reportedFiles: ["a.swift"], status: .returned, createdAt: t))
        try roundTrip(VerificationRecord(id: "ver_1", projectId: "prj_1", workOrderId: "wo_1", returnId: "ret_1",
                                         outcome: .verified, proofResults: [ProofResult(command: "swift test", exitCode: 0)],
                                         gitObservation: GitObservation(head: "abc", committed: true), recommendation: "ship", createdAt: t))
    }

    private func sampleProposal() -> ProjectProposal {
        ProjectProposal(id: "prop_1", projectId: "prj_1", threadId: "thr_mgr", createdFromTurnId: "turn_1",
                        kind: .execute_slice, title: "Build PRJ-S00", scope: "Core models",
                        suggestedLane: .code, suggestedTeamId: "code_core", suggestedEffort: .high,
                        approval: ProjectApproval(approvedBy: "mike", approvedAt: t, approvedContentHash: "h1"),
                        baseGitHead: "abc", createdAt: t, updatedAt: t)
    }

    private func sampleWorkOrder() -> WorkOrder {
        WorkOrder(id: "wo_1", proposalId: "prop_1", projectId: "prj_1", title: "Build PRJ-S00",
                  lane: .code, mode: .dispatch, targetAgent: "codex", promptBody: "implement",
                  expectedReturn: "diff + proof", proofCommands: ["swift test"],
                  localRootPathSnapshot: "/Users/x/Allnighter", createdAt: t)
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

    // MARK: - Proposal state machine

    func testProposalStateMachineAllowsLegalTransitions() {
        XCTAssertTrue(ProposalStatus.proposed.canTransition(to: .approved))
        XCTAssertTrue(ProposalStatus.approved.canTransition(to: .running))
        XCTAssertTrue(ProposalStatus.running.canTransition(to: .returned))
        XCTAssertTrue(ProposalStatus.returned.canTransition(to: .verified))
        XCTAssertTrue(ProposalStatus.postponed.canTransition(to: .approved))
    }

    func testProposalStateMachineRejectsIllegalTransitions() {
        XCTAssertFalse(ProposalStatus.proposed.canTransition(to: .verified))   // can't skip the work
        XCTAssertFalse(ProposalStatus.running.canTransition(to: .approved))     // no going back
        XCTAssertFalse(ProposalStatus.verified.canTransition(to: .running))     // terminal
        XCTAssertFalse(ProposalStatus.cancelled.canTransition(to: .proposed))   // terminal
        XCTAssertTrue(ProposalStatus.verified.isTerminal)
        XCTAssertTrue(ProposalStatus.cancelled.isTerminal)
    }

    // MARK: - Enum closedness (hard cutover: canonical machine values only)

    func testCanonicalEnumRawValues() {
        XCTAssertEqual(ProposalKind.spec_explore.rawValue, "spec_explore")   // not spec_fanout
        XCTAssertNil(ProposalKind(rawValue: "spec_fanout"))
        XCTAssertEqual(WorkOrderLane.allCases.map(\.rawValue), ["code", "design", "copy", "none"])  // not build
        XCTAssertNil(WorkOrderLane(rawValue: "build"))
        XCTAssertEqual(ManagerTurnMode.allCases.map(\.rawValue).contains("delegate"), true)  // not fanout
        XCTAssertNil(ManagerTurnMode(rawValue: "fanout"))
        XCTAssertEqual(WorkerReadinessStatus.allCases.count, 8)
    }

    // MARK: - Inference bans (model-level)

    func testChatAnswerTurnCarriesNoProposal() {
        // Chat -> work order ban: a pure answer/orient turn never carries proposals.
        let answer = ProjectManagerTurn(id: "t", projectId: "p", threadId: "th", userMessageId: "m",
                                        createdAt: t, mode: .answer)
        XCTAssertTrue(answer.isWellFormed)
        let bad = ProjectManagerTurn(id: "t", projectId: "p", threadId: "th", userMessageId: "m",
                                     createdAt: t, mode: .answer, proposals: ["prop_1"])
        XCTAssertFalse(bad.isWellFormed)
    }

    func testDispatchTurnMustLinkAnApprovedWorkOrder() {
        let bad = ProjectManagerTurn(id: "t", projectId: "p", threadId: "th", userMessageId: "m",
                                     createdAt: t, mode: .dispatch)
        XCTAssertFalse(bad.isWellFormed)
        let ok = ProjectManagerTurn(id: "t", projectId: "p", threadId: "th", userMessageId: "m",
                                    createdAt: t, mode: .dispatch, handoff: ProjectHandoff(workOrderId: "wo_1"))
        XCTAssertTrue(ok.isWellFormed)
    }

    func testWorkOrderNeedsProofOrWaiverAndExpectedReturn() {
        var wo = sampleWorkOrder()
        XCTAssertTrue(wo.isDispatchReady)
        wo.proofCommands = []
        XCTAssertFalse(wo.isDispatchReady)               // no proof, no waiver
        wo.proofWaiver = "folder project; manual proof"
        XCTAssertTrue(wo.isDispatchReady)                // explicit waiver is enough
        wo.expectedReturn = ""
        XCTAssertFalse(wo.isDispatchReady)               // must name expected return
    }

    func testWorkerReturnDoneRequiresVerifiedOrWaiver() {
        XCTAssertTrue(VerificationOutcome.verified.isDone)
        XCTAssertTrue(VerificationOutcome.waived.isDone)
        XCTAssertFalse(VerificationOutcome.notVerified.isDone)
        XCTAssertFalse(VerificationOutcome.needsHuman.isDone)
    }

    func testNonGitFolderCannotClaimCommitVerification() {
        let folder = sampleProject(kind: .folder)
        let v = VerificationRecord(id: "v", projectId: folder.id, workOrderId: "wo", outcome: .verified,
                                   gitObservation: GitObservation(head: nil, committed: false), createdAt: t)
        XCTAssertFalse(v.claimsCommitVerification(project: folder))   // folder: never commit-verified
        let repo = sampleProject(kind: .gitRepo)
        let vc = VerificationRecord(id: "v2", projectId: repo.id, workOrderId: "wo", outcome: .verified,
                                    gitObservation: GitObservation(head: "abc", committed: true), createdAt: t)
        XCTAssertTrue(vc.claimsCommitVerification(project: repo))
    }

    func testMissingOrArchivedRootBlocksMutatingDispatch() {
        XCTAssertTrue(sampleProject().allowsMutatingDispatch)
        XCTAssertFalse(sampleProject(rootState: .missing).allowsMutatingDispatch)
        XCTAssertFalse(sampleProject(rootState: .permissionDenied).allowsMutatingDispatch)
        XCTAssertFalse(sampleProject(archived: true).allowsMutatingDispatch)
    }
}
