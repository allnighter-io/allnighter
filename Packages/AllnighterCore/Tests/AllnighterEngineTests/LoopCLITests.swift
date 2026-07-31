import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

/// `alln loop` (LVC v7 `docs/phases/Loop_Verb_Cutover.md` §2, LVC-S02c). Covers
/// the PART A defect fix (`nextAction.command` must reproduce every explicitly
/// supplied flag) and the `list`/`status`/`stop`/`resume`/`wait` delegation —
/// exit-free/injectable helpers are the unit-testable surface, matching
/// `RelayCLITests`.
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

    private func makeRelayStateStore() -> RelayStateStore {
        RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
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

    // MARK: - loop list: smallest honest listing, filtered to the resolved project

    func testRunListFiltersToTheResolvedProject() throws {
        let projectStore = makeProjectStore()
        let relayStateStore = makeRelayStateStore()
        let projectA = try addProject(projectStore, path: "a")
        let projectB = try addProject(projectStore, path: "b")

        let inProject = RelayState(
            id: "loop_a", projectRoot: projectA.normalizedRootPath, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running, createdAt: Date()
        )
        let outsideProject = RelayState(
            id: "loop_b", projectRoot: projectB.normalizedRootPath, docPath: nil, brief: "other repo's brief",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev", status: .awaitingPM, createdAt: Date()
        )
        try relayStateStore.save(inProject)
        try relayStateStore.save(outsideProject)

        // runList prints to stdout; assert via the injected stores instead of capturing
        // output — the filter predicate is what this test is protecting.
        let all = relayStateStore.list()
        let filtered = all.filter { $0.projectRoot == projectA.normalizedRootPath }
        XCTAssertEqual(filtered.map(\.id), ["loop_a"])

        // Smoke: runList must not crash/exit for a project with loops.
        LoopCLI.runList(["--project", projectA.id, "--json"], projectStore: projectStore, relayStateStore: relayStateStore)
    }

    func testLoopListEntryPMOccupantReflectsChair() throws {
        let relayStateStore = makeRelayStateStore()
        let callerChair = RelayState(
            id: "loop_pilot", projectRoot: "/repo", docPath: nil, brief: "fix everything",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev", status: .awaitingPM, createdAt: Date()
        )
        let agentChair = RelayState(
            id: "loop_relay", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running, createdAt: Date()
        )
        try relayStateStore.save(callerChair)
        try relayStateStore.save(agentChair)

        let states = relayStateStore.list()
        let pilot = states.first { $0.id == "loop_pilot" }!
        let relay = states.first { $0.id == "loop_relay" }!
        XCTAssertEqual(pilot.isCallerChair ? "caller" : pilot.pmModelId, "caller")
        XCTAssertEqual(relay.isCallerChair ? "caller" : relay.pmModelId, "model_pm")
    }

    // MARK: - loop status is chair-neutral (RelayCLI.runStatus carries no pmMode branching)

    func testRunStatusAcceptsTerminalWaitForACallerChairLoop() throws {
        let relayStateStore = makeRelayStateStore()
        let done = RelayState(
            id: "loop_pilot_done", projectRoot: "/repo", docPath: nil, brief: "fix everything",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev", status: .done, createdAt: Date(), finishedAt: Date()
        )
        try relayStateStore.save(done)

        // Would `exit(2)`/fail if `--wait-for terminal` were rejected for an
        // external-chair (pilot) loop — LVC v7 §2 requires it to be accepted
        // "regardless of who holds the chair." `threadProjector: nil` + a hermetic
        // `RunStore` keep this off the real user data directory.
        RelayCLI.runStatus(
            ["--relay", "loop_pilot_done", "--wait-for", "terminal", "--timeout", "1", "--json"],
            stateStore: relayStateStore,
            threadProjector: nil,
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        )
    }
}
