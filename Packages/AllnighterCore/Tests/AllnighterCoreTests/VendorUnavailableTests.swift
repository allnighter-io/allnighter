import XCTest
import AgentOSTeam
@testable import AllnighterCore

final class VendorUnavailableTests: XCTestCase {
    func testCursorComposerResourceExhaustedNamesModelUnavailableAndPreservesVendorText() throws {
        let raw = "RetriableError: [resource_exhausted] Error"
        let event = RunEvent(
            id: UUID().uuidString,
            seq: 1,
            ts: Date(),
            kind: RunEventKind.workerStatusChanged,
            payload: [
                "runId": .string("run_vendor_unavailable"),
                "workerId": .string("worker_1"),
                "modelId": .string("model_cursor_composer_25"),
                "to": .string(WorkerAnswerStatus.failed.rawValue),
                "reason": .string(raw),
            ]
        )

        let projected = try XCTUnwrap(NDJSONStreamProjector.LiveMapper().event(for: event))
        let error = try XCTUnwrap(projected.data.error)

        XCTAssertEqual(projected.event, "workerFailed")
        XCTAssertTrue(error.message.contains("Cursor's Composer 2.5 model is unavailable"))
        XCTAssertTrue(error.message.contains(raw), "the vendor's literal failure text remains in the payload")
    }

    func testSameVendorTextOnAnotherCatalogSourceIsUnchanged() throws {
        let raw = "RetriableError: [resource_exhausted] Error"
        let projected = try projectedFailure(modelId: "model_gpt_sol", reason: raw)

        XCTAssertEqual(projected.data.error?.message, raw,
                       "the Cursor-only recognizer is never consulted for another catalog source")
    }

    func testUnmatchedFailureAndUnrecordedModelStayByteForByteUnchanged() throws {
        let unmatched = "RetriableError: [other_failure] Error"
        XCTAssertEqual(try projectedFailure(modelId: "model_cursor_composer_25", reason: unmatched).data.error?.message,
                       unmatched)

        let cursorShaped = "RetriableError: [resource_exhausted] Error"
        XCTAssertEqual(try projectedFailure(modelId: "model_not_recorded", reason: cursorShaped).data.error?.message,
                       cursorShaped,
                       "a model with no catalog driver is unrecorded and changes nothing")
    }

    func testHistoricalProjectionAlsoPresentsCursorModelUnavailability() throws {
        let raw = "RetriableError: [resource_exhausted] Error"
        var run = try Fixtures.run(.runPartial)
        let failedAnswerIndex = try XCTUnwrap(run.answers.indices.first {
            run.answers[$0].result.status == .failed
        })
        let workerId = run.answers[failedAnswerIndex].memberId
        let workerIndex = try XCTUnwrap(run.workers.indices.first { run.workers[$0].id == workerId })
        run.answers[failedAnswerIndex].result.errorReason = raw
        run.workers[workerIndex].modelId = "model_cursor_composer_25"

        let failure = try XCTUnwrap(NDJSONStreamProjector.events(for: run).first {
            $0.event == "workerFailed" && $0.data.agentId == workerId
        })
        XCTAssertEqual(failure.data.error?.message,
                       "Cursor's Composer 2.5 model is unavailable. Vendor error: \(raw)")

        let floorError = try XCTUnwrap(FloorProjector.project(run).errors.first {
            $0.agentId == workerId
        })
        XCTAssertEqual(floorError.message,
                       "Cursor's Composer 2.5 model is unavailable. Vendor error: \(raw)")
    }

    private func projectedFailure(modelId: String, reason: String) throws -> NDJSONStreamProjector.Event {
        let event = RunEvent(
            id: UUID().uuidString,
            seq: 1,
            ts: Date(),
            kind: RunEventKind.workerStatusChanged,
            payload: [
                "runId": .string("run_vendor_unavailable"),
                "workerId": .string("worker_1"),
                "modelId": .string(modelId),
                "to": .string(WorkerAnswerStatus.failed.rawValue),
                "reason": .string(reason),
            ]
        )
        return try XCTUnwrap(NDJSONStreamProjector.LiveMapper().event(for: event))
    }
}
