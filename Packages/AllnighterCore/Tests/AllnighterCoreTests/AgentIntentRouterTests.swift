import XCTest
@testable import AllnighterCore

/// IR-S01 / IR-S02 golden transcripts for `alln team hello --for`
/// (`Agent_Intent_Router.md`), including IR-S02b Decision 10 lifecycle bundles.
final class AgentIntentRouterTests: XCTestCase {

    private var allReady: [ReadyTeam] {
        BuiltInTeams.all.map {
            ReadyTeam(lane: $0.lane.rawValue, team: $0.id, displayName: $0.displayName)
        }
    }

    /// Explicit ready verdict — fake `Model(id: "m1"…)` does not staff teams.
    private var readyVerdict: AgentReadiness.Verdict {
        AgentReadiness.Verdict(
            canStartTeamRun: true,
            readyTeams: allReady,
            blockedReason: nil,
            nextAction: AgentNextAction(kind: "startTeamRun", tool: "team_start")
        )
    }

    private func route(_ intent: String, ready: [ReadyTeam]? = nil) -> AgentIntentRouter.Payload {
        AgentIntentRouter.route(
            intent: intent,
            teams: BuiltInTeams.all,
            readyTeams: ready ?? allReady,
            readyModels: [],
            canStartTeamRun: true
        )
    }

    private func assertResolves(_ command: AgentIntentRouter.RunnableCommand?, file: StaticString = #filePath, line: UInt = #line) {
        let display = command?.display ?? ""
        XCTAssertNotNil(ContractRegistry.resolveCommandName(from: display),
                        "lifecycle display must resolve: \(display)", file: file, line: line)
        let argvJoined = (command?.argv ?? []).joined(separator: " ")
        XCTAssertNotNil(ContractRegistry.resolveCommandName(from: argvJoined),
                        "lifecycle argv must resolve: \(argvJoined)", file: file, line: line)
    }

    // MARK: - Taxonomy golden rows

    func testHardenSpecRoutesToSpecReviewDefault() {
        let p = route("harden this spec before I build")
        XCTAssertEqual(p.recommended?.kind, "team")
        XCTAssertEqual(p.recommended?.teamId, "code_spec_review")
        let argv = p.recommended?.command?.argv ?? []
        XCTAssertEqual(Array(argv.prefix(5)),
                       ["alln", "team", "start", "--team", "code_spec_review"])
        XCTAssertTrue(argv.contains("--json"))
        XCTAssertFalse(p.nextActions.isEmpty)
    }

    func testSpecReviewDefaultHasDepthAlternatesMinAndMax() {
        let p = route("harden this spec before I build")
        XCTAssertEqual(p.recommended?.teamId, "code_spec_review")
        XCTAssertEqual(
            Set(p.recommended?.depthAlternates ?? []),
            Set(["code_spec_review_min", "code_spec_review_max"]),
            "tiered Spec Review must surface Min+Max as depthAlternates")
    }

    func testGrowthBuildersLoveRoutesToGrowth() {
        let p = route("how do we get X builders to love this")
        XCTAssertEqual(p.recommended?.teamId, "code_growth")
        XCTAssertEqual(p.recommended?.kind, "team")
    }

    func testCrashCauseRoutesToBugHuntDefault() {
        let p = route("find the real cause of this crash")
        XCTAssertEqual(p.recommended?.teamId, "code_bug_hunt")
    }

    func testRewriteLandingRoutesToCopyLanding() {
        let p = route("rewrite my landing page")
        XCTAssertEqual(p.recommended?.teamId, "copy_landing")
    }

    func testUntieredFamilyHasEmptyDepthAlternates() {
        let security = route("is this secure? credentials permissions exposure")
        XCTAssertEqual(security.recommended?.teamId, "code_security_review")
        XCTAssertEqual(security.recommended?.depthAlternates ?? ["sentinel"], [],
                       "untiered Security Review must not invent Min/Max")

        let copy = route("write clearer more persuasive copy for our product")
        XCTAssertEqual(copy.recommended?.teamId, "copy_core")
        XCTAssertEqual(copy.recommended?.depthAlternates ?? ["sentinel"], [],
                       "untiered Copy Core must not invent Min/Max")
    }

