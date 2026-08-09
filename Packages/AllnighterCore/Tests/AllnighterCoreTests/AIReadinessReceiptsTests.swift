import XCTest
@testable import AllnighterCore

final class AIReadinessReceiptsTests: XCTestCase {

    func testSeedQuestionsMatchPacketSpec() {
        XCTAssertEqual(AIReadinessReceipts.seedQuestions.count, 4)
        XCTAssertEqual(AIReadinessReceipts.seedQuestions[0], "How do I run the tests here?")
        XCTAssertEqual(AIReadinessReceipts.seedQuestions[1], "How do I run this project locally from a clean clone?")
        XCTAssertEqual(AIReadinessReceipts.seedQuestions[2], "Where is the durable truth about how this product behaves?")
        XCTAssertEqual(AIReadinessReceipts.seedQuestions[3], "If I change behavior, what proves I did not break something?")
    }

    func testColdReadBriefContainsAllQuestions() {
        for q in AIReadinessReceipts.seedQuestions {
            XCTAssertTrue(AIReadinessReceipts.coldReadBrief.contains(q),
                          "coldReadBrief must contain question: \(q)")
        }
    }

    func testColdReadBriefBansVendorLanguage() {
        XCTAssertTrue(AIReadinessReceipts.coldReadBrief.contains("Ban vendor ranking"))
    }

