import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class PresetAndDoctorTests: XCTestCase {

    // MARK: - Honest stage-profile persistence (P06)

    private func sampleRun() -> CouncilRun {
        CouncilRun(
            id: "run1", prompt: "p", status: .answersIn,
            panel: [TestSupport.seat("worker_opus")],
            members: [MemberResponse(seatId: "worker_opus#0", workerId: "worker_opus", status: .done, output: "answer")],
            createdAt: Date()
        )
    }

    private func opus() -> Worker {
        Worker(id: "worker_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
    }

    private let combined = """
    ```json
    {"consensus":[],"contradictions":[],"partialCoverage":[],"uniqueInsights":[],"blindSpots":[],"failedSeats":[]}
    ```
    ===PLAN===
    # Plan
    """

    func testStagesRecordTheProfileUsed() async {
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: combined, exitCode: 0)])
        let synth = Synthesizer(workerRunner: WorkerRunner(commandRunner: mock))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let stages = await synth.synthesize(
            run: sampleRun(), judge: opus(), manifest: manifest, workers: [opus()],
            config: TestSupport.config(judge: "worker_opus")
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

    // MARK: - PanelPresetStore (new seat-based shape)

    func testPanelPresetStoreRoundTrips() throws {
        let tmp = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = PanelPresetStore(rootDirectory: tmp)
        XCTAssertTrue(store.load().isEmpty)

        let preset = PanelPreset(
            id: "p1", displayName: "My panel",
            seats: [PanelSeatSpec(workerId: "worker_opus"), PanelSeatSpec(workerId: "worker_grok")],
            synthesis: SynthesisConfig(analysisDepth: .separate, judgeWorkerId: "worker_opus", analysisProfileId: "judge_analysis_v1", planProfileId: "judge_plan_v1")
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
            judgeWorkerId: "worker_opus",
            analysisProfileId: "judge_analysis_v1",
            planProfileId: "judge_plan_v1"
        )
        let summary = WorkOrder.panelSummary(seatCount: 6, judgeLabel: "Opus", synthesis: synthesis, lensCount: 3)
        XCTAssertEqual(summary, "6 seats · Opus judge · separate analysis + plan · 3 lenses")
        XCTAssertFalse(summary.contains("est"))
        XCTAssertFalse(summary.contains("quota"))
    }

    func testWorkOrderDesignSummary() {
        let summary = WorkOrder.designSummary(outputCount: 4, engineNames: ["Grok", "Gemini"])
        XCTAssertEqual(summary, "4 mockups · Grok, Gemini")
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