    // MARK: - Primitives (IR-S02)

    func testRelayOvernightRoutesToPairRelay() {
        let p = route("keep building overnight without me")
        XCTAssertEqual(p.recommended?.kind, "relay")
        let argv = p.recommended?.command?.argv ?? []
        XCTAssertEqual(Array(argv.prefix(3)), ["alln", "pair", "relay"])
        XCTAssertTrue(argv.contains("--json"))
    }

    func testPilotSuperviseRoutesToPairPilot() {
        let p = route("have another model BUILD this while I supervise")
        XCTAssertEqual(p.recommended?.kind, "pilot")
        let argv = p.recommended?.command?.argv ?? []
        XCTAssertEqual(Array(argv.prefix(4)), ["alln", "pair", "pilot", "start"])
    }

    // MARK: - Lifecycle bundle (IR-S02b / Decision 10)

    func testSpecReviewLifecycleResolvesViaRegistry() throws {
        let p = route("harden this spec before I build")
        let life = try XCTUnwrap(p.lifecycle)
        XCTAssertEqual(life.monitor?.argv,
                       ["alln", "team", "status", "<run-id>", "--json"])
        XCTAssertEqual(life.result?.argv,
                       ["alln", "team", "result", "<run-id>", "--json"])
        XCTAssertEqual(life.cancel?.argv,
                       ["alln", "team", "cancel", "<run-id>", "--json"])
        assertResolves(life.monitor)
        assertResolves(life.result)
        assertResolves(life.cancel)
        XCTAssertEqual(ContractRegistry.resolveCommandName(from: life.monitor!.display), "team status")
        XCTAssertEqual(ContractRegistry.resolveCommandName(from: life.result!.display), "team result")
        XCTAssertEqual(ContractRegistry.resolveCommandName(from: life.cancel!.display), "team cancel")
    }

    func testRelayLifecyclePresentAndCancelResolves() throws {
        let p = route("keep building overnight without me")
        let life = try XCTUnwrap(p.lifecycle)
        XCTAssertEqual(life.monitor?.argv,
                       ["alln", "pair", "relay-status", "--relay", "<run-id>", "--json"])
        XCTAssertEqual(life.result?.argv, life.monitor?.argv,
                       "relay-status is both monitor and terminal truth owner")
        XCTAssertEqual(life.cancel?.argv, ["alln", "kill", "<run-id>", "--json"])
        assertResolves(life.monitor)
        assertResolves(life.cancel)
        XCTAssertEqual(ContractRegistry.resolveCommandName(from: life.cancel!.display), "kill")
    }

    func testPilotLifecyclePresentAndCancelResolves() throws {
        let p = route("have another model BUILD this while I supervise")
        let life = try XCTUnwrap(p.lifecycle)
        XCTAssertEqual(life.monitor?.argv,
                       ["alln", "pair", "pilot", "status", "--relay", "<run-id>", "--json"])
        XCTAssertEqual(life.result?.argv, life.monitor?.argv)
        XCTAssertEqual(life.cancel?.argv, ["alln", "kill", "<run-id>", "--json"])
        assertResolves(life.monitor)
        assertResolves(life.cancel)
        XCTAssertEqual(ContractRegistry.resolveCommandName(from: life.monitor!.display), "pair pilot status")
        XCTAssertEqual(ContractRegistry.resolveCommandName(from: life.cancel!.display), "kill")
    }

    func testNoMatchHasNoLifecycle() {
        let p = route("asdf qwerty zxcvbn totally nonsense intent 999")
        XCTAssertNil(p.lifecycle)
        XCTAssertEqual(p.readiness.code, "INTENT_NO_MATCH")
    }

    func testWorkerNameUnknownHasNoLifecycle() {
        let p = route("ask ModelZorch999 for feedback")
        XCTAssertNil(p.lifecycle)
        XCTAssertEqual(p.readiness.code, "WORKER_NAME_UNKNOWN")
    }

    // MARK: - Named worker + read-only (field probe)

