#if DEBUG
import Foundation
import AllnighterCore

/// Designer-mock Project Manager exchange for the GUI proof (DEBUG only — never real
/// data). A realistic propose → approve → verify slice on the halo-app limiter.
enum ProjectManagerCardsSample {
    static let now = Date(timeIntervalSince1970: 1_750_000_000)

    static let answer = """
    The limiter is in `limiter/bucket.go` and currently drops over-limit requests with
    a bare **503**. The public API contract (and the open issue #214) wants a **429 +
    `Retry-After`**. The tree is clean at `abc1234`; `swift test` is green. One bounded
    move gets us there.
    """

    static let proposal = ProjectProposal(
        id: "prop_sample", projectId: "prj_halo", threadId: "mgr_thread_prj_halo", createdFromTurnId: "mgr_s",
        kind: .execute_slice, status: .proposed,
        title: "Return 429 + Retry-After on rate limit",
        whyNow: "Issue #214 is the only open blocker for the public launch; the limiter already computes the reset window, so this is a small, contained change.",
        userGoal: "Ship a spec-compliant public rate limiter.",
        currentTruth: ["limiter/bucket.go drops with 503", "reset window already computed", "tree clean at abc1234"],
        scope: "Map over-limit to HTTP 429 and set Retry-After from the existing reset window. One handler + one test.",
        nonGoals: ["No change to the bucket algorithm", "No new config surface"],
        likelyFilesOrAreas: ["limiter/bucket.go", "limiter/bucket_test.go"],
        risks: ["Clients that special-case 503 may need a note in the changelog"],
        suggestedLane: .code, suggestedEffort: .med,
        baseGitHead: "abc1234def5", createdAt: now, updatedAt: now)

    static let order = WorkOrder(
        id: "wo_sample", proposalId: "prop_sample", projectId: "prj_halo",
        title: "Return 429 + Retry-After on rate limit",
        lane: .code, mode: .reveal, targetSourceId: "codex",
        promptBody: "# Return 429 + Retry-After on rate limit\n\nScope: map over-limit to HTTP 429 and set Retry-After from the existing reset window. One handler + one test.\n\nNon-goals: bucket algorithm changes; new config.",
        scope: "One handler + one test.", nonGoals: ["No bucket changes"],
        expectedReturn: "A diff implementing the scope, plus the output of the declared proof commands.",
        proofCommands: ["go test ./limiter/...", "go vet ./..."], proofWaiver: nil,
        baseGitHead: "abc1234def5", localRootPathSnapshot: "/Users/jd/dev/halo-app", createdAt: now)

    static let answerTurn = ProjectManagerTurn(
        id: "mgr_ans", projectId: "prj_halo", threadId: "mgr_thread_prj_halo", userMessageId: "u1",
        createdAt: now, mode: .answer, answerMarkdown: answer, modelId: "model_opus")

    /// The seeded live-conversation timeline for the pm-live proof.
    static var proofItems: [ProjectManagerViewModel.Item] {
        [.answer(answerTurn), .proposal(proposal), .workOrder(order), .verification(verification)]
    }

    static let verification = VerificationRecord(
        id: "ver_sample", projectId: "prj_halo", workOrderId: "wo_sample", returnId: "ret_sample",
        outcome: .verified,
        proofResults: [
            ProofResult(command: "go test ./limiter/...", exitCode: 0, outputTail: "ok  limiter  0.4s", durationSeconds: 0.4),
            ProofResult(command: "go vet ./...", exitCode: 0, outputTail: "", durationSeconds: 0.2),
        ],
        gitObservation: GitObservation(head: "def5678", committed: true, dirty: false),
        scopeFindings: [], docsDriftFindings: [], missingProof: [],
        recommendation: "All declared proof passed. Safe to mark done.", createdAt: now)
}
#endif
