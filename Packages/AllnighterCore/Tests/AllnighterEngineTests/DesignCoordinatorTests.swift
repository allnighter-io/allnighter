import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

final class DesignCoordinatorTests: XCTestCase {

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agc-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a PNG to the prompt-directed save path for the listed workers; the
    /// rest "fail" (exit 1). Keyed by the prompt's persona so we can target seats.
    private struct ScriptedImageRunner: CommandRunner {
        /// persona ids that should succeed (write a file)
        let succeedPersonas: Set<String>
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                 workingDirectory: String?, timeout: Duration) async -> CommandResult {
            let prompt = args.first { $0.contains("Save the final image to") } ?? ""
            let persona = ["minimal", "bold", "editorial", "on_brand"].first { prompt.contains("\($0):") } ?? ""
            guard succeedPersonas.contains(persona),
                  let path = DesignImageRunner.firstCapture(prompt, pattern: #"Save the final image to (\S+)"#) else {
                return CommandResult(stderr: "engine refused", exitCode: 1)
            }
            try? Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: URL(fileURLWithPath: path))
            return CommandResult(stdout: "SESSION=s-\(persona)", exitCode: 0)
        }
    }

    private func imageModel(_ id: String) -> Model {
        Model(id: id, displayName: id, modelLabel: "m", driverId: "img")
    }

    private func registry() -> DriverRegistry {
        DriverRegistry([DriverManifest(
            id: "img", displayName: "Img", kind: .headlessCLI,
            invoke: .init(command: "img", args: ["-p", "{{prompt}}"]),
            imageGen: .init(args: ["-p", "{{prompt}}"],
                            promptTemplate: "Generate an image: {{designPrompt}}. Save the final image to {{imageOut}} and reply.",
                            arrival: .promptDirected, sessionIdRegex: #"SESSION=(\S+)"#)
        )])
    }

    private func workers() -> [Worker] {
        [Worker(id: "w1#0", modelId: "w1", instanceIndex: 0, skillId: "minimal"),
         Worker(id: "w2#0", modelId: "w2", instanceIndex: 0, skillId: "bold"),
         Worker(id: "w3#0", modelId: "w3", instanceIndex: 0, skillId: "editorial")]
    }

    func testAllSeatsRenderCompleteBoardInPanelOrder() async {
        let dir = tempDir()
        let runner = DesignImageRunner(commandRunner: ScriptedImageRunner(succeedPersonas: ["minimal", "bold", "editorial"]))
        let coordinator = DesignCoordinator(imageRunner: runner, registry: registry(), idFactory: { UUID().uuidString }, now: { Date(timeIntervalSince1970: 0) })
        let request = DesignRequest(prompt: "make it premium", personaIds: ["minimal", "bold", "editorial"], targetShape: .mobile)

        let run = await coordinator.generate(request: request, teamWorkers: workers(),
                                             models: [imageModel("w1"), imageModel("w2"), imageModel("w3")], runDir: dir)

        XCTAssertEqual(run.status, .complete)
        let board = run.latestStage(.board)?.payload?.board
        XCTAssertEqual(board?.options.count, 3)
        XCTAssertEqual(board?.options.map(\.persona), ["minimal", "bold", "editorial"])  // panel order
        XCTAssertEqual(board?.rendered.count, 3)
        XCTAssertEqual(board?.options.first?.sessionId, "s-minimal")
        XCTAssertTrue(run.workerAnswers.allSatisfy { $0.status == .done })
    }

    func testPartialBoardWhenSomeSeatsFail() async {
        let dir = tempDir()
        let runner = DesignImageRunner(commandRunner: ScriptedImageRunner(succeedPersonas: ["minimal"]))  // bold + editorial fail
        let coordinator = DesignCoordinator(imageRunner: runner, registry: registry())
        let request = DesignRequest(prompt: "x", personaIds: ["minimal", "bold", "editorial"], targetShape: .desktop)

        let run = await coordinator.generate(request: request, teamWorkers: workers(),
                                             models: [imageModel("w1"), imageModel("w2"), imageModel("w3")], runDir: dir)

        XCTAssertEqual(run.status, .partial)               // board still usable
        let board = run.latestStage(.board)?.payload?.board
        XCTAssertEqual(board?.rendered.count, 1)
        XCTAssertEqual(board?.options.filter { $0.status == .failed }.count, 2)
        XCTAssertEqual(run.workerAnswers.filter { $0.status == .failed }.count, 2)
    }

    func testNoSeatRendersIsFailedRun() async {
        let dir = tempDir()
        let runner = DesignImageRunner(commandRunner: ScriptedImageRunner(succeedPersonas: []))
        let coordinator = DesignCoordinator(imageRunner: runner, registry: registry())
        let request = DesignRequest(prompt: "x", personaIds: ["minimal", "bold"], targetShape: .mobile)
        let run = await coordinator.generate(request: request,
                                             teamWorkers: Array(workers().prefix(2)),
                                             models: [imageModel("w1"), imageModel("w2")], runDir: dir)
        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.latestStage(.board)?.payload?.board?.rendered.count, 0)
    }

    func testEventsStreamMemberAndStatusChanges() async {
        let dir = tempDir()
        let runner = DesignImageRunner(commandRunner: ScriptedImageRunner(succeedPersonas: ["minimal", "bold", "editorial"]))
        let coordinator = DesignCoordinator(imageRunner: runner, registry: registry())
        // Hoist into Sendable locals so the concurrent task captures no `self`.
        let request = DesignRequest(prompt: "x", personaIds: ["minimal"], targetShape: .mobile)
        let s = workers()
        let ws = [imageModel("w1"), imageModel("w2"), imageModel("w3")]

        async let runTask = coordinator.generate(request: request, teamWorkers: s, models: ws, runDir: dir)
        var kinds: [String] = []
        for await event in coordinator.events { kinds.append(event.kind) }
        _ = await runTask

        XCTAssertTrue(kinds.contains(RunEventKind.runStatusChanged))
        XCTAssertTrue(kinds.contains(RunEventKind.workerStatusChanged))
    }
}
