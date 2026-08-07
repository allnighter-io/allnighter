import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine
@testable import AllnighterCLI

/// CLI surface gates owned by `AllnighterCLI` (VSI-S05 export path).
final class AllnighterCLITests: XCTestCase {

    /// End-to-end export of a killed run that already has a stale prompt-only
    /// `bundle.md` on disk. Proves the partial path bypasses that file — a fix
    /// to `humanAnswer` alone would still print the prompt-only bundle.
    func testExportLabelsAndReturnsPartialAnswer() throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-cli-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }
        setenv("ALLNIGHTER_SUPPORT_DIR", support.path, 1)
        defer { unsetenv("ALLNIGHTER_SUPPORT_DIR") }

        let prompt = String(repeating: "PROMPT_ONLY_ECHO ", count: 80)
        let partial = "VSI_S05_EXPORT_PARTIAL_BODY — the work that must survive kill."
        let worker = Agent(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0)
        let run = TeamRun(
            id: "A6A06D63",
            prompt: prompt,
            status: .cancelled,
            workers: [worker],
            answers: [TeamAnswer(
                memberId: worker.id, modelId: worker.modelId, role: "answer",
                result: WorkerRunResult(status: .cancelled, output: partial))],
            createdAt: Date(),
            endReason: .killed
        )

        let store = RunStore()
        let dir = try store.save(run, models: [])
        // Incident shape: terminal save already wrote a prompt-first bundle.
        // Overwrite with prompt-only content so export cannot accidentally pass
        // by reading a regenerated bundle that already includes the partial.
        let staleBundle = "# Team Run\n\n## Prompt\n\n\(prompt)\n"
        try Data(staleBundle.utf8).write(to: dir.appendingPathComponent("bundle.md"))

        let onDiskBundle = try String(
            contentsOf: dir.appendingPathComponent("bundle.md"), encoding: .utf8)
        XCTAssertTrue(onDiskBundle.contains("PROMPT_ONLY_ECHO"))
        XCTAssertFalse(onDiskBundle.contains("VSI_S05_EXPORT_PARTIAL_BODY"))

        let exported = AllnighterCLI.exportMarkdown(
            for: run,
            models: [],
            manifests: [],
            existingBundle: onDiskBundle
        )

        XCTAssertTrue(exported.contains("Partial answer"), exported)
        XCTAssertTrue(exported.contains(partial), exported)
        XCTAssertFalse(
            exported.hasPrefix(staleBundle) || exported == staleBundle,
            "export must bypass the prompt-only bundle.md on the partial path"
        )
        // The labeled partial path must not be prompt-first (incident: 2,657
        // chars of echoed prompt and nothing else).
        let partialIdx = try XCTUnwrap(exported.range(of: "Partial answer")?.lowerBound)
        let promptIdx = exported.range(of: "PROMPT_ONLY_ECHO")?.lowerBound
        if let promptIdx {
            XCTAssertLessThan(partialIdx, promptIdx)
        }
    }

    /// QDR-S01 (Qwen driver bug report): a killed run's complete work sat in
    /// `answers[0].markdown` while `artifact` stayed null. `show --answer`
    /// retrieval must return that text — raw on stdout, partial labeled by the
    /// stderr note — for any run state that holds text.
    func testAnswerRetrievalReturnsKilledRunPartial() throws {
        let body = String(repeating: "QDR_S01_REVISED_DOC ", count: 400)
        let worker = Agent(id: "model_qwen_38_max#0", modelId: "model_qwen_38_max", instanceIndex: 0)
        let run = TeamRun(
            id: "QDR-KILLED",
            prompt: "Edit the file Docs/foo.md in place.",
            status: .cancelled,
            workers: [worker],
            answers: [TeamAnswer(
                memberId: worker.id, modelId: worker.modelId, role: "answer",
                result: WorkerRunResult(status: .cancelled, output: body))],
            createdAt: Date(),
            endReason: .killed
        )
        let trj = TeamRunJSONMapper.map(run, models: [], manifests: [], context: .init())
        XCTAssertEqual(trj.answer?.status, .cancelled, "VSI-S05 hoist precondition")

        let retrieval = try XCTUnwrap(AllnighterCLI.answerRetrieval(from: trj))
        XCTAssertEqual(retrieval.text, body, "stdout must be the raw answer text (redirect-clean)")
        let note = try XCTUnwrap(retrieval.note)
        XCTAssertTrue(note.contains("partial answer"), note)
        XCTAssertFalse(retrieval.text.contains("Partial answer"), "no label inside the body")
    }

    /// QDR-S01: a completed run retrieves without a partial note.
    func testAnswerRetrievalDoneRunHasNoNote() throws {
        let worker = Agent(id: "model_qwen_38_max#0", modelId: "model_qwen_38_max", instanceIndex: 0)
        let run = TeamRun(
            id: "QDR-DONE",
            prompt: "p",
            status: .complete,
            workers: [worker],
            answers: [TeamAnswer(
                memberId: worker.id, modelId: worker.modelId, role: "answer",
                result: WorkerRunResult(status: .done, output: "FINISHED_BODY"))],
            createdAt: Date()
        )
        let trj = TeamRunJSONMapper.map(run, models: [], manifests: [], context: .init())
        let retrieval = try XCTUnwrap(AllnighterCLI.answerRetrieval(from: trj))
        XCTAssertEqual(retrieval.text, "FINISHED_BODY")
        XCTAssertNil(retrieval.note)
    }

    /// QDR-S01: a run with no answer text retrieves nothing — the caller fails
    /// loud with RUN_NO_ANSWER instead of printing silence.
    func testAnswerRetrievalEmptyRunIsNil() throws {
        let worker = Agent(id: "model_qwen_38_max#0", modelId: "model_qwen_38_max", instanceIndex: 0)
        let run = TeamRun(
            id: "QDR-EMPTY",
            prompt: "p",
            status: .failed,
            workers: [worker],
            answers: [TeamAnswer(
                memberId: worker.id, modelId: worker.modelId, role: "answer",
                result: WorkerRunResult(status: .failed))],
            createdAt: Date()
        )
        let trj = TeamRunJSONMapper.map(run, models: [], manifests: [], context: .init())
        XCTAssertNil(AllnighterCLI.answerRetrieval(from: trj))
        XCTAssertNotNil(ContractRegistry.milestone1.errorSpec(for: "RUN_NO_ANSWER"))
    }
}
