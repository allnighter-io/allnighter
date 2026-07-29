import XCTest
import AppKit
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

@MainActor
final class AppModelTests: XCTestCase {

    func testLoadsDefaultPanel() {
        let model = AppModel()
        XCTAssertGreaterThanOrEqual(model.models.count, 14)
        XCTAssertFalse(model.models.filter(\.enabled).isEmpty)
        XCTAssertFalse(model.isConfigurationBroken)
    }

    func testHasTieredPresets() {
        let model = AppModel()
        XCTAssertTrue(model.presets.contains { $0.id == "preset_fast" })
        XCTAssertTrue(model.presets.contains { $0.builtIn })
        // A preset is active by default and seats the panel.
        XCTAssertFalse(model.expandedAgents.isEmpty)
    }

    func testApplyPresetSetsSeatsSynthesisAndActiveId() {
        let model = AppModel()
        guard let quality = model.presets.first(where: { $0.id == "preset_quality" }) else { return XCTFail("no quality preset") }
        model.apply(quality)
        XCTAssertEqual(model.activePresetId, "preset_quality")
        XCTAssertEqual(model.currentSynthesis.analysisDepth, .separate)
        XCTAssertEqual(model.expandedAgents.count, quality.workerSpecs.expandedAgents().count)
    }

    func testSelfDoublePresetExpandsToMultipleSeats() {
        let model = AppModel()
        guard let selfDouble = model.presets.first(where: { $0.id == "preset_self_double" }) else { return }
        model.apply(selfDouble)
        XCTAssertEqual(model.expandedAgents.count, 3)
        XCTAssertEqual(Set(model.expandedAgents.map(\.modelId)).count, 1)
    }

    func testToggleWorkerEditsSeatsAndClearsPreset() {
        let model = AppModel()
        guard let worker = model.models.first else { return }
        let wasSeated = model.isSeated(worker)
        model.toggle(worker)
        XCTAssertNotEqual(model.isSeated(worker), wasSeated)
        XCTAssertNil(model.activePresetId)
    }

    func testJudgeResolvesToCanSynthesizeModel() {
        let model = AppModel()
        // Default panel includes Opus (role .both).
        if model.models.contains(where: { $0.canWritePlan }) {
            XCTAssertNotNil(model.planWriterModel)
            XCTAssertTrue(model.planWriterModel?.canWritePlan ?? false)
        }
    }

    func testTeamSummaryReflectsSeatsAndDepth() {
        let model = AppModel()
        let summary = model.runSummary
        // `runSummary` says "N agent(s)" — "worker" was retired from user-facing
        // copy in the vocab cutover. This assertion kept the old noun and had been
        // failing unnoticed, because the Mac test target is an Xcode target and is
        // not run by `swift test --package-path Packages/AllnighterCore`.
        XCTAssertTrue(summary.contains("\(model.expandedAgents.count) agent"), summary)
        if model.currentSynthesis.analysisDepth == .combined {
            XCTAssertTrue(summary.contains("combined analysis + plan"))
        } else {
            XCTAssertTrue(summary.contains("separate analysis + plan"))
        }
    }

    func testRunRequiresPrompt() {
        let model = AppModel()
        model.prompt = "   "
        model.runTeam()
        XCTAssertNil(model.run)
        XCTAssertFalse(model.isRunning)
    }

    func testBundleMarkdownEmptyWithoutRun() {
        let model = AppModel()
        XCTAssertTrue(model.bundleMarkdown().isEmpty)
    }

    func testManualAnswerNoOpWithoutRun() {
        let model = AppModel()
        model.setManualAnswer(workerId: "model_opus#0", text: "hi")
        XCTAssertNil(model.run)
    }

    func testQuickCapturePrefillsFromClipboardWhenEmpty() {
        let model = AppModel()
        model.prompt = ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("clipboard question", forType: .string)
        model.quickCapture(prefillClipboard: true)
        XCTAssertEqual(model.prompt, "clipboard question")
    }

    func testQuickCaptureDoesNotOverwriteExistingPrompt() {
        let model = AppModel()
        model.prompt = "already typed"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("clip", forType: .string)
        model.quickCapture(prefillClipboard: true)
        XCTAssertEqual(model.prompt, "already typed")
    }

    /// Launch Authority TCC hotfix (H0/H1/H6): the cold-launch cache load must
    /// NOT start live detection. The original code red was launch → runDetection
    /// → isDetecting = true → shell/CLI spawn → TCC prompt. Re-adding a probe to
    /// the launch path would flip isDetecting and fail this gate.
    func testLoadCachedSetupStateDoesNotStartDetection() {
        let model = AppModel()
        XCTAssertFalse(model.isDetecting)
        model.loadCachedSetupState()
        XCTAssertFalse(model.isDetecting, "cold-launch cache load must never start a live probe")
    }