    func testParseColdReadFromSeatOutput() {
        let output = """
        ## Seat summary
        Tests: npm test

        ```ai-readiness-cold-read
        {
          "answers": [
            {"question":"How do I run the tests here?","answer":"npm test","couldNotDetermine":false},
            {"question":"How do I run this project locally from a clean clone?","answer":"npm install && npm run dev","couldNotDetermine":false},
            {"question":"Where is the durable truth about how this product behaves?","answer":"docs/README.md","couldNotDetermine":false},
            {"question":"If I change behavior, what proves I did not break something?","answer":"npm test","couldNotDetermine":false}
          ]
        }
        ```
        """
        let result = AIReadinessReceipts.parseColdRead(fromSeatOutput: output)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 4)
        XCTAssertEqual(result?[0].question, "How do I run the tests here?")
        XCTAssertEqual(result?[0].answer, "npm test")
        XCTAssertEqual(result?[0].couldNotDetermine, false)
        XCTAssertEqual(result?[1].answer, "npm install && npm run dev")
    }

    func testParseColdReadReturnsNilWithoutBlock() {
        XCTAssertNil(AIReadinessReceipts.parseColdRead(fromSeatOutput: nil))
        XCTAssertNil(AIReadinessReceipts.parseColdRead(fromSeatOutput: "Just prose."))
    }

    func testParseColdReadReturnsNilWithMalformedJSON() {
        let output = """
        ```ai-readiness-cold-read
        not json at all
        ```
        """
        XCTAssertNil(AIReadinessReceipts.parseColdRead(fromSeatOutput: output))
    }

    func testParseColdReadHandlesCouldNotDetermine() {
        let output = """
        ```ai-readiness-cold-read
        {
          "answers": [
            {"question":"How do I run the tests here?","answer":"could not determine","couldNotDetermine":true},
            {"question":"How do I run this project locally from a clean clone?","answer":"npm start","couldNotDetermine":false}
          ]
        }
        ```
        """
        let result = AIReadinessReceipts.parseColdRead(fromSeatOutput: output)
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(result?[0].couldNotDetermine, true)
        XCTAssertEqual(result?[0].answer, "could not determine")
        XCTAssertEqual(result?[1].couldNotDetermine, false)
    }

    func testParseColdReadDefaultsCouldNotDetermineFalse() {
        let output = """
        ```ai-readiness-cold-read
        {
          "answers": [
            {"question":"How do I run the tests here?","answer":"npm test"}
          ]
        }
        ```
        """
        let result = AIReadinessReceipts.parseColdRead(fromSeatOutput: output)
        XCTAssertEqual(result?[0].couldNotDetermine, false)
    }

    func testTallyPreservesSeatIds() {
        let receipt = AIReadinessReceipts.tally(
            question: "How do I run the tests here?",
            seatAnswers: [
                AIReadinessReport.BlindAnswer(seatId: "readiness_setup_scout", answer: "npm test"),
                AIReadinessReport.BlindAnswer(seatId: "readiness_test_infra_scout", answer: "npm test"),
                AIReadinessReport.BlindAnswer(seatId: "readiness_measurement_auditor", answer: "could not determine")
            ]
        )
        XCTAssertEqual(receipt.agreedCount, 2)
        XCTAssertEqual(receipt.totalCount, 3)
        XCTAssertEqual(receipt.answers.map(\.seatId), [
            "readiness_setup_scout", "readiness_test_infra_scout", "readiness_measurement_auditor"
        ])
        XCTAssertEqual(receipt.notableMiss, "Some seats could not determine")
    }

    func testTallyFullAgreement() {
        let receipt = AIReadinessReceipts.tally(
            question: "How do I run the tests here?",
            answers: ["npm test", "npm test", "npm test"]
        )
        XCTAssertEqual(receipt.question, "How do I run the tests here?")
        XCTAssertEqual(receipt.agreedCount, 3)
        XCTAssertEqual(receipt.totalCount, 3)
        XCTAssertEqual(receipt.answers.count, 3)
        XCTAssertNil(receipt.notableMiss)
    }

    func testTallyFullDisagreement() {
        let receipt = AIReadinessReceipts.tally(
            question: "How do I run the tests here?",
            answers: ["npm test", "yarn test", "make test"]
        )
        XCTAssertEqual(receipt.agreedCount, 1)
        XCTAssertEqual(receipt.totalCount, 3)
        XCTAssertEqual(receipt.notableMiss, "Seats disagreed")
    }

    func testTallyWithCouldNotDetermine() {
        let receipt = AIReadinessReceipts.tally(
            question: "How do I run the tests here?",
            answers: ["npm test", "npm test", "could not determine"]
        )
        XCTAssertEqual(receipt.agreedCount, 2)
        XCTAssertEqual(receipt.totalCount, 3)
        XCTAssertEqual(receipt.notableMiss, "Some seats could not determine")
    }

    func testTallyAllCouldNotDetermine() {
        let receipt = AIReadinessReceipts.tally(
            question: "How do I run the tests here?",
            answers: ["could not determine", "could not determine", "could not determine"]
        )
        XCTAssertEqual(receipt.agreedCount, 0)
        XCTAssertEqual(receipt.totalCount, 3)
        XCTAssertNotNil(receipt.notableMiss)
    }

    func testTallyMixedCNDAndDisagreement() {
        let receipt = AIReadinessReceipts.tally(
            question: "How do I run the tests here?",
            answers: ["npm test", "yarn test", "could not determine"]
        )
        XCTAssertEqual(receipt.agreedCount, 1)
        XCTAssertEqual(receipt.totalCount, 3)
        XCTAssertEqual(receipt.notableMiss, "Some seats could not determine; remaining seats disagreed")
    }

    func testTallyLargestClusterWins() {
        let receipt = AIReadinessReceipts.tally(
            question: "How do I run the tests here?",
            answers: ["npm test", "npm test", "yarn test", "yarn test", "npm test"]
        )
        XCTAssertEqual(receipt.agreedCount, 3)
        XCTAssertEqual(receipt.totalCount, 5)
    }

    func testTallyNormalizesWhitespaceForAgreement() {
        let receipt = AIReadinessReceipts.tally(
            question: "How do I run the tests here?",
            answers: ["npm test", "  npm test  ", "npm  test"]
        )
        XCTAssertEqual(receipt.agreedCount, 3)
        XCTAssertEqual(receipt.totalCount, 3)
        XCTAssertNil(receipt.notableMiss)
    }

    func testTallyNormalizesCaseForAgreement() {
        let receipt = AIReadinessReceipts.tally(
            question: "How do I run the tests here?",
            answers: ["npm test", "NPM TEST", "Npm Test"]
        )
        XCTAssertEqual(receipt.agreedCount, 3)
    }

    func testTallyStoresAnswersVerbatim() {
        let receipt = AIReadinessReceipts.tally(
            question: "Q",
            answers: ["  npm test  ", "NPM TEST"]
        )
        XCTAssertEqual(receipt.answers[0].answer, "  npm test  ")
        XCTAssertEqual(receipt.answers[1].answer, "NPM TEST")
    }

    func testTallyNoNotableMissWhenAllAgree() {
        let receipt = AIReadinessReceipts.tally(
            question: "How do I run the tests here?",
            answers: ["npm test", "npm test"]
        )
        XCTAssertNil(receipt.notableMiss)
    }

    func testTallyNeverEmitsPercentScoreGrade() {
        let receipt = AIReadinessReceipts.tally(
            question: "Q",
            answers: ["a1", "a2", "could not determine"]
        )
        let data = try! CoreJSON.encode(receipt)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("not a dict")
            return
        }
        let banned = ["score", "grade", "rating", "percent", "percentage"]
        for key in json.keys {
            for b in banned {
                XCTAssertFalse(key.lowercased().contains(b),
                               "key '\(key)' contains banned word '\(b)'")
            }
        }
    }

    func testTallyEmptyAnswers() {
        let receipt = AIReadinessReceipts.tally(
            question: "Q",
            answers: []
        )
        XCTAssertEqual(receipt.agreedCount, 0)
        XCTAssertEqual(receipt.totalCount, 0)
        XCTAssertNil(receipt.notableMiss)
    }

    func testTallyEmptyStringTreatedAsCouldNotDetermine() {
        let receipt = AIReadinessReceipts.tally(
            question: "Q",
            answers: ["npm test", ""]
        )
        XCTAssertEqual(receipt.agreedCount, 1)
        XCTAssertEqual(receipt.totalCount, 2)
        XCTAssertEqual(receipt.notableMiss, "Some seats could not determine")
    }

    func testAssemblePromptIncludesColdReadBriefForAnswerSeat() {
        let assembled = SkillCatalog.assemblePrompt(
            skillId: "readiness_setup_scout",
            founderPrompt: "Audit this repo",
            outputKind: .aiReadinessReport
        )
        XCTAssertTrue(assembled.contains("Cold-read brief"), "answer seat must get cold-read brief")
        XCTAssertTrue(assembled.contains("How do I run the tests here?"), "must contain seed question")
        XCTAssertTrue(assembled.hasSuffix("Audit this repo"))
    }

    func testAssemblePromptIncludesColdReadBriefForReviewSeat() {
        let assembled = SkillCatalog.assemblePrompt(
            skillId: "scope_steward",
            founderPrompt: "Review this",
            outputKind: .aiReadinessReport
        )
        XCTAssertTrue(assembled.contains("Cold-read brief"), "review seat must get cold-read brief")
    }

    func testAssemblePromptExcludesColdReadBriefForPlanWriter() {
        let assembled = SkillCatalog.assemblePrompt(
            skillId: "ai_readiness_writer",
            founderPrompt: "Synthesize",
            outputKind: .aiReadinessReport
        )
        XCTAssertTrue(assembled.contains("Lead Call envelope"))
        XCTAssertFalse(assembled.contains("Cold-read brief"), "planWriter must not get cold-read brief")
    }

    func testAssemblePromptExcludesColdReadBriefWithoutOutputKind() {
        let assembled = SkillCatalog.assemblePrompt(
            skillId: "readiness_setup_scout",
            founderPrompt: "Audit this repo"
        )
        XCTAssertFalse(assembled.contains("Cold-read brief"), "must not include cold-read brief without aiReadinessReport outputKind")
    }

    func testAssemblePromptExcludesColdReadBriefForDesignBoardAnswer() {
        let assembled = SkillCatalog.assemblePrompt(
            skillId: "minimal",
            founderPrompt: "Design a page",
            outputKind: .designBoard
        )
        XCTAssertTrue(assembled.contains("Design capture"), "design answer seat must get capture brief")
        XCTAssertFalse(assembled.contains("Cold-read brief"), "design answer must not get cold-read brief")
    }

    func testAssemblePromptExcludesColdReadBriefForDirectChat() {
        let assembled = SkillCatalog.assemblePrompt(
            skillId: SkillCatalog.directChatSkillId,
            founderPrompt: "Hello",
            outputKind: .aiReadinessReport
        )
        XCTAssertEqual(assembled, "Hello")
        XCTAssertFalse(assembled.contains("Cold-read brief"))
    }
}
