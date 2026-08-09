import XCTest
@testable import AllnighterCore

/// ARA-S01 Works Test: AI Readiness report typed schema encodes/decodes, parses
/// from the fenced block, and never contains a score/grade/rating/percentage key
/// anywhere in its serialized JSON.
final class AIReadinessReportTests: XCTestCase {

    // MARK: - Schema

    func testReportRoundTrips() throws {
        let report = AIReadinessReport(
            call: "Your repo is workable but no agent finds the test command",
            receipts: [
                AIReadinessReport.ColdReadReceipt(
                    question: "How do I run the tests here?",
                    answers: [
                        AIReadinessReport.BlindAnswer(seatId: "setup_scout", answer: "npm test"),
                        AIReadinessReport.BlindAnswer(seatId: "measurement_auditor", answer: "npm test"),
                        AIReadinessReport.BlindAnswer(seatId: "test_infra_scout", answer: "npm run test:watch — this is a watcher")
                    ],
                    agreedCount: 2,
                    totalCount: 3,
                    notableMiss: "One seat picked the watcher command"
                )
            ],
            threeFixes: [
                AIReadinessReport.Fix(
                    title: "Add a fast test subset",
                    whyItBites: "Every agent run spends 14 minutes in the full suite",
                    fix: "# Add to package.json\n\"test:fast\": \"vitest run --testPathPattern 'unit/'\"",
                    doneWhen: "npm run test:fast exits in under 30 seconds and returns 0"
                )
            ],
            findings: [
                AIReadinessReport.Finding(
                    seatId: "test_infra_scout",
                    bucket: "tests",
                    severity: "material",
                    title: "Default test command is a watcher",
                    evidence: "package.json line 12: \"test\": \"vitest\" (no --run flag)",
                    nugget: "the_watcher_trap",
                    whyItBites: "Every agent session reads the first run as a hang",
                    fix: "Add --run to the vitest command or a separate test:ci script",
                    doneWhen: "npm test exits with a non-zero status when a test fails"
                )
            ],
            strengths: [
                AIReadinessReport.Strength(
                    title: "Clear AGENTS.md routing table",
                    evidence: "AGENTS.md lines 42–68 route every task type to a single doc"
                )
            ],
            couldNotDetermine: [
                "What framework is used for end-to-end tests — no playwright or cypress config found"
            ]
        )
        let data = try CoreJSON.encode(report)
        let back = try CoreJSON.decode(AIReadinessReport.self, from: data)
        XCTAssertEqual(back.call, report.call)
        XCTAssertEqual(back.receipts.count, 1)
        XCTAssertEqual(back.receipts.first?.question, "How do I run the tests here?")
        XCTAssertEqual(back.receipts.first?.agreedCount, 2)
        XCTAssertEqual(back.receipts.first?.totalCount, 3)
        XCTAssertEqual(back.threeFixes.count, 1)
        XCTAssertEqual(back.threeFixes.first?.title, "Add a fast test subset")
        XCTAssertEqual(back.findings.count, 1)
        XCTAssertEqual(back.findings.first?.severity, "material")
        XCTAssertEqual(back.strengths.count, 1)
        XCTAssertEqual(back.couldNotDetermine.count, 1)
    }

