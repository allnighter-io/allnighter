import XCTest
@testable import AllnighterCore
import AgentOSTeam

final class VendorSubstitutionPolicyTests: XCTestCase {
    private func model(_ id: String, driver: String) -> Model {
        Model(id: id, displayName: id, modelLabel: id, driverId: driver, role: .both)
    }

    private func parkedRun(
        origin: String,
        failedModelId: String = "model_fable",
        failedSource: String = "claude_code"
    ) -> TeamRun {
        TeamRun(
            id: "run-1",
            prompt: "work",
            status: .queued,
            phase: .waitingForVendor,
            presetId: TeamCatalog.defaultRunTeam()?.id,
            workers: [
                Agent(
                    id: "model_fable#0",
                    modelId: failedModelId,
                    instanceIndex: 0,
                    skillId: "first_principles_builder",
                    purpose: .answer
                ),
            ],
            createdAt: Date(),
            mutating: true,
            blocker: RunBlocker(
                resource: .vendorBackoff,
                quotaScope: failedSource,
                wakeAfter: Date().addingTimeInterval(7 * 24 * 60 * 60)
            ),
            attempts: [
                RunAttempt(
                    attemptNumber: 1,
                    requestedSourceId: failedSource,
                    requestedModelId: failedModelId,
                    resolvedSourceId: failedSource,
                    resolvedModelId: failedModelId,
                    startedAt: Date(),
                    endedAt: Date(),
                    selectionOrigin: origin
                ),
            ]
        )
    }

    private var settings: DefaultModelSettings {
        DefaultModelSettings(
            defaultTier: .frontier,
            allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_fable", "model_chatgpt"])
        )
    }

    func testAutoHopAllowedOnLongReset() {
        let run = parkedRun(origin: RunSelectionOrigin.auto)
        let models = [
            model("model_fable", driver: "claude_code"),
            model("model_chatgpt", driver: "codex"),
        ]
        let candidate = VendorSubstitutionPolicy.nextAutomaticCandidate(
            run: run,
            failedModelId: "model_fable",
            preset: TeamCatalog.defaultRunTeam()!,
            settings: settings,
            models: models,
            readyModels: models,
            coolingSourceIds: ["claude_code"],
            lane: .code
        )
        XCTAssertEqual(candidate?.modelId, "model_chatgpt")
        XCTAssertEqual(candidate?.selectionOrigin, RunSelectionOrigin.automaticSubstitute)
    }

    func testNamedWorkerHopRefused() {
        let run = parkedRun(origin: RunSelectionOrigin.explicit)
        let models = [
            model("model_fable", driver: "claude_code"),
            model("model_chatgpt", driver: "codex"),
        ]
        XCTAssertNil(
            VendorSubstitutionPolicy.nextAutomaticCandidate(
                run: run,
                failedModelId: "model_fable",
                preset: TeamCatalog.defaultRunTeam()!,
                settings: settings,
                models: models,
                readyModels: models,
                coolingSourceIds: ["claude_code"],
                lane: .code
            )
        )
    }

    func testVisitedSourceRefused() {
        var run = parkedRun(origin: RunSelectionOrigin.auto)
        run.attempts.append(
            RunAttempt(
                attemptNumber: 2,
                requestedSourceId: "codex",
                requestedModelId: "model_chatgpt",
                resolvedSourceId: "codex",
                resolvedModelId: "model_chatgpt",
                startedAt: Date(),
                endedAt: Date(),
                selectionOrigin: RunSelectionOrigin.automaticSubstitute,
                substitutionOfAttempt: 1
            )
        )
        let models = [
            model("model_fable", driver: "claude_code"),
            model("model_chatgpt", driver: "codex"),
            model("model_opus", driver: "grok"),
        ]
        XCTAssertNil(
            VendorSubstitutionPolicy.nextAutomaticCandidate(
                run: run,
                failedModelId: "model_chatgpt",
                preset: TeamCatalog.defaultRunTeam()!,
                settings: settings,
                models: models,
                readyModels: models,
                coolingSourceIds: ["codex"],
                lane: .code
            )
        )
    }

