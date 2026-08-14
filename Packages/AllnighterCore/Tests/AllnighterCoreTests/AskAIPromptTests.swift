import XCTest
@testable import AllnighterCore

final class AskAIPromptTests: XCTestCase {
    private let context = AskAIPrompt.Context(
        appVersion: "1.1.5",
        cliVersion: "1.1.5",
        standaloneHomePath: "/Users/ada/.local/share/allnighter/bin/alln",
        resolvedPathAlln: nil,
        pathConflict: false,
        benchHeadline: "partial",
        benchReady: 5,
        benchNeedsStep: 3,
        benchSupported: 8
    )

    func testAssemblePutsQuestionAfterFactsAndDoesNotHijackDirectChatNoun() {
        let text = AskAIPrompt.assemble(
            question: "Where is Boost window?",
            context: context
        )
        XCTAssertTrue(text.contains("Where is Boost window?"))
        XCTAssertTrue(text.contains("not on PATH"))
        XCTAssertTrue(text.contains("5 available"))
        XCTAssertTrue(text.contains("Boost window"))
        XCTAssertTrue(text.contains(AskAIPrompt.supportEmail))
        XCTAssertFalse(text.contains("direct_chat"), "preamble must not mention the passthrough skill id")
    }

    func testNotOnPathFactNamesRepairVersusColdStart() {
        XCTAssertTrue(context.factsBlock.contains("alln install-cli"))
        XCTAssertTrue(context.factsBlock.contains("get.allnighter.io"))
        XCTAssertFalse(context.factsBlock.contains("PATH conflict"))
    }

    func testPathConflictFactIsDistinctFromMissingPATH() {
        let conflict = AskAIPrompt.Context(
            appVersion: "1.1.5",
            cliVersion: "1.1.5",
            standaloneHomePath: "/Users/ada/.local/share/allnighter/bin/alln",
            resolvedPathAlln: "/opt/homebrew/bin/alln",
            pathConflict: true
        )
        XCTAssertTrue(conflict.factsBlock.contains("PATH conflict"))
        XCTAssertTrue(conflict.factsBlock.contains("/opt/homebrew/bin/alln"))
        XCTAssertFalse(conflict.factsBlock.contains("(not on PATH)"))
    }

    func testOrientationIsAShortRoleNotAGlossary() {
        let o = AskAIPrompt.orientation
        XCTAssertTrue(o.contains("Ask AI"))
        XCTAssertTrue(o.contains(AskAIPrompt.supportEmail))
        XCTAssertTrue(o.contains("Don't change files"))
        XCTAssertTrue(o.contains("alln chrome --json"))
        XCTAssertFalse(o.contains("Boost window"))
        XCTAssertFalse(o.contains("need a step"))
        XCTAssertFalse(o.contains("alln help search"))
        XCTAssertFalse(o.contains("never used a terminal"))
        XCTAssertLessThan(o.count, 700)
    }

    func testProbesCoverNonObviousSurfaces() {
        let ids = Set(AskAIPrompt.probes.map(\.id))
        XCTAssertEqual(ids.count, AskAIPrompt.probes.count)
        for needed in [
            "path_not_on_path", "boost_window", "teams_growth",
            "capacity_need_a_step", "ask_vs_chat", "gui_use_from_cli",
            "default_model", "billing_hatch",
        ] {
            XCTAssertNotNil(AskAIPrompt.probe(id: needed), "missing probe \(needed)")
        }
        XCTAssertFalse(
            AskAIPrompt.probes.contains { $0.question.lowercased().contains("what is allnighter") },
            "probes must not be the obvious FAQ"
        )
    }

    func testScreenFactLeadsTheLiveBlock() {
        let ctx = AskAIPrompt.Context(
            appVersion: "1.1.6",
            cliVersion: "1.1.6",
            standaloneHomePath: "/tmp/alln",
            resolvedPathAlln: "/tmp/alln",
            pathConflict: false,
            screen: "settings.boost"
        )
        XCTAssertTrue(ctx.factsBlock.hasPrefix("- Screen: settings.boost"))
        XCTAssertFalse(AskAIPrompt.orientation.contains("settings.boost"))
    }

    func testSupportMailto() {
        XCTAssertEqual(AskAIPrompt.supportMailto.absoluteString, "mailto:support@allnighter.io")
    }

    func testFromThisMacDoesNotProbeVendors() {
        let ctx = AskAIPrompt.Context.fromThisMac(
            appVersion: "test",
            pathEnvironment: "/tmp/empty-path-for-ask-ai-test",
            homeDirectory: URL(fileURLWithPath: "/tmp/ask-ai-home")
        )
        XCTAssertEqual(ctx.cliVersion, AllnighterVersionIdentity.binaryVersion)
        XCTAssertNil(ctx.benchHeadline, "CLI assembly must not invent a bench tally")
        XCTAssertNil(ctx.resolvedPathAlln)
    }
}
