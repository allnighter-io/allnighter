import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// ATL-S03 — Loop launch surface: validation + detached start wiring. Starts via
/// `alln loop start --no-wait` (LVC v7, `docs/phases/Loop_Verb_Cutover.md`).
@MainActor
final class RelayLaunchViewModelTests: XCTestCase {
    private func tempRoot(_ label: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-relay-launch-\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func repoRoot() -> String {
        tempRoot("repo").path
    }

    // MARK: - Validation

    func testValidationRequiresKickoffDocAndSeats() {
        let issues = RelayLaunchViewModel.validate(
            kickoffMessage: "  ",
            docPath: "",
            pmModelId: nil,
            devModelId: nil,
            maxRounds: 20
        )
        XCTAssertTrue(issues.contains { $0.id == "kickoff" })
        XCTAssertTrue(issues.contains { $0.id == "doc" })
        XCTAssertTrue(issues.contains { $0.id == "pm" })
        XCTAssertTrue(issues.contains { $0.id == "dev" })
    }

    func testValidationRejectsSameSeatForBothRoles() {
        let issues = RelayLaunchViewModel.validate(
            kickoffMessage: "Ship it",
            docPath: "docs/spec.md",
            pmModelId: "model_x",
            devModelId: "model_x",
            maxRounds: 20
        )
        XCTAssertTrue(issues.contains { $0.id == "same-seat" })
    }

    func testValidationRejectsNonPositiveMaxRounds() {
        let issues = RelayLaunchViewModel.validate(
            kickoffMessage: "Ship it",
            docPath: "docs/spec.md",
            pmModelId: "a",
            devModelId: "b",
            maxRounds: 0
        )
        XCTAssertTrue(issues.contains { $0.id == "max-rounds" })
    }

    func testCanStartTrueOnlyWhenValid() {
        let config = AppConfig.loadConfiguration()
        let vm = RelayLaunchViewModel(
            projectId: "prj_test", projectRoot: repoRoot(),
            models: config.models, registry: config.registry, readyModels: []
        )
        XCTAssertFalse(vm.canStart)
        vm.kickoffMessage = "Ship the parser fix."
        vm.docPath = "docs/spec.md"
        vm.pmModelId = "pm_worker"
        vm.devModelId = "dev_worker"
        XCTAssertTrue(vm.canStart)
    }

    // MARK: - Detached start

    func testStartReturnsRelayIdFromDetachedAccept() async {
        let config = AppConfig.loadConfiguration()
        let stateStore = RelayStateStore(
            rootDirectory: tempRoot("detach").appendingPathComponent("relay", isDirectory: true)
        )
        let vm = RelayLaunchViewModel(
            projectId: "prj_test", projectRoot: repoRoot(),
            models: config.models, registry: config.registry, readyModels: [],
            initialKickoffMessage: "Ship the parser fix.",
            stateStore: stateStore,
            detachedLaunch: { _, _ in .accepted(id: "relay_detached_test", pid: 4242) }
        )
        vm.docPath = "docs/spec.md"
        vm.pmModelId = "pm_worker"
        vm.devModelId = "dev_worker"

        let relayId = await vm.start()
        XCTAssertEqual(relayId, "relay_detached_test")
        XCTAssertFalse(vm.isStarting)
    }

    func testStartRefusesWhenPreflightFindsActiveRelay() async throws {
        let config = AppConfig.loadConfiguration()
        let root = tempRoot("dup")
        let stateStore = RelayStateStore(rootDirectory: root.appendingPathComponent("relay", isDirectory: true))
        let projectRoot = repoRoot()
        let vm = RelayLaunchViewModel(
            projectId: "prj_test", projectRoot: projectRoot,
            models: config.models, registry: config.registry, readyModels: [],
            initialKickoffMessage: "Ship it",
            stateStore: stateStore,
            detachedLaunch: { _, _ in XCTFail("must not spawn when preflight refuses"); return .accepted(id: "nope", pid: 1) }
        )
        vm.docPath = "docs/spec.md"
        vm.pmModelId = "pm_worker"
        vm.devModelId = "dev_worker"

        let existing = RelayState(
            id: "relay_existing_active", projectRoot: projectRoot, docPath: "docs/spec.md",
            pmModelId: "pm_worker", devModelId: "dev_worker",
            status: .running, createdAt: Date()
        )
        try stateStore.save(existing)

        let relayId = await vm.start()
        XCTAssertNil(relayId)
        XCTAssertEqual(vm.startRefusalIssue?.id, "already-active")
    }

    func testStartMapsDetachedAlreadyActiveRefusal() async {
        let config = AppConfig.loadConfiguration()
        let vm = RelayLaunchViewModel(
            projectId: "prj_test", projectRoot: repoRoot(),
            models: config.models, registry: config.registry, readyModels: [],
            initialKickoffMessage: "Ship it",
            detachedLaunch: { _, _ in
                .refused(code: "RELAY_ALREADY_ACTIVE", message: "duplicate relay on doc")
            }
        )
        vm.docPath = "docs/spec.md"
        vm.pmModelId = "pm_worker"
        vm.devModelId = "dev_worker"

        let relayId = await vm.start()
        XCTAssertNil(relayId)
        XCTAssertEqual(vm.startRefusalIssue?.id, "already-active")
    }

    func testStartReturnsNilWhenInvalid() async {
        let config = AppConfig.loadConfiguration()
        let vm = RelayLaunchViewModel(
            projectId: "prj_test", projectRoot: repoRoot(),
            models: config.models, registry: config.registry, readyModels: []
        )
        let relayId = await vm.start()
        XCTAssertNil(relayId)
    }

    func testRelayDetachedLauncherStripsNoWaitFromChildArgv() {
        let parent = [
            "loop", "start", "Ship it", "--spec", "docs/a.md", "--no-wait", "--json", "--delivery", "wake",
        ]
        XCTAssertEqual(
            RelayDetachedLauncher.childArguments(from: parent),
            ["loop", "start", "Ship it", "--spec", "docs/a.md", "--json"]
        )
    }

    func testRelayStartArgumentsUsesLoopStartGrammar() {
        let args = RelayDetachedLauncher.relayStartArguments(
            docPath: "docs/spec.md",
            projectId: "prj_test",
            pmModelId: "pm_worker",
            devModelId: "dev_worker",
            kickoffMessage: "Ship the parser fix.",
            maxRounds: 20,
            until: nil
        )
        XCTAssertEqual(args, [
            "loop", "start", "Ship the parser fix.",
            "--spec", "docs/spec.md",
            "--project", "prj_test",
            "--pm", "pm_worker",
            "--dev", "dev_worker",
            "--max-rounds", "20",
            "--no-wait", "--json",
        ])
    }
}
