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
}
