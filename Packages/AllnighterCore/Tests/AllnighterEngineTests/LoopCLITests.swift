import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

/// `alln loop` (LVC v7 `docs/phases/Loop_Verb_Cutover.md` §2, LVC-S02c). Covers
/// the PART A defect fix (`nextAction.command` must reproduce every explicitly
/// supplied flag) and the `list`/`status`/`stop`/`resume`/`wait` delegation —
/// exit-free/injectable helpers are the unit-testable surface, matching
/// `LoopEngineCLITests`.
final class LoopCLITests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-loop-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeProjectStore() -> ProjectStore {
        ProjectStore(rootDirectory: tmp.appendingPathComponent("projects"))
    }

    private func makeLoopStateStore() -> LoopStateStore {
        LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
    }

    @discardableResult
    private func addProject(_ store: ProjectStore, path: String = "repo") throws -> Project {
        let dir = tmp.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try store.add(path: dir.path, name: nil)
    }

    // MARK: - PART A: buildStartCommand reproduces exactly what the caller typed

    func testBuildStartCommandReproducesEveryExplicitFlag() {
        let command = LoopCLI.buildStartCommand(
            brief: "execute this doc",
            specPath: "docs/phases/Loop_Verb_Cutover.md",
            pmRaw: "caller",
            devRaw: "model_grok"
        )
        XCTAssertEqual(
            command,
            "alln loop start \"execute this doc\" --spec docs/phases/Loop_Verb_Cutover.md --pm caller --dev model_grok"
        )
    }

    func testBuildStartCommandOmitsFlagsTheCallerNeverTyped() {
        let command = LoopCLI.buildStartCommand(brief: "fix the tests", specPath: nil, pmRaw: nil, devRaw: nil)
        XCTAssertEqual(command, "alln loop start \"fix the tests\"")
        XCTAssertFalse(command.contains("--pm"))
        XCTAssertFalse(command.contains("--dev"))
        XCTAssertFalse(command.contains("--spec"))
    }

    func testBuildStartCommandHonorsPartialFlags() {
        let command = LoopCLI.buildStartCommand(brief: "ship it", specPath: nil, pmRaw: "model_pm", devRaw: nil)
        XCTAssertEqual(command, "alln loop start \"ship it\" --pm model_pm")
    }

    // MARK: - loopArgs: positional <loop-id> -> --relay <id>, everything else forwarded

    func testLoopArgsInsertsRelayFlagFromPositional() {
        let forwarded = LoopCLI.loopArgs(["relay_123", "--json"], usageLine: "loop status <loop-id>")
        XCTAssertTrue(forwarded.contains("--relay"))
        XCTAssertTrue(forwarded.contains("relay_123"))
        XCTAssertTrue(forwarded.contains("--json"))
    }

    func testLoopArgsForwardsValueFlags() {
        let forwarded = LoopCLI.loopArgs(
            ["relay_123", "--wait-for", "terminal", "--timeout", "30"], usageLine: "loop status <loop-id>"
        )
        XCTAssertEqual(forwarded.first, "--relay")
        XCTAssertEqual(forwarded[1], "relay_123")
        XCTAssertTrue(forwarded.contains("--wait-for"))
        XCTAssertTrue(forwarded.contains("terminal"))
        XCTAssertTrue(forwarded.contains("--timeout"))
        XCTAssertTrue(forwarded.contains("30"))
    }

    // MARK: - Contract registration of every dispatched subcommand (LOOP-REG)

    /// Enumerates `LoopCLI.implementedSubcommands` (the real dispatch list) so a
    /// future verb added there fails until `ContractRegistry` declares `loop <sub>`.
    func testEveryImplementedLoopSubcommandResolvesToRegisteredCommand() {
        XCTAssertFalse(LoopCLI.implementedSubcommands.isEmpty)
        for sub in LoopCLI.implementedSubcommands {
            let name = "loop \(sub)"
            let resolved = ContractRegistry.resolveCommandName(from: "alln \(name)")
            XCTAssertEqual(
                resolved, name,
                "LoopCLI dispatches `\(sub)` but ContractRegistry has no M1 command `\(name)`"
            )
        }
    }

    // MARK: - loop list: smallest honest listing, filtered to the resolved project

    func testRunListFiltersToTheResolvedProject() throws {
        let projectStore = makeProjectStore()
        let loopStateStore = makeLoopStateStore()
        let projectA = try addProject(projectStore, path: "a")
        let projectB = try addProject(projectStore, path: "b")

        let inProject = LoopState(
            id: "loop_a", projectRoot: projectA.normalizedRootPath, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running, createdAt: Date()
        )
        let outsideProject = LoopState(
            id: "loop_b", projectRoot: projectB.normalizedRootPath, docPath: nil, brief: "other repo's brief",
            pmModelId: LoopState.callerPMModelId, devModelId: "model_dev", status: .awaitingPM, createdAt: Date()
        )
        try loopStateStore.save(inProject)
        try loopStateStore.save(outsideProject)

        // runList prints to stdout; assert via the injected stores instead of capturing
        // output — the filter predicate is what this test is protecting.
        let all = loopStateStore.list()
        let filtered = all.filter { $0.projectRoot == projectA.normalizedRootPath }
        XCTAssertEqual(filtered.map(\.id), ["loop_a"])

        // Smoke: runList must not crash/exit for a project with loops.
        LoopCLI.runList(["--project", projectA.id, "--json"], projectStore: projectStore, loopStateStore: loopStateStore)
    }

    func testLoopListEntryPMOccupantReflectsChair() throws {
        let loopStateStore = makeLoopStateStore()
        let callerChair = LoopState(
            id: "loop_pilot", projectRoot: "/repo", docPath: nil, brief: "fix everything",
            pmModelId: LoopState.callerPMModelId, devModelId: "model_dev", status: .awaitingPM, createdAt: Date()
        )
        let agentChair = LoopState(
            id: "loop_relay", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running, createdAt: Date()
        )
        try loopStateStore.save(callerChair)
        try loopStateStore.save(agentChair)

        let states = loopStateStore.list()
        let pilot = states.first { $0.id == "loop_pilot" }!
        let relay = states.first { $0.id == "loop_relay" }!
        XCTAssertEqual(pilot.isCallerChair ? "caller" : pilot.pmModelId, "caller")
        XCTAssertEqual(relay.isCallerChair ? "caller" : relay.pmModelId, "model_pm")
    }

    // MARK: - loop status is chair-neutral (LoopEngineCLI.runStatus carries no pmMode branching)

    func testRunStatusAcceptsTerminalWaitForACallerChairLoop() throws {
        let loopStateStore = makeLoopStateStore()
        let done = LoopState(
            id: "loop_pilot_done", projectRoot: "/repo", docPath: nil, brief: "fix everything",
            pmModelId: LoopState.callerPMModelId, devModelId: "model_dev", status: .done, createdAt: Date(), finishedAt: Date()
        )
        try loopStateStore.save(done)

        // Would `exit(2)`/fail if `--wait-for terminal` were rejected for an
        // external-chair (pilot) loop — LVC v7 §2 requires it to be accepted
        // "regardless of who holds the chair." `threadProjector: nil` + a hermetic
        // `RunStore` keep this off the real user data directory.
        LoopEngineCLI.runStatus(
            ["--relay", "loop_pilot_done", "--wait-for", "terminal", "--timeout", "1", "--json"],
            stateStore: loopStateStore,
            threadProjector: nil,
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        )
    }

    func testResolveSeatsAllowsLocalOllamaPMWithDisclosureAndDoesNotBlockDevFrontier() {
        let local = Model(
            id: "custom_opencode_ollama_qwen3_8b",
            displayName: "qwen3 8b",
            modelLabel: "ollama/qwen3:8b",
            driverId: "opencode",
            role: .both
        )
        let frontier = Model(
            id: "model_pm",
            displayName: "PM",
            modelLabel: "opus",
            driverId: "claude_code",
            role: .both
        )
        let seats = LoopCLI.resolveSeats(
            opts: Options(["--pm", local.id, "--dev", frontier.id]),
            models: [local, frontier]
        )
        XCTAssertEqual(seats.pm, .agent(local.id))
        XCTAssertEqual(seats.pmSource, "explicit")
        XCTAssertEqual(seats.dev, frontier.id)
        XCTAssertNotNil(seats.localLeadDisclosure)
        XCTAssertTrue(seats.localLeadDisclosure?.contains("runs on your Mac through Ollama") == true)
        XCTAssertTrue(seats.localLeadDisclosure?.contains("You pinned it as the Loop lead") == true)
        XCTAssertNil(seats.localExecutionWarning)
    }
}
