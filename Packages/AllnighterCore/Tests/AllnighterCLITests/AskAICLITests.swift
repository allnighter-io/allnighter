import XCTest
@testable import AllnighterCLI
import AllnighterCore

final class AskAICLITests: XCTestCase {
    func testParsePrintPromptAndQuestion() {
        let p = AskAICLI.parse(["Where is Boost?", "--print-prompt"])
        XCTAssertEqual(p.question, "Where is Boost?")
        XCTAssertTrue(p.printPrompt)
        XCTAssertFalse(p.run)
        XCTAssertNil(p.unknownFlag)
    }

    func testParseProbeId() {
        let p = AskAICLI.parse(["--probe", "boost_window", "--print-prompt"])
        XCTAssertEqual(p.probeId, "boost_window")
        XCTAssertEqual(p.question, nil)
        XCTAssertTrue(AskAICLI.resolvedQuestion(p).question?.contains("Boost") == true)
    }

    func testUnknownProbeFails() {
        let p = AskAICLI.parse(["--probe", "not_a_probe"])
        XCTAssertNotNil(AskAICLI.resolvedQuestion(p).error)
    }

    func testUnknownFlagIsCapturedNotSwallowed() {
        let p = AskAICLI.parse(["--explode", "hi"])
        XCTAssertEqual(p.unknownFlag, "--explode")
    }

    func testParseProjectForRun() {
        let p = AskAICLI.parse(["--probe", "boost_window", "--run", "--project", "prj_5ea07fd5", "--json"])
        XCTAssertEqual(p.probeId, "boost_window")
        XCTAssertEqual(p.project, "prj_5ea07fd5")
        XCTAssertTrue(p.run)
        XCTAssertTrue(p.json)
    }

    func testProbesJSONListsEveryCannedId() throws {
        let data = Data(AskAICLI.probesJSON().utf8)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["supportEmail"] as? String, "support@allnighter.io")
        let probes = obj?["probes"] as? [[String: Any]] ?? []
        let ids = Set(probes.compactMap { $0["id"] as? String })
        XCTAssertEqual(ids, Set(AskAIPrompt.probes.map(\.id)))
    }

    func testAssembledPromptIsReadOnlyAutoNotATeam() {
        let prompt = AskAICLI.assembledPrompt(
            question: "Where is Boost window?",
            context: AskAIPrompt.Context(
                appVersion: "1.1.5",
                cliVersion: "1.1.5",
                standaloneHomePath: "/tmp/alln",
                resolvedPathAlln: nil,
                pathConflict: false
            )
        )
        XCTAssertTrue(prompt.contains("Where is Boost window?"))
        XCTAssertTrue(prompt.contains("Don't change files"))
        XCTAssertFalse(prompt.contains("--team"))
        XCTAssertFalse(prompt.contains("code_growth"))
    }
}