    func testFieldProbeChatGPTSolReadOnlyPinsCodexNative() {
        let p = route("ask ChatGPT 5.6 Sol for read-only feedback on these two docs")
        XCTAssertEqual(p.recommended?.kind, "chat")
        XCTAssertEqual(p.requestedWorker?.resolvedModelId, "model_chatgpt",
                       "native Codex Sol, not Cursor model_chatgpt_sol")
        XCTAssertTrue(
            p.requestedWorker?.alternates.contains("model_chatgpt_sol") == true,
            "Cursor Sol must appear as a loud alternate")
        let posture = p.recommended?.safetyPosture ?? ""
        if posture == "readOnly" {
            // Codex mechanically enforces — preferred.
        } else {
            XCTAssertEqual(posture, "advisoryReadOnly")
            XCTAssertTrue(
                (p.recommended?.why ?? "").uppercased().contains("ADVISORY"),
                "advisory posture must say ADVISORY in why")
        }
        let argv = p.recommended?.command?.argv ?? []
        XCTAssertFalse(argv.isEmpty, "command must be present")
        XCTAssertTrue(argv.contains("--worker"))
        if let idx = argv.firstIndex(of: "--worker") {
            XCTAssertEqual(argv[idx + 1], "model_chatgpt")
        }
        // Read-only / advisory keeps final-only `--json` (honest; not a progress lie).
        XCTAssertTrue(argv.contains("--json"), "read-only ask may keep --json final envelope")
        XCTAssertFalse(argv.contains("--stream"))
        XCTAssertNotNil(p.lifecycle?.cancel)
        XCTAssertNil(p.lifecycle?.monitor, "chat progress is the launch transport, not a poll verb")
        assertResolves(p.lifecycle?.cancel)
    }

    func testMutatingChatAskUsesStreamNotFinalOnlyJSON() {
        let p = route("ask ChatGPT 5.6 Sol to refactor this module")
        XCTAssertEqual(p.recommended?.kind, "chat")
        XCTAssertEqual(p.recommended?.safetyPosture, "mutating")
        let argv = p.recommended?.command?.argv ?? []
        XCTAssertTrue(argv.contains("--stream"),
                      "mutating chat must teach --stream as progress transport")
        XCTAssertFalse(argv.contains("--json"),
                       "mutating chat must not teach final-only --json as progress")
        XCTAssertNotNil(p.lifecycle?.cancel)
        XCTAssertNil(p.lifecycle?.monitor)
        XCTAssertNil(p.lifecycle?.result)
        assertResolves(p.lifecycle?.cancel)
    }

    func testBareSolReadOnlyResolvesToCodexWhenUnambiguous() {
        let p = route("ask Sol for a read-only take")
        XCTAssertEqual(p.recommended?.kind, "chat")
        XCTAssertEqual(p.requestedWorker?.resolvedModelId, "model_chatgpt")
        XCTAssertTrue(p.requestedWorker?.alternates.contains("model_chatgpt_sol") == true)
        let posture = p.recommended?.safetyPosture ?? ""
        XCTAssertTrue(posture == "readOnly" || posture == "advisoryReadOnly")
        if posture == "advisoryReadOnly" {
            XCTAssertTrue((p.recommended?.why ?? "").uppercased().contains("ADVISORY"))
        }
        let argv = p.recommended?.command?.argv ?? []
        XCTAssertTrue(argv.contains("--worker"))
        if let idx = argv.firstIndex(of: "--worker") {
            XCTAssertEqual(argv[idx + 1], "model_chatgpt")
        }
    }

    func testNonsenseWorkerNameUnknownWithNextActions() {
        let p = route("ask ModelZorch999 for feedback")
        XCTAssertEqual(p.readiness.code, "WORKER_NAME_UNKNOWN")
        XCTAssertFalse(p.nextActions.isEmpty, "no-empty-silence on unknown worker")
        XCTAssertNil(p.requestedWorker?.resolvedModelId)
        XCTAssertEqual(p.requestedWorker?.requestedName, "ModelZorch999")
    }

    // MARK: - Overlap / no-match

