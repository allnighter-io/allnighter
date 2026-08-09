import XCTest
import AgentOSTeam
@testable import AllnighterCore

/// ARA-S05 Works Test: AI Readiness report projects to the artifact Card, renders
/// readiness HTML sections (receipts, strengths, could-not-determine), maps
/// threeFixes to recommendations when Lead Call recs are absent, prefers typed
/// report.call for call/title, and never contains score/grade/rating/% language.
final class AIReadinessArtifactTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeAIReadinessRun(leadMarkdown: String) -> TeamRun {
        let workers = [
            Agent(id: "model_sonnet#0", modelId: "model_sonnet", instanceIndex: 0,
                   skillId: "ai_readiness_writer", skillName: "AI Readiness Writer", purpose: .plan),
            Agent(id: "model_haiku#0", modelId: "model_haiku", instanceIndex: 0,
                   skillId: "readiness_setup_scout", skillName: "Setup Scout", purpose: .answer),
        ]
        let answers = [
            TeamAnswer(memberId: "model_sonnet#0", modelId: "model_sonnet", role: "plan",
                       result: WorkerRunResult(status: .done, output: leadMarkdown,
                                               timing: RunTiming(startedAt: now, finishedAt: now, durationMs: 3000))),
            TeamAnswer(memberId: "model_haiku#0", modelId: "model_haiku", role: "answer",
                       result: WorkerRunResult(status: .done, output: "Seat summary here.",
                                               timing: RunTiming(startedAt: now, finishedAt: now, durationMs: 800))),
        ]
        let plan = StageOutput(id: "stage_plan", purpose: .plan, status: .done,
                               payload: .plan(markdown: leadMarkdown))
        return TeamRun(
            id: "run_ara_artifact1", prompt: "Audit this repo for AI readiness",
            status: .complete, presetId: "code_ai_readiness",
            workers: workers, answers: answers, stages: [plan], createdAt: now,
            teamDisplayName: "AI Readiness", outputKind: .aiReadinessReport
        )
    }

    // MARK: - Projection

    func testReadinessFieldsPopulateFromParsedReport() {
        let md = aiReadinessWriterOutput()
        let card = ArtifactProjector.project(makeAIReadinessRun(leadMarkdown: md))
        XCTAssertEqual(card.readinessReceipts?.count, 1)
        XCTAssertEqual(card.readinessReceipts?.first?.question, "How do I run the tests here?")
        XCTAssertEqual(card.readinessReceipts?.first?.agreedCount, 2)
        XCTAssertEqual(card.readinessReceipts?.first?.totalCount, 3)
        XCTAssertEqual(card.readinessReceipts?.first?.notableMiss, "One seat picked the watcher")
        XCTAssertEqual(card.readinessStrengths?.count, 1)
        XCTAssertEqual(card.readinessStrengths?.first?.title, "Clear AGENTS.md")
        XCTAssertEqual(card.readinessStrengths?.first?.evidence, "AGENTS.md lines 42-68")
        XCTAssertEqual(card.readinessCouldNotDetermine?.count, 1)
        XCTAssertEqual(card.readinessCouldNotDetermine?.first, "What e2e framework is used")
    }

    func testReportCallPreferredForCallAndTitle() {
        let md = aiReadinessWriterOutput()
        let card = ArtifactProjector.project(makeAIReadinessRun(leadMarkdown: md))
        XCTAssertEqual(card.call, "Your repo is workable but no agent finds the test command")
        XCTAssertEqual(card.title, "Your repo is workable but no agent finds the test command")
    }

    func testThreeFixesBecomeRecommendationsWhenLeadCallRecsEmpty() {
        let md = aiReadinessWriterOutput()
        let card = ArtifactProjector.project(makeAIReadinessRun(leadMarkdown: md))
        XCTAssertEqual(card.recommendations.count, 1)
        XCTAssertEqual(card.recommendations.first?.decision, "Add a fast test subset")
        XCTAssertEqual(card.recommendations.first?.lean, "fix")
        XCTAssertTrue(card.recommendations.first?.why.contains("14 minutes") ?? false)
    }

    func testLeadCallRecsTakePriorityOverThreeFixes() {
        let md = aiReadinessWriterOutputWithLeadCall()
        let card = ArtifactProjector.project(makeAIReadinessRun(leadMarkdown: md))
        XCTAssertEqual(card.recommendations.count, 1)
        XCTAssertEqual(card.recommendations.first?.decision, "Lead Call rec takes priority")
        XCTAssertEqual(card.verdict, "Ready")
    }

    func testReadinessFieldsNilWhenReportAbsent() {
        let md = "# No report block\n\nJust prose."
        let card = ArtifactProjector.project(makeAIReadinessRun(leadMarkdown: md))
        XCTAssertNil(card.readinessReceipts)
        XCTAssertNil(card.readinessStrengths)
        XCTAssertNil(card.readinessCouldNotDetermine)
    }

    // MARK: - HTML

    func testHTMLContainsReadinessSections() {
        let md = aiReadinessWriterOutput()
        let html = ArtifactProjector.renderHTML(
            ArtifactProjector.project(makeAIReadinessRun(leadMarkdown: md))
        )
        XCTAssertTrue(html.contains("Cold-read receipts"))
        XCTAssertTrue(html.contains("How do I run the tests here?"))
        XCTAssertTrue(html.contains("agreed 2/3"))
        XCTAssertTrue(html.contains("notable miss: One seat picked the watcher"))
        XCTAssertTrue(html.contains("Already right"))
        XCTAssertTrue(html.contains("Clear AGENTS.md"))
        XCTAssertTrue(html.contains("AGENTS.md lines 42-68"))
        XCTAssertTrue(html.contains("Could not determine"))
        XCTAssertTrue(html.contains("What e2e framework is used"))
    }

    func testHTMLBansScoreGradeRatingPercentLanguage() {
        let md = aiReadinessWriterOutput()
        let html = ArtifactProjector.renderHTML(
            ArtifactProjector.project(makeAIReadinessRun(leadMarkdown: md))
        )
        // Check body content only — CSS percentages (width, gradient stops) are
        // visual styling, not product language. Ban % only when used as a product
        // percentage (digit followed by % outside the <style> block).
        let bodyStart = html.range(of: "<body>")?.upperBound ?? html.startIndex
        let bodyEnd = html.range(of: "</body>", options: .backwards)?.lowerBound ?? html.endIndex
        let bodyHTML = String(html[bodyStart..<bodyEnd]).lowercased()
        let banned = ["score", "grade", "rating"]
        for word in banned {
            XCTAssertFalse(bodyHTML.contains(word),
                           "HTML body must not contain banned word '\(word)'")
        }
        // Percent as product language: digit immediately before % (e.g. "85%").
        if bodyHTML.range(of: #"\d%"#, options: .regularExpression) != nil {
            XCTFail("HTML body must not contain a product-level percentage (e.g. 85%)")
        }
        let keys = ["score", "grade", "rating", "percent"]
        for key in keys {
            XCTAssertFalse(bodyHTML.contains("data-\(key)") || bodyHTML.contains("class=\"\(key)"),
                           "HTML body class/data must not contain '\(key)'")
        }
    }

    func testG13GatePassesOnReadinessArtifact() {
        let md = aiReadinessWriterOutput()
        let html = ArtifactProjector.renderHTML(
            ArtifactProjector.project(makeAIReadinessRun(leadMarkdown: md))
        )
        XCTAssertTrue(ArtifactProjector.g13Violations(in: html).isEmpty)
    }

    func testReadinessNoVerdictWhenReportHasNoLeadCall() {
        let md = """
        # AI Readiness · my-repo

        The report without a lead call.

        ```ai-readiness-report
        {
          "call": "Your repo needs a test command",
          "receipts": [],
          "threeFixes": [],
          "findings": [],
          "strengths": [],
          "couldNotDetermine": []
        }
        ```
        """
        let card = ArtifactProjector.project(makeAIReadinessRun(leadMarkdown: md))
        XCTAssertNil(card.verdict)
        XCTAssertEqual(card.call, "Your repo needs a test command")
    }

    // MARK: - Fixtures

    private func aiReadinessWriterOutput() -> String {
        return """
        # AI Readiness · my-repo

        Your repo is workable but no agent finds the test command.

        ```ai-readiness-report
        {
          "call": "Your repo is workable but no agent finds the test command",
          "receipts": [
            {
              "question": "How do I run the tests here?",
              "answers": [
                {"seatId": "setup_scout", "answer": "npm test"},
                {"seatId": "measurement_auditor", "answer": "npm test"},
                {"seatId": "test_infra_scout", "answer": "npm run test:watch"}
              ],
              "agreedCount": 2,
              "totalCount": 3,
              "notableMiss": "One seat picked the watcher"
            }
          ],
          "threeFixes": [
            {
              "title": "Add a fast test subset",
              "whyItBites": "Every agent run spends 14 minutes in the full suite",
              "fix": "\\"test:fast\\": \\"vitest run --testPathPattern 'unit/'\\"",
              "doneWhen": "npm run test:fast exits in under 30 seconds"
            }
          ],
          "findings": [],
          "strengths": [
            {"title": "Clear AGENTS.md", "evidence": "AGENTS.md lines 42-68"}
          ],
          "couldNotDetermine": ["What e2e framework is used"]
        }
        ```
        """
    }

    private func aiReadinessWriterOutputWithLeadCall() -> String {
        return """
        Status: Ready

        Asked: Audit this repo for AI readiness

        Title: AI Readiness for my-repo

        ```lead-call
        {
          "schemaVersion": 1,
          "status": "Ready",
          "asked": "Audit this repo for AI readiness",
          "title": "AI Readiness for my-repo",
          "call": "Your repo is workable but no agent finds the test command",
          "recommendations": [
            {"decision": "Lead Call rec takes priority", "lean": "fix", "why": "from lead call"}
          ]
        }
        ```

        ```ai-readiness-report
        {
          "call": "Your repo is workable but no agent finds the test command",
          "receipts": [
            {
              "question": "How do I run the tests here?",
              "answers": [
                {"seatId": "setup_scout", "answer": "npm test"},
                {"seatId": "measurement_auditor", "answer": "npm test"},
                {"seatId": "test_infra_scout", "answer": "npm run test:watch"}
              ],
              "agreedCount": 2,
              "totalCount": 3,
              "notableMiss": "One seat picked the watcher"
            }
          ],
          "threeFixes": [
            {
              "title": "Add a fast test subset",
              "whyItBites": "Every agent run spends 14 minutes in the full suite",
              "fix": "test:fast",
              "doneWhen": "npm run test:fast exits in under 30 seconds"
            }
          ],
          "findings": [],
          "strengths": [
            {"title": "Clear AGENTS.md", "evidence": "AGENTS.md lines 42-68"}
          ],
          "couldNotDetermine": ["What e2e framework is used"]
        }
        ```
        """
    }
}