    func testIncompatibleCandidateRefused() {
        let run = parkedRun(origin: RunSelectionOrigin.auto)
        let models = [
            model("model_fable", driver: "claude_code"),
            model("model_chatgpt_sol", driver: "cursor_agent"),
        ]
        XCTAssertNil(
            VendorSubstitutionPolicy.nextAutomaticCandidate(
                run: run,
                failedModelId: "model_fable",
                preset: TeamCatalog.defaultRunTeam()!,
                settings: settings,
                models: models,
                readyModels: models,
                coolingSourceIds: ["claude_code"],
                lane: .code
            )
        )
    }

    func testHopBoundRefused() {
        var run = parkedRun(origin: RunSelectionOrigin.auto)
        for number in 2...4 {
            run.attempts.append(
                RunAttempt(
                    attemptNumber: number,
                    requestedSourceId: "codex",
                    requestedModelId: "model_chatgpt",
                    resolvedSourceId: "codex",
                    resolvedModelId: "model_chatgpt",
                    startedAt: Date(),
                    endedAt: Date(),
                    selectionOrigin: RunSelectionOrigin.automaticSubstitute,
                    substitutionOfAttempt: number - 1
                )
            )
        }
        let models = [
            model("model_fable", driver: "claude_code"),
            model("model_chatgpt", driver: "codex"),
            model("model_opus", driver: "grok"),
        ]
        XCTAssertFalse(VendorSubstitutionPolicy.canHopAgain(from: run.attempts))
        XCTAssertNil(
            VendorSubstitutionPolicy.nextAutomaticCandidate(
                run: run,
                failedModelId: "model_chatgpt",
                preset: TeamCatalog.defaultRunTeam()!,
                settings: settings,
                models: models,
                readyModels: models,
                coolingSourceIds: ["codex"],
                lane: .code
            )
        )
    }

    func testShortKnownResetPrefersParkOverSubstitution() {
        let soon = Date().addingTimeInterval(5 * 60)
        XCTAssertFalse(
            VendorSubstitutionPolicy.prefersSubstitutionOverPark(
                wakeAfter: soon,
                observation: nil
            )
        )
        XCTAssertTrue(
            VendorSubstitutionPolicy.prefersSubstitutionOverPark(
                wakeAfter: nil,
                observation: nil
            )
        )
        XCTAssertTrue(
            VendorSubstitutionPolicy.prefersSubstitutionOverPark(
                wakeAfter: Date().addingTimeInterval(3 * 60 * 60),
                observation: nil
            )
        )
    }

    func testSubstitutionsOffWaitsSameSource() {
        var off = settings
        off.allowHealthySubstitutions = false
        let run = parkedRun(origin: RunSelectionOrigin.auto)
        let models = [
            model("model_fable", driver: "claude_code"),
            model("model_chatgpt", driver: "codex"),
        ]
        XCTAssertNil(
            VendorSubstitutionPolicy.nextAutomaticCandidate(
                run: run,
                failedModelId: "model_fable",
                preset: TeamCatalog.defaultRunTeam()!,
                settings: off,
                models: models,
                readyModels: models,
                coolingSourceIds: ["claude_code"],
                lane: .code
            )
        )
    }

    func testManualCandidatesIncludeCompatibleReadyModels() {
        let run = parkedRun(origin: RunSelectionOrigin.explicit)
        let models = [
            model("model_fable", driver: "claude_code"),
            model("model_chatgpt", driver: "codex"),
            model("model_opus", driver: "grok"),
        ]
        let candidates = VendorSubstitutionPolicy.manualCandidates(
            run: run,
            failedModelId: "model_fable",
            preset: TeamCatalog.defaultRunTeam()!,
            settings: settings,
            models: models,
            readyModels: models,
            coolingSourceIds: ["claude_code"],
            lane: .code
        )
        XCTAssertEqual(candidates.map(\.id), ["model_chatgpt", "model_opus"])
    }
}
