import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class PresetAndDoctorTests: XCTestCase {

    // MARK: - Honest synthesis-instruction persistence (P05-S03)

    private func sampleRun() -> CouncilRun {
        CouncilRun(
            id: "run1",
            prompt: "p",
            status: .answersIn,
            panel: ["worker_opus"],
            members: [MemberResponse(workerId: "worker_opus", status: .done, output: "answer")],
            createdAt: Date()
        )
    }

    private func opus() -> Worker {
        Worker(id: "worker_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
    }

    func testCustomInstructionsArePersistedHonestly() async {
        // The Phase 04 seam: instructions were always written as the default id.
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "# Plan", exitCode: 0)])
        let synth = Synthesizer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let result = await synth.synthesize(
            run: sampleRun(), synthesizer: opus(), manifest: manifest, workers: [opus()],
            instructions: .custom("Summarize in three bullets only.")
        )
        XCTAssertEqual(result.instructions, "Summarize in three bullets only.")
        XCTAssertNotEqual(result.instructions, SynthesisInstructions.defaultID)
    }

    func testNamedPresetPersistsItsID() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "# Plan", exitCode: 0)])
        let synth = Synthesizer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let preset = SynthesisInstructionPreset(id: "terse_v1", displayName: "Terse", template: "Be terse.")

        let result = await synth.synthesize(
            run: sampleRun(), synthesizer: opus(), manifest: manifest, workers: [opus()],
            instructions: .preset(preset)
        )
        XCTAssertEqual(result.instructions, "terse_v1")
    }

    func testDefaultChoiceUsesBuiltInDefaultID() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "# Plan", exitCode: 0)])
        let synth = Synthesizer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let result = await synth.synthesize(run: sampleRun(), synthesizer: opus(), manifest: manifest, workers: [opus()])
        XCTAssertEqual(result.instructions, SynthesisInstructions.defaultID)
    }

    // MARK: - SynthesisInstructionStore

    func testInstructionStoreAlwaysHasBuiltInDefault() {
        let tmp = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = SynthesisInstructionStore(rootDirectory: tmp)
        let presets = store.load()
        XCTAssertEqual(presets.first?.id, SynthesisInstructions.defaultID)
        XCTAssertTrue(presets.first?.builtIn ?? false)
        XCTAssertNotNil(store.preset(id: SynthesisInstructions.defaultID))
    }

    func testInstructionStoreSavesAndDeletesUserPresets() throws {
        let tmp = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = SynthesisInstructionStore(rootDirectory: tmp)
        let preset = SynthesisInstructionPreset(id: "mine_v1", displayName: "Mine", template: "Custom.")

        try store.save(preset)
        XCTAssertEqual(store.preset(id: "mine_v1")?.template, "Custom.")
        XCTAssertTrue(store.load().contains { $0.id == "mine_v1" })

        try store.delete(id: "mine_v1")
        XCTAssertNil(store.preset(id: "mine_v1"))
        // Built-in survives deletion of user presets.
        XCTAssertNotNil(store.preset(id: SynthesisInstructions.defaultID))
    }

    // MARK: - PanelPresetStore

    func testPanelPresetStoreRoundTrips() throws {
        let tmp = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = PanelPresetStore(rootDirectory: tmp)
        XCTAssertTrue(store.load().isEmpty)

        let preset = PanelPreset(
            id: "p1", displayName: "My panel",
            panelWorkerIds: ["worker_opus", "worker_grok"],
            draftSynthesizerWorkerId: "worker_opus",
            draftSynthesisInstructionPresetId: "default_master_plan_v1"
        )
        try store.save(preset)
        XCTAssertEqual(store.load().count, 1)
        XCTAssertEqual(store.load().first, preset)

        try store.delete(id: "p1")
        XCTAssertTrue(store.load().isEmpty)
    }

    // MARK: - Doctor

    func testDoctorHealthyWorker() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "claude 1.2.3 READY", exitCode: 0)])
        let doctor = Doctor(commandRunner: mock)
        let worker = TestSupport.worker("worker_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let d = await doctor.diagnose(worker, manifest: manifest)
        XCTAssertTrue(d.present)
        XCTAssertNotNil(d.version)
        XCTAssertTrue(d.isHealthy)
        XCTAssertNil(d.fixHint)
    }

    func testDoctorMissingCLIGivesInstallHint() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(launchError: "command not found")])
        let doctor = Doctor(commandRunner: mock)
        let worker = TestSupport.worker("worker_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let d = await doctor.diagnose(worker, manifest: manifest)
        XCTAssertFalse(d.present)
        XCTAssertFalse(d.isHealthy)
        XCTAssertTrue(d.fixHint?.contains("Install") ?? false)
    }

    func testDoctorPresentButSmokeFailsGivesHint() async {
        // detect succeeds (exit 0) but the smoke token is absent -> unhealthy.
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "claude 1.2.3", exitCode: 0)])
        let doctor = Doctor(commandRunner: mock)
        let worker = TestSupport.worker("worker_opus", driverId: "claude_code", model: "opus")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let d = await doctor.diagnose(worker, manifest: manifest)
        XCTAssertTrue(d.present)
        XCTAssertFalse(d.isHealthy)
        XCTAssertNotNil(d.fixHint)
    }

    func testDoctorManualWorkerIsUnknownNotBroken() async {
        let mock = MockCommandRunner(scripts: [:])
        let doctor = Doctor(commandRunner: mock)
        let worker = TestSupport.worker("worker_manual", driverId: "manual")
        let manifest = DriverManifest(id: "manual", displayName: "Manual", kind: .manualPaste)

        let d = await doctor.diagnose(worker, manifest: manifest)
        XCTAssertEqual(d.kind, .manualPaste)
        XCTAssertEqual(d.health, .unknown)
        XCTAssertTrue(d.present)
    }

    func testDoctorNoManifestGivesDriverHint() async {
        let mock = MockCommandRunner(scripts: [:])
        let doctor = Doctor(commandRunner: mock)
        let worker = TestSupport.worker("worker_x", driverId: "ghost")

        let d = await doctor.diagnose(worker, manifest: nil)
        XCTAssertFalse(d.present)
        XCTAssertTrue(d.fixHint?.contains("ghost") ?? false)
    }

    func testDoctorAuthReasonMapsToAuthenticateHint() {
        let worker = TestSupport.worker("worker_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let hint = Doctor.fixHint(for: .unhealthy(reason: "Error: please log in to continue"), worker: worker, manifest: manifest)
        XCTAssertTrue(hint?.lowercased().contains("authenticat") ?? false)
        XCTAssertTrue(hint?.contains("claude login") ?? false)
    }

    func testDoctorAllPreservesPanelOrder() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "READY", exitCode: 0)])
        let doctor = Doctor(commandRunner: mock)
        let workers = [
            TestSupport.worker("a", driverId: "claude_code"),
            TestSupport.worker("b", driverId: "claude_code"),
            TestSupport.worker("c", driverId: "claude_code")
        ]
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let diagnoses = await doctor.diagnoseAll(workers: workers, registry: registry)
        XCTAssertEqual(diagnoses.map(\.workerId), ["a", "b", "c"])
    }

    private static func tempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("allnighter-test-\(UUID().uuidString)", isDirectory: true)
    }
}
