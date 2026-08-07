import XCTest
import AgentOSCLI
import AllnighterCore
@testable import AllnighterEngine

final class OpenCodeOutcomeAuthorityTests: XCTestCase {
    private func signal(
        intent: OpenCodeRunIntent = .mutating,
        assistantText: String? = nil,
        toolOnlySummary: String? = nil,
        idleReason: OpenCodeIdleReason = .localIdle,
        promptEcho: Bool = false,
        foreignIdleDetected: Bool = false
    ) -> OpenCodeTurnSignal {
        OpenCodeTurnSignal(
            intent: intent,
            assistantText: assistantText,
            toolOnlySummary: toolOnlySummary,
            idleReason: idleReason,
            promptEcho: promptEcho,
            foreignIdleDetected: foreignIdleDetected,
            toolNames: toolOnlySummary == nil ? [] : ["write"]
        )
    }

    func testAssistantTextLocalIdleIsDone() {
        let v = OpenCodeOutcomeAuthority.resolve(
            signal: signal(assistantText: "- one\n- two"),
            repoDelta: nil,
            workerOutput: nil
        )
        XCTAssertEqual(v, .done(output: "- one\n- two"))
    }

    func testPromptEchoFails() {
        let v = OpenCodeOutcomeAuthority.resolve(
            signal: signal(promptEcho: true),
            repoDelta: RepoDelta(changed: true, commits: [.init(sha: "a", subject: "x")]),
            workerOutput: "echo"
        )
        XCTAssertEqual(v, .failed(reason: "incomplete_no_final_message"))
    }

    /// CT-13: non-local idleReason wins over promptEcho (matches AgentOS emitTerminal).
    func testNonLocalIdleReasonBeatsPromptEcho() {
        let v = OpenCodeOutcomeAuthority.resolve(
            signal: signal(idleReason: .streamDrop, promptEcho: true),
            repoDelta: nil,
            workerOutput: nil
        )
        XCTAssertEqual(v, .failed(reason: "stream_drop"))
    }

    /// CT-04: permission terminal + stale stream_drop signal must not rewrite.
    func testPreservesPermissionFailureDespiteStreamDropSignal() {
        var outcome = WorkerRunOutcome(
            status: .failed,
            errorKind: .permissionRequired,
            errorReason: "blockedOn: permission",
            openCodeTurnSignal: signal(idleReason: .streamDrop)
        )
        let verdict = OpenCodeOutcomeAuthority.resolve(
            signal: outcome.openCodeTurnSignal,
            repoDelta: nil,
            workerOutput: nil,
            existingErrorKind: outcome.errorKind,
            existingErrorReason: outcome.errorReason
        )
        XCTAssertNil(verdict, "authority must leave permission terminal alone")
        if let verdict {
            OpenCodeOutcomeAuthority.apply(verdict, to: &outcome)
        }
        XCTAssertEqual(outcome.errorKind, .permissionRequired)
        XCTAssertEqual(outcome.errorReason, "blockedOn: permission")
    }

    func testPreservesSessionErrorDespiteStreamDropSignal() {
        let verdict = OpenCodeOutcomeAuthority.resolve(
            signal: signal(idleReason: .streamDrop),
            repoDelta: nil,
            workerOutput: nil,
            existingErrorKind: .nonzeroExit,
            existingErrorReason: "opencode session error: boom"
        )
        XCTAssertNil(verdict)
    }

    func testForeignIdleFailsEvenWithCommits() {
        let v = OpenCodeOutcomeAuthority.resolve(
            signal: signal(
                toolOnlySummary: "Completed via 1 tool action",
                idleReason: .foreignIdle,
                foreignIdleDetected: true
            ),
            repoDelta: RepoDelta(changed: true, commits: [.init(sha: "a", subject: "x")]),
            workerOutput: nil
        )
        XCTAssertEqual(v, .failed(reason: "foreign_idle"))
    }

    /// F8: stall / stream-drop / timeout keep distinct errorReason strings.
    func testClassifiedIdleReasonsSurviveOutcomeAuthority() {
        XCTAssertEqual(
            OpenCodeOutcomeAuthority.resolve(
                signal: signal(idleReason: .stalledNoProgress),
                repoDelta: nil, workerOutput: nil),
            .failed(reason: "stalled_no_progress"))
        XCTAssertEqual(
            OpenCodeOutcomeAuthority.resolve(
                signal: signal(idleReason: .streamDrop),
                repoDelta: nil, workerOutput: nil),
            .failed(reason: "stream_drop"))
        XCTAssertEqual(
            OpenCodeOutcomeAuthority.resolve(
                signal: signal(idleReason: .timeout),
                repoDelta: nil, workerOutput: nil),
            .failed(reason: "timeout"))
    }

    /// 226CB771-shaped: tool-only + commit → done.
    func testToolOnlyWithCommitsIsDone() {
        let v = OpenCodeOutcomeAuthority.resolve(
            signal: signal(toolOnlySummary: "Completed via 2 tool actions with no closing message."),
            repoDelta: RepoDelta(
                changed: true,
                commits: [.init(sha: "abc", subject: "edit")],
                filesChanged: 1,
                files: ["f.swift"]
            ),
            workerOutput: nil
        )
        guard case .done(let out) = v else { return XCTFail("\(String(describing: v))") }
        XCTAssertEqual(out?.contains("2 tool"), true)
    }

    /// C1FBDB46-shaped: tool-only + dirty, no commit → incomplete_uncommitted.
    func testToolOnlyDirtyNoCommitIsIncompleteUncommitted() {
        let v = OpenCodeOutcomeAuthority.resolve(
            signal: signal(toolOnlySummary: "Completed via 1 tool action with no closing message."),
            repoDelta: RepoDelta(changed: false, worktreeDirty: true),
            workerOutput: nil
        )
        XCTAssertEqual(v, .failed(reason: "incomplete_uncommitted"))
    }

    func testToolOnlyCleanTreeFails() {
        let v = OpenCodeOutcomeAuthority.resolve(
            signal: signal(toolOnlySummary: "Completed via 1 tool action with no closing message."),
            repoDelta: RepoDelta(changed: false, worktreeDirty: false),
            workerOutput: nil
        )
        XCTAssertEqual(v, .failed(reason: "incomplete_no_final_message"))
    }

    func testNilSignalPassesThrough() {
        XCTAssertNil(OpenCodeOutcomeAuthority.resolve(
            signal: nil, repoDelta: nil, workerOutput: "x"))
    }

    func testApplyRewritesOutcome() {
        var outcome = WorkerRunOutcome(
            status: .failed, errorKind: .emptyOutput, errorReason: "incomplete_no_final_message",
            openCodeTurnSignal: signal(toolOnlySummary: "Completed via 1 tool action with no closing message.")
        )
        OpenCodeOutcomeAuthority.apply(
            .done(output: outcome.openCodeTurnSignal?.toolOnlySummary), to: &outcome)
        XCTAssertEqual(outcome.status, .done)
        XCTAssertNil(outcome.errorKind)
        XCTAssertEqual(outcome.output?.contains("1 tool"), true)
    }
}
