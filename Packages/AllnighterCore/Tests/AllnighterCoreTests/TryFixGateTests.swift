import XCTest
@testable import AllnighterCore

/// The Try Fix gate blocks on DANGER, never on DOUBT (Try_Fix_Auto_Implement). A
/// low-confidence or T3 packet still runs; a danger flag / missing hypothesis / missing
/// proof / bad executor blocks. The fix-attempt prompt is a disciplined one-round order.
final class TryFixGateTests: XCTestCase {

    private func goodExecutor() -> TryFixGate.ExecutorFacts {
        .init(teamId: "build_slice", exists: true, isMutating: true, isRunnable: true, workerCount: 1)
    }

    private func packet(
        hyp: [FixPacket.Hypothesis] = [.init(id: "h1", cause: "c", fix: "f", fixBoundary: "b")],
        proof: FixPacket.ProofMethod = .userObservation, command: String? = nil,
        truthOwner: String = "owner", danger: [String] = [],
        confidence: FixPacket.Confidence = .high, tier: String? = nil
    ) -> FixPacket {
        FixPacket(symptom: "s", truthOwner: truthOwner, hypotheses: hyp,
                  proofMethod: proof, proofCommand: command,
                  confidenceOrdering: confidence, tier: tier, dangerFlags: danger)
    }

    func testLowConfidenceStillRuns() {
        // The whole point: doubt does not block.
        let d = TryFixGate.evaluate(packet: packet(confidence: .low), executor: goodExecutor())
        XCTAssertEqual(d, .allowed(topHypothesisId: "h1"))
    }

    func testT3CriticalStillRuns() {
        let d = TryFixGate.evaluate(packet: packet(tier: "T3 Critical"), executor: goodExecutor())
        XCTAssertTrue(d.isAllowed)
    }

    func testUserObservationProofIsEnough() {
        let d = TryFixGate.evaluate(packet: packet(proof: .userObservation), executor: goodExecutor())
        XCTAssertTrue(d.isAllowed, "an honest 'the user can see it' proof is allowed")
    }

    func testDangerFlagBlocks() {
        let d = TryFixGate.evaluate(packet: packet(danger: ["credentials"]), executor: goodExecutor())
        XCTAssertEqual(d, .blocked(code: "TRY_FIX_PACKET_UNSAFE", reason: "danger flag(s): credentials"))
    }

    func testMissingPacketBlocks() {
        XCTAssertEqual(TryFixGate.evaluate(packet: nil, executor: goodExecutor()),
                       .blocked(code: "TRY_FIX_PACKET_MISSING", reason: "answer run produced no typed fix packet"))
    }

    func testNoActionableHypothesisBlocks() {
        let d = TryFixGate.evaluate(packet: packet(hyp: [.init(id: "h1", cause: "c", fix: "", fixBoundary: "")]),
                                    executor: goodExecutor())
        if case .blocked(let code, _) = d { XCTAssertEqual(code, "TRY_FIX_PACKET_UNSAFE") } else { XCTFail() }
    }

    func testCommandProofWithoutCommandBlocks() {
        let d = TryFixGate.evaluate(packet: packet(proof: .command, command: nil), executor: goodExecutor())
        if case .blocked(let code, _) = d { XCTAssertEqual(code, "TRY_FIX_PACKET_UNSAFE") } else { XCTFail() }
    }

    func testNonMutatingExecutorBlocks() {
        let exec = TryFixGate.ExecutorFacts(teamId: "code_plan", exists: true, isMutating: false, isRunnable: true, workerCount: 1)
        if case .blocked(let code, _) = TryFixGate.evaluate(packet: packet(), executor: exec) {
            XCTAssertEqual(code, "TRY_FIX_EXECUTOR_INVALID")
        } else { XCTFail() }
    }

    func testMultiWorkerExecutorBlocks() {
        let exec = TryFixGate.ExecutorFacts(teamId: "x", exists: true, isMutating: true, isRunnable: true, workerCount: 3)
        if case .blocked(let code, _) = TryFixGate.evaluate(packet: packet(), executor: exec) {
            XCTAssertEqual(code, "TRY_FIX_EXECUTOR_INVALID")
        } else { XCTFail() }
    }

    // MARK: - Prompt

    func testFixAttemptPromptIsDisciplined() {
        let p = packet(hyp: [.init(id: "h1", cause: "reader reads string first", experiment: "log types",
                                   fix: "read image before string", fixBoundary: "ComposerPasteboardReader")],
                       proof: .command, command: "swift test --filter PasteTests")
        var pk = p; pk.ruledOut = ["Edit-menu wiring (present)"]; pk.seam = "AppKit↔SwiftUI"
        let prompt = FixAttemptPrompt.assemble(originalReport: "paste drops images", packet: pk, hypothesis: pk.hypotheses[0])
        XCTAssertTrue(prompt.contains("read image before string"))
        XCTAssertTrue(prompt.contains("ComposerPasteboardReader"))
        XCTAssertTrue(prompt.contains("AppKit↔SwiftUI"))
        XCTAssertTrue(prompt.contains("Edit-menu wiring (present)"), "ruled-out memory is carried in")
        XCTAssertTrue(prompt.contains("swift test --filter PasteTests"))
        XCTAssertTrue(prompt.contains("STOP"), "must instruct stop-on-conflict / stop-on-fail")
        XCTAssertTrue(prompt.contains("only this hypothesis") || prompt.contains("ONLY this hypothesis"))
    }

    func testPromptUserObservationWhenNoCommand() {
        let prompt = FixAttemptPrompt.assemble(originalReport: "x", packet: packet(proof: .userObservation),
                                               hypothesis: packet().hypotheses[0])
        XCTAssertTrue(prompt.contains("no automated proof"))
    }
}
