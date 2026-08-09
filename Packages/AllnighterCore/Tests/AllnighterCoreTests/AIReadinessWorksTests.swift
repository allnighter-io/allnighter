import XCTest
import AgentOSTeam
@testable import AllnighterCore

/// ARA-S06 Works Test (§12):
///   1. Clean-bill fixture — empty findings + strengths → no fault invention, no banned language
///   2. No-number check — deterministic banned-numeric-pattern scan on artifact
///   3. Cold-start — counsel(0) non-nil, contains team id; counsel(1) == nil
///   4. MenuSelectionCopy — code_ai_readiness has authored pair, no score language
final class AIReadinessWorksTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    // MARK: - Helpers

    private func makeRun(leadMarkdown: String) -> TeamRun {
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
            id: "run_ara_s06", prompt: "Audit this repo for AI readiness",
            status: .complete, presetId: "code_ai_readiness",
            workers: workers, answers: answers, stages: [plan], createdAt: now,
            teamDisplayName: "AI Readiness", outputKind: .aiReadinessReport
        )
    }

    // MARK: - Gate 1: Clean-bill fixture

    func testCleanBillFixtureNoFaultInventionWhenFindingsEmpty() {
        let md = cleanBillWriterOutput()
        let card = ArtifactProjector.project(makeRun(leadMarkdown: md))
        let html = ArtifactProjector.renderHTML(card)

        // Strengths appear.
        XCTAssertTrue(html.contains("Clear AGENTS.md"),
                      "HTML must contain the cited strength")
        XCTAssertTrue(html.contains("docs/FOLDER_MAP.md"),
                      "HTML must contain the strength evidence")
        XCTAssertTrue(html.contains("Ready for cold read"),
                      "HTML must contain the second strength")

        // No fault language invented from empty findings.
        let faultPatterns = [
            "no findings", "zero findings", "no issues", "all clear",
            "passes", "passed", "no problems", "nothing found",
            "clean bill of health", "no concerns", "looks good",
        ]
        let bodyHTML = bodyContent(html).lowercased()
        for pattern in faultPatterns {
            XCTAssertFalse(bodyHTML.contains(pattern),
                           "HTML must not invent fault language \"\(pattern)\" from empty findings")
        }

        // No banned score/grade/rating/% language (S05-style scan).
        assertNoBannedScoreLanguage(in: html)
    }

    func testCleanBillFixtureGatesPassBannedScoreScan() {
        let md = cleanBillWriterOutput()
        let card = ArtifactProjector.project(makeRun(leadMarkdown: md))
        let html = ArtifactProjector.renderHTML(card)
        assertNoBannedScoreLanguage(in: html)
    }

    // MARK: - Gate 2: No-number check

    func testNoNumericScoringInProjectedArtifact() {
        let md = typicalWriterOutput()
        let card = ArtifactProjector.project(makeRun(leadMarkdown: md))
        let html = ArtifactProjector.renderHTML(card)
        let body = bodyContent(html).lowercased()

        // Banned numeric scoring patterns (away from the agreed N/M tally in receipts).
        let bannedNumericPatterns: [(String, String)] = [
            ("\\d+\\s*/\\s*1[00]\\b", "X/10 or X/100"),
            ("\\d+\\s*out of\\s*1[00]", "X out of 10/100"),
            ("\\d+\\s*star", "N star"),
            ("score[s]?\\s*:?\\s*\\d", "score: N"),
            ("grade[s]?\\s*:?\\s*[a-fA-F]", "grade: letter"),
            ("rating[s]?\\s*:?\\s*\\d", "rating: N"),
            ("\\d+\\s*%\\s*(score|grade|rating|rank)", "N% score/grade/rating/rank"),
        ]
        // The agreed N/M in receipts is legitimate — check that patterns appear
        // only inside receipt-tally context, not as standalone scores.
        for (pattern, label) in bannedNumericPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(body.startIndex..., in: body)
            let matches = regex.matches(in: body, options: [], range: range)
            // Expect zero matches outside receipt tally context.
            for match in matches {
                let matchRange = match.range
                let matchStr = (body as NSString).substring(with: matchRange)
                // Allow only if inside a receipt-tally context (agreed counts).
                let precedingContext = (body as NSString).substring(
                    with: NSRange(location: max(0, matchRange.location - 30),
                                  length: min(30, matchRange.location)))
                let isReceiptTally = precedingContext.contains("agreed") || precedingContext.contains("receipt-tally")
                if !isReceiptTally {
                    XCTFail("HTML body contains banned numeric scoring pattern '\(matchStr)' matching \(label)")
                }
            }
        }
    }

    // MARK: - Gate 3: Cold-start counsel

    func testColdStartCounselNonNilWhenNoThreads() {
        let result = AIReadinessColdStart.counsel(threadCount: 0)
        XCTAssertNotNil(result, "counsel(0) must return non-nil when no threads")
        guard let counsel = result else { return }
        XCTAssertTrue(counsel.contains(AIReadinessColdStart.teamId),
                      "counsel must contain team id '\(AIReadinessColdStart.teamId)'")
        XCTAssertTrue(counsel.contains("AI Readiness"),
                      "counsel must name AI Readiness as first recommended Code Team")
        XCTAssertTrue(counsel.contains("first recommended Code Team"),
                      "counsel must identify AI Readiness as first recommended Code Team")
        XCTAssertTrue(counsel.contains("alln run"),
                      "counsel must contain the runExample command")
        // Never a score/grade/rating/%.
        for banned in ["score", "grade", "rating", "percent", "%"] {
            XCTAssertFalse(counsel.lowercased().contains(banned),
                           "counsel must not contain banned word '\(banned)'")
        }
    }

    func testColdStartCounselNilWhenThreadsExist() {
        XCTAssertNil(AIReadinessColdStart.counsel(threadCount: 1))
        XCTAssertNil(AIReadinessColdStart.counsel(threadCount: 5))
    }

    func testColdStartRunExampleUsesCorrectTeamId() {
        XCTAssertTrue(AIReadinessColdStart.runExample.contains("--team code_ai_readiness"),
                      "runExample must use --team code_ai_readiness")
        XCTAssertTrue(AIReadinessColdStart.runExample.contains("--json"),
                      "runExample must include --json for agent consumption")
    }

    // MARK: - Gate 4: MenuSelectionCopy (optional — in same commit when budget allows)

    func testCodeAIReadinessHasAuthoredMenuPair() {
        let pair = MenuSelectionCopy.team(
            id: "code_ai_readiness",
            displayName: "AI Readiness",
            description: "Audit how workable a repo is for coding agents",
            mutating: false
        )
        // Must be the authored entry, not a derived fallback.
        XCTAssertFalse(pair.useWhen.contains("AI Readiness") && pair.useWhen.count <= 4,
                       "useWhen must be authored, not derived from display name")
        XCTAssertFalse(MenuSelectionCopy.isBannedStub(pair.useWhen),
                       "useWhen must not be a banned stub")
        XCTAssertFalse(MenuSelectionCopy.isBannedStub(pair.dontUseWhen),
                       "dontUseWhen must not be a banned stub")
        // Within bounds.
        let maxUse = MenuSelectionCopy.useWhenMax
        let maxDont = MenuSelectionCopy.dontUseWhenMax
        let useLen = pair.useWhen.trimmingCharacters(in: .whitespacesAndNewlines).count
        let dontLen = pair.dontUseWhen.trimmingCharacters(in: .whitespacesAndNewlines).count
        XCTAssertTrue(useLen <= maxUse && useLen > 0,
                      "useWhen must be non-empty and ≤ \(maxUse) chars, got \(useLen)")
        XCTAssertTrue(dontLen <= maxDont && dontLen > 0,
                      "dontUseWhen must be non-empty and ≤ \(maxDont) chars, got \(dontLen)")
        // No score/grade/rating/% language.
        for banned in ["score", "grade", "rating", "percent", "%"] {
            XCTAssertFalse(pair.useWhen.lowercased().contains(banned),
                           "useWhen must not contain banned word '\(banned)'")
            XCTAssertFalse(pair.dontUseWhen.lowercased().contains(banned),
                           "dontUseWhen must not contain banned word '\(banned)'")
        }
    }

    // MARK: - Fixtures

    /// Clean-bill: findings empty, ≥1 strength, ≥1 threeFixes.
    private func cleanBillWriterOutput() -> String {
        return """
        # AI Readiness · spotless-repo

        This repo is well set up for agents — everything an agent needs is documented.

        ```ai-readiness-report
        {
          "call": "This repo is well set up for agents",
          "receipts": [
            {
              "question": "How do I run the tests here?",
              "answers": [
                {"seatId": "setup_scout", "answer": "npm test"},
                {"seatId": "measurement_auditor", "answer": "npm test"}
              ],
              "agreedCount": 2,
              "totalCount": 2
            }
          ],
          "threeFixes": [
            {
              "title": "Add a fast test subset for agent loops",
              "whyItBites": "The full suite takes 8 minutes; agents waste quota",
              "fix": "Add \\"test:fast\\" script targeting unit tests only",
              "doneWhen": "npm run test:fast finishes under 30 seconds"
            }
          ],
          "findings": [],
          "strengths": [
            {"title": "Clear AGENTS.md", "evidence": "docs/FOLDER_MAP.md with full routing table"},
            {"title": "Ready for cold read", "evidence": "Four agents independently found the same test command"}
          ],
          "couldNotDetermine": []
        }
        ```
        """
    }

    /// Typical report with findings, strengths, etc.
    private func typicalWriterOutput() -> String {
        return """
        # AI Readiness · typical-repo

        This repo needs a few things to be fully workable for agents.

        ```ai-readiness-report
        {
          "call": "Your repo is workable but the test command is a watcher",
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
              "title": "Add a non-watching test command",
              "whyItBites": "Agents read the default npm test as a hang",
              "fix": "\\"test:ci\\": \\"vitest run\\"",
              "doneWhen": "npm run test:ci exits with correct exit code"
            }
          ],
          "findings": [
            {
              "id": "watcher-test-default",
              "seatId": "test_infra_scout",
              "bucket": "tests",
              "severity": "material",
              "title": "Default test command is a watcher",
              "evidence": "package.json line 12: \\"test\\": \\"vitest\\"",
              "nugget": "the_watcher_trap",
              "whyItBites": "Every agent session reads the first run as a hang",
              "fix": "Add --run flag or a separate test:ci script",
              "doneWhen": "npm test exits non-zero when a test fails"
            }
          ],
          "strengths": [
            {"title": "Clear AGENTS.md", "evidence": "AGENTS.md lines 42-68"}
          ],
          "couldNotDetermine": ["What e2e framework is used"]
        }
        ```
        """
    }

    // MARK: - S05-style banned scan (reused)

    private func assertNoBannedScoreLanguage(in html: String) {
        let bodyStart = html.range(of: "<body>")?.upperBound ?? html.startIndex
        let bodyEnd = html.range(of: "</body>", options: .backwards)?.lowerBound ?? html.endIndex
        let bodyHTML = String(html[bodyStart..<bodyEnd]).lowercased()
        let banned = ["score", "grade", "rating"]
        for word in banned {
            XCTAssertFalse(bodyHTML.contains(word),
                           "HTML body must not contain banned word '\(word)'")
        }
        if bodyHTML.range(of: #"\d%"#, options: .regularExpression) != nil {
            XCTFail("HTML body must not contain a product-level percentage (e.g. 85%)")
        }
        let keys = ["score", "grade", "rating", "percent"]
        for key in keys {
            XCTAssertFalse(bodyHTML.contains("data-\(key)") || bodyHTML.contains("class=\"\(key)"),
                           "HTML body class/data must not contain '\(key)'")
        }
    }

    private func bodyContent(_ html: String) -> String {
        guard let bodyStart = html.range(of: "<body>")?.upperBound,
              let bodyEnd = html.range(of: "</body>", options: .backwards)?.lowerBound else {
            return html
        }
        return String(html[bodyStart..<bodyEnd])
    }
}