    func testCodingKeysNeverIncludeBannedScoreLanguage() throws {
        let report = AIReadinessReport(
            call: "test",
            receipts: [
                AIReadinessReport.ColdReadReceipt(
                    question: "Q1",
                    answers: [AIReadinessReport.BlindAnswer(seatId: "s1", answer: "a1")],
                    agreedCount: 1,
                    totalCount: 1
                )
            ],
            threeFixes: [
                AIReadinessReport.Fix(title: "f1", whyItBites: "w", fix: "f", doneWhen: "d")
            ],
            findings: [
                AIReadinessReport.Finding(
                    seatId: "s1", bucket: "tests", severity: "blocking",
                    title: "t", evidence: "e", whyItBites: "w", fix: "f", doneWhen: "d"
                )
            ],
            strengths: [AIReadinessReport.Strength(title: "s", evidence: "e")],
            couldNotDetermine: ["x"]
        )
        let data = try CoreJSON.encode(report)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("encoded JSON is not a dictionary")
            return
        }
        let banned = ["score", "grade", "rating", "percent", "percentage"]
        let violations = collectBannedKeys(in: json, banned: banned)
        XCTAssertTrue(violations.isEmpty,
                      "encoded JSON contains banned score-key: \(violations)")
    }

    func testParserExtractsTypedReport() {
        let writerOutput = """
        # AI Readiness · my-repo

        Your repo is workable but a few things would make it better for agents.

        ```ai-readiness-report
        {
          "call": "Your default test command is a watcher",
          "receipts": [
            {
              "question": "How do I run the tests here?",
              "answers": [
                {"seatId": "setup_scout", "answer": "npm test"},
                {"seatId": "measurement_auditor", "answer": "npm run test:ci"}
              ],
              "agreedCount": 0,
              "totalCount": 2,
              "notableMiss": "Two seats gave different commands"
            }
          ],
          "threeFixes": [
            {
              "title": "Add a non-watching test command",
              "whyItBites": "Agents read the watcher as a hang",
              "fix": "script: npm run test:ci",
              "doneWhen": "npm test exits with exit code"
            }
          ],
          "findings": [
            {
              "seatId": "test_infra_scout",
              "bucket": "tests",
              "severity": "material",
              "title": "Default test is a watcher",
              "evidence": "package.json line 12",
              "nugget": "the_watcher_trap",
              "whyItBites": "Every agent session reads as a hang",
              "fix": "Add --run flag",
              "doneWhen": "npm test exits non-zero on failure"
            }
          ],
          "strengths": [
            {"title": "Clear CONTRIBUTING.md", "evidence": "CONTRIBUTING.md line 1-50"}
          ],
          "couldNotDetermine": ["What e2e framework is used"]
        }
        ```
        """
        let report = AIReadinessReportParser.parse(fromWriterOutput: writerOutput)
        XCTAssertEqual(report?.call, "Your default test command is a watcher")
        XCTAssertEqual(report?.receipts.count, 1)
        XCTAssertEqual(report?.receipts.first?.answers.count, 2)
        XCTAssertEqual(report?.receipts.first?.agreedCount, 0)
        XCTAssertEqual(report?.receipts.first?.totalCount, 2)
        XCTAssertEqual(report?.threeFixes.count, 1)
        XCTAssertEqual(report?.threeFixes.first?.title, "Add a non-watching test command")
        XCTAssertEqual(report?.findings.count, 1)
        XCTAssertEqual(report?.findings.first?.bucket, "tests")
        XCTAssertEqual(report?.findings.first?.nugget, "the_watcher_trap")
        XCTAssertEqual(report?.strengths.count, 1)
        XCTAssertEqual(report?.couldNotDetermine.count, 1)
    }

    func testParserReturnsNilWithoutBlock() {
        XCTAssertNil(AIReadinessReportParser.parse(fromWriterOutput: "# AI Readiness\nJust prose."))
        XCTAssertNil(AIReadinessReportParser.parse(fromWriterOutput: nil))
    }

    func testAiReadinessReportOutputKind() {
        XCTAssertTrue(TeamOutputKind.allCases.contains(.aiReadinessReport))
    }

    // MARK: - Helpers

    private func collectBannedKeys(in dict: [String: Any], banned: [String],
                                   path: String = "") -> [String] {
        var violations: [String] = []
        for (key, value) in dict {
            let keyPath = path.isEmpty ? key : "\(path).\(key)"
            let lowerKey = key.lowercased()
            if banned.contains(where: { lowerKey.contains($0) }) {
                violations.append(keyPath)
            }
            if let nested = value as? [String: Any] {
                violations.append(contentsOf: collectBannedKeys(in: nested, banned: banned, path: keyPath))
            } else if let array = value as? [[String: Any]] {
                for (idx, element) in array.enumerated() {
                    violations.append(contentsOf: collectBannedKeys(in: element, banned: banned, path: "\(keyPath)[\(idx)]"))
                }
            }
        }
        return violations
    }
}