    /// Authority gate (H1): a full probe that is not user-initiated must fall
    /// back to the quiet cache load instead of spawning.
    func testFullSetupProbeWithoutUserIntentDoesNotDetect() {
        let model = AppModel()
        model.runFullSetupProbe(userInitiated: false)
        XCTAssertFalse(model.isDetecting, "a non-user-initiated full probe must not spawn")
    }

    // MARK: - Census merge policy (C3)

    private func record(_ driver: String, ready: Bool, path: String? = nil) -> ToolProbeRecord {
        ToolProbeRecord(
            driverId: driver,
            status: ready ? .ready(version: "1.0") : .notInstalled,
            invocation: path.map { .direct(path: $0) },
            version: ready ? "1.0" : nil,
            lastProbeAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testCensusMergeNeverDowngradesReadyTool() {
        let existing = [record("claude_code", ready: true, path: "/x/claude")]
        let discovered = [record("claude_code", ready: false)]
        let merged = AppModel.mergedToolStatuses(existing: existing, discovered: discovered)
        XCTAssertTrue(merged.first { $0.driverId == "claude_code" }?.status.isSmokeReady ?? false,
                      "a ready tool must never be downgraded by a later census")
    }

    func testCensusMergeUpgradesNonReadyAndAppendsNew() {
        let existing = [record("claude_code", ready: true, path: "/x/claude"),
                        record("grok", ready: false)]
        let discovered = [record("grok", ready: true, path: "/x/grok"),       // upgrade
                          record("codex", ready: true, path: "/x/codex")]      // brand-new
        let merged = AppModel.mergedToolStatuses(existing: existing, discovered: discovered)
        let byId = Dictionary(uniqueKeysWithValues: merged.map { ($0.driverId, $0) })
        XCTAssertTrue(byId["grok"]?.status.isSmokeReady ?? false, "non-ready grok upgraded to ready")
        XCTAssertEqual(byId["codex"]?.invocation, .direct(path: "/x/codex"), "new driver appended")
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.prefix(2).map(\.driverId), ["claude_code", "grok"], "existing order preserved")
    }

    func testCensusMergeIgnoresUselessDiscovery() {
        let existing = [record("grok", ready: false)]
        // Discovered record has no ready status and no invocation → not an improvement.
        let discovered = [record("grok", ready: false)]
        let merged = AppModel.mergedToolStatuses(existing: existing, discovered: discovered)
        XCTAssertEqual(merged.count, 1)
        XCTAssertNil(merged.first?.invocation)
    }

    // MARK: - Gap detector (Track 0.3)

    func testUnresolvedSupportedTreatsNotInstalledAndMissingAsGaps() {
        let registry = AppConfig.loadDefaultRegistry()
        let supported = registry.all.filter { $0.kind == .headlessCLI }.map(\.id)
        guard let first = supported.first else { return XCTFail("no headless drivers") }

        // Only `first` is ready; the rest have no record → all-but-first are gaps.
        let gaps = AppCensusModel.unresolvedSupported(registry: registry, toolStatuses: [record(first, ready: true, path: "/x/\(first)")])
        XCTAssertEqual(Set(gaps), Set(supported).subtracting([first]),
                       "a ready tool is not a gap; every supported tool without a found record is")

        // Every tool notInstalled → every tool is a gap.
        let allNotInstalled = supported.map { ToolProbeRecord(driverId: $0, status: .notInstalled, lastProbeAt: Date(timeIntervalSince1970: 0)) }
        XCTAssertEqual(Set(AppCensusModel.unresolvedSupported(registry: registry, toolStatuses: allNotInstalled)), Set(supported))
    }

    func testNoGapWhenAllSupportedReady() {
        let registry = AppConfig.loadDefaultRegistry()
        let supported = registry.all.filter { $0.kind == .headlessCLI }.map(\.id)
        let allReady = supported.map { record($0, ready: true, path: "/x/\($0)") }
        XCTAssertTrue(AppCensusModel.unresolvedSupported(registry: registry, toolStatuses: allReady).isEmpty,
                      "no gaps when every supported tool is ready")
    }

    // MARK: - First-run gating (Track A)

    func testFirstRunGatingMarksCompletedOnceAndPersists() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("setup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = SetupStore(fileURL: tmp)

        let model = AppModel(setupStore: store)
        XCTAssertFalse(model.hasCompletedSetup, "a fresh install has not completed setup → launch opens setup")
        model.markSetupCompleted()
        XCTAssertTrue(model.hasCompletedSetup, "completion persists → launch stops auto-opening setup")
        model.markSetupCompleted() // idempotent

        // A new model reading the same store sees the persisted completion.
        XCTAssertTrue(AppModel(setupStore: store).hasCompletedSetup, "completion survives relaunch")
    }

    func testHistorySelectionDrivesDisplayRun() {
        let model = AppModel()
        let past = TeamRun(id: "r1", prompt: "old prompt", status: .complete, createdAt: Date())
        model.openHistory(past)
        XCTAssertEqual(model.displayRun?.id, "r1")
        model.closeHistory()
        XCTAssertNil(model.displayRun)
    }
}
