import XCTest
@testable import AllnighterCore

/// IR-S01 golden transcripts for `alln team hello --for` (`Agent_Intent_Router.md`).
final class AgentIntentRouterTests: XCTestCase {

    private var allReady: [ReadyTeam] {
        BuiltInTeams.all.map {
            ReadyTeam(lane: $0.lane.rawValue, team: $0.id, displayName: $0.displayName)
        }
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
    }

    // MARK: - Without --for unchanged (AgentHello)

    func testHelloWithoutForUnchangedReadinessReport() {
        let verdict = AgentReadiness.evaluate(teams: BuiltInTeams.all, readyModels: [
            Model(id: "m1", displayName: "M", modelLabel: "m", driverId: "claude_code", role: .both),
        ])
        let payload = AgentHello.build(
            verdict: verdict,
            contractHash: ContractRegistry.contractHash(),
            binaryVersion: "test"
        )
        XCTAssertEqual(payload.schemaVersion, 3)
        XCTAssertEqual(
            payload.nextCommandPlan.command,
            "alln team preflight --team <team-id> --json")
        XCTAssertFalse(payload.workflows.isEmpty)
    }

    func testIntentRouteJSONRoundTrips() throws {
        let verdict = AgentReadiness.Verdict(
            canStartTeamRun: true,
            readyTeams: allReady,
            blockedReason: nil,
            nextAction: AgentNextAction(kind: "startTeamRun", tool: "team_start")
        )
        let json = AgentHello.intentRouteJSONString(
            intent: "find the real cause of this crash",
            verdict: verdict,
            readyModels: []
        )
        let decoded = try CoreJSON.decode(AgentIntentRouter.Payload.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.recommended?.teamId, "code_bug_hunt")
    }
}
