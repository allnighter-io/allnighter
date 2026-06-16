import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class PresetAndDoctorTests: XCTestCase {

    // MARK: - Honest stage-profile persistence (P06)

    private func sampleRun() -> TeamRun {
        TeamRun(
            id: "run1", prompt: "p", status: .answersIn,
            workers: [TestSupport.seat("model_opus")],
            workerAnswers: [WorkerAnswer(workerId: "model_opus#0", modelId: "model_opus", status: .done, output: "answer")],
            createdAt: Date()
        )
    }

    private func opus() -> Model {
        Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
    }

    private let combined = """
    ```json
    {"consensus":[],"contradictions":[],"partialCoverage":[],"uniqueInsights":[],"blindSpots":[],"failedWorkers":[]}
    ```
    ===PLAN===
    # Plan
    """

    func testStagesRecordTheProfileUsed() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: combined, exitCode: 0)])
        let synth = PlanWriter(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let stages = await synth.synthesize(
            run: sampleRun(), judge: opus(), manifest: manifest, models: [opus()],
            config: TestSupport.config(judge: "model_opus")
        )
        XCTAssertEqual(stages.first { $0.purpose == .analysis }?.promptProfileId, SynthesisInstructions.analysisID)
        XCTAssertEqual(stages.first { $0.purpose == .plan }?.promptProfileId, SynthesisInstructions.planID)
    }

    // MARK: - SynthesisInstructionStore

    func testInstructionStoreHasBuiltInJudgeProfiles() {
        let tmp = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = SynthesisInstructionStore(rootDirectory: tmp)
        let presets = store.load()
        XCTAssertNotNil(store.preset(id: SynthesisInstructions.analysisID))
        XCTAssertNotNil(store.preset(id: SynthesisInstructions.planID))
        XCTAssertTrue(presets.contains { $0.id == SynthesisInstructions.analysisID && $0.builtIn })
    }

    func testInstructionStoreSavesAndDeletesUserPresets() throws {
        let tmp = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = SynthesisInstructionStore(rootDirectory: tmp)
        let preset = SynthesisInstructionPreset(id: "mine_v1", displayName: "Mine", template: "Custom.")

        try store.save(preset)
        XCTAssertEqual(store.preset(id: "mine_v1")?.template, "Custom.")
        try store.delete(id: "mine_v1")
        XCTAssertNil(store.preset(id: "mine_v1"))
        XCTAssertNotNil(store.preset(id: SynthesisInstructions.planID))
    }

    // MARK: - PanelPresetStore (legacy council/workflow panel shape)

    func testPanelPresetStoreRoundTrips() throws {
        let tmp = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = PanelPresetStore(rootDirectory: tmp)
        XCTAssertTrue(store.load().isEmpty)

        let preset = PanelPreset(
            id: "p1", displayName: "My panel",
            workerSpecs: [WorkerSpec(modelId: "model_opus"), WorkerSpec(modelId: "model_grok")],
            synthesis: SynthesisConfig(analysisDepth: .separate, planWriterModelId: "model_opus", analysisProfileId: "plan_analysis_v1", planProfileId: "plan_writer_v1")
        )
        try store.save(preset)
        XCTAssertEqual(store.load().count, 1)
        XCTAssertEqual(store.load().first, preset)
        try store.delete(id: "p1")
        XCTAssertTrue(store.load().isEmpty)
    }

    func testWorkOrderPanelSummary() {
        let synthesis = SynthesisConfig(
            analysisDepth: .separate,
            planWriterModelId: "model_opus",
            analysisProfileId: "plan_analysis_v1",
            planProfileId: "plan_writer_v1"
        )
        let summary = WorkOrder.teamSummary(workerCount: 6, judgeLabel: "Opus", synthesis: synthesis, lensCount: 3)
        XCTAssertEqual(summary, "6 workers · Opus plan writer · separate analysis + plan · 3 lenses")
        XCTAssertFalse(summary.contains("est"))
        XCTAssertFalse(summary.contains("quota"))
    }

    func testWorkOrderDesignSummary() {
        let summary = WorkOrder.designSummary(outputCount: 4, engineNames: ["Grok", "Gemini"])
        XCTAssertEqual(summary, "4 mockups · Grok, Gemini")
    }

    // MARK: - Doctor

    func testDoctorHealthyModel() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "claude 1.2.3 READY", exitCode: 0)])
        let doctor = Doctor(commandRunner: mock)
        let worker = TestSupport.worker("model_opus", driverId: "claude_code")
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
        let worker = TestSupport.worker("model_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let d = await doctor.diagnose(worker, manifest: manifest)
        XCTAssertFalse(d.present)
        XCTAssertTrue(d.fixHint?.contains("Install") ?? false)
    }

    func testDoctorManualWorkerIsUnknownNotBroken() async {
        let doctor = Doctor(commandRunner: MockCommandRunner(scripts: [:]))
        let worker = TestSupport.worker("worker_manual", driverId: "manual")
        let manifest = DriverManifest(id: "manual", displayName: "Manual", kind: .manualPaste)
        let d = await doctor.diagnose(worker, manifest: manifest)
        XCTAssertEqual(d.kind, .manualPaste)
        XCTAssertEqual(d.health, .unknown)
        XCTAssertTrue(d.present)
    }

    func testDoctorNoManifestGivesDriverHint() async {
        let doctor = Doctor(commandRunner: MockCommandRunner(scripts: [:]))
        let worker = TestSupport.worker("worker_x", driverId: "ghost")
        let d = await doctor.diagnose(worker, manifest: nil)
        XCTAssertFalse(d.present)
        XCTAssertTrue(d.fixHint?.contains("ghost") ?? false)
    }

    func testDoctorAuthReasonMapsToAuthenticateHint() {
        let worker = TestSupport.worker("model_opus", driverId: "claude_code")
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let hint = Doctor.fixHint(for: .unhealthy(reason: "Error: please log in to continue"), model: worker, manifest: manifest)
        XCTAssertTrue(hint?.contains("authenticated") ?? false)
        XCTAssertTrue(hint?.contains("Log in") ?? false)
    }

    func testDoctorAllPreservesPanelOrder() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "READY", exitCode: 0)])
        let doctor = Doctor(commandRunner: mock)
        let models = [
            TestSupport.worker("a", driverId: "claude_code"),
            TestSupport.worker("b", driverId: "claude_code"),
            TestSupport.worker("c", driverId: "claude_code")
        ]
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let diagnoses = await doctor.diagnoseAll(models: models, registry: registry)
        XCTAssertEqual(diagnoses.map(\.modelId), ["a", "b", "c"])
    }

    private static func tempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-test-\(UUID().uuidString)", isDirectory: true)
    }
}