    func testUIBrokenOverlapWinsGUIBugHunt() {
        // Deterministic winner among GUI Bug Hunt / Design / Usability / Bug Hunt.
        let p = route("the UI is broken")
        XCTAssertEqual(p.recommended?.teamId, "code_gui_bug_hunt",
                       "overlap phrase must prefer GUI Bug Hunt; got \(p.recommended?.teamId ?? "nil")")
    }

    func testNoMatchReturnsConcreteNextActions() {
        let p = route("asdf qwerty zxcvbn totally nonsense intent 999")
        XCTAssertNil(p.recommended?.teamId ?? p.recommended?.kind)
        XCTAssertEqual(p.readiness.code, "INTENT_NO_MATCH")
        XCTAssertFalse(p.nextActions.isEmpty, "no-empty-silence: never bare pick-a-team")
        XCTAssertTrue(p.nextActions.allSatisfy { !$0.command.isEmpty })
    }

    func testEmptyIntentNoMatch() {
        let p = route("   ")
        XCTAssertEqual(p.readiness.code, "INTENT_NO_MATCH")
        XCTAssertFalse(p.nextActions.isEmpty)
    }

    // MARK: - Command grammar + readiness

    func testEmittedTeamStartGrammarResolvesInContract() throws {
        let p = route("harden this spec before I build")
        let display = try XCTUnwrap(p.recommended?.command?.display)
        XCTAssertNotNil(ContractRegistry.resolveCommandName(from: display),
                        "display must resolve: \(display)")
        let argvJoined = (p.recommended?.command?.argv ?? []).joined(separator: " ")
        XCTAssertNotNil(ContractRegistry.resolveCommandName(from: argvJoined))
    }

    func testDownTeamLoudFallbackNotSilentSwap() {
        let ready = allReady.filter { $0.team != "code_spec_review" }
        let p = route("harden this spec before I build", ready: ready)
        XCTAssertEqual(p.recommended?.teamId, "code_spec_review")
        // Preferred may lack a runnable command; fallback (if any) stays in-family.
        if let fb = p.fallback {
            XCTAssertTrue(fb.teamId?.hasPrefix("code_spec_review") == true,
                          "fallback must stay in Spec Review family, got \(fb.teamId ?? "nil")")
            XCTAssertNotNil(fb.command)
        }
        XCTAssertFalse(p.nextActions.isEmpty)
        // No recommended.command → no lifecycle (Decision 10 attaches only to runnable launches).
        if p.recommended?.command == nil {
            XCTAssertNil(p.lifecycle)
        }
    }

    // MARK: - Without --for unchanged (AgentHello)

    func testHelloWithoutForUnchangedReadinessReport() {
        let payload = AgentHello.build(
            verdict: readyVerdict,
            contractHash: ContractRegistry.contractHash(),
            binaryVersion: "test"
        )
        XCTAssertEqual(payload.schemaVersion, 3)
        XCTAssertEqual(
            payload.nextCommandPlan.command,
            "alln team preflight --team <team-id> --json")
        XCTAssertFalse(payload.workflows.isEmpty)
        XCTAssertTrue(payload.canStartTeamRun)
        let async = payload.workflows.first { $0.id == "run_async" }
        XCTAssertEqual(
            async?.steps,
            [
                "alln team preflight --team <team-id> --json",
                "alln team start --team <team-id> --json \"<message>\"",
                "alln team status <run-id> --json",
                "alln team result <run-id> --json",
                "alln show <run-id> --json",
            ],
            "run_async must teach status between start and result (Decision 10)")
    }

    func testIntentRouteJSONRoundTrips() throws {
        let json = AgentHello.intentRouteJSONString(
            intent: "find the real cause of this crash",
            verdict: readyVerdict,
            readyModels: []
        )
        let decoded = try CoreJSON.decode(AgentIntentRouter.Payload.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.recommended?.teamId, "code_bug_hunt")
        XCTAssertNotNil(decoded.lifecycle)
        XCTAssertEqual(decoded.lifecycle?.monitor?.argv,
                       ["alln", "team", "status", "<run-id>", "--json"])
        XCTAssertEqual(decoded.lifecycle?.cancel?.argv,
                       ["alln", "team", "cancel", "<run-id>", "--json"])
    }
}
