import XCTest
import AgentOSTeam
@testable import AllnighterCore

final class ArtifactProjectorTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_750_000_000)

  private func multiSeatRun(
    leadMarkdown: String,
    status: RunStatus = .complete
  ) -> TeamRun {
    let workers = [
      Worker(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0,
             skillId: "reader", skillName: "Reader", purpose: .answer),
      Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0,
             skillId: "skeptic", skillName: "Skeptic", purpose: .review),
      Worker(id: "model_opus#1", modelId: "model_opus", instanceIndex: 1,
             skillId: "lead", skillName: "Lead", purpose: .plan),
    ]
    let answers = [
      TeamAnswer(memberId: "model_grok#0", modelId: "model_grok", role: "answer",
                 result: WorkerRunResult(status: .done, output: "Reader one-liner line",
                                         timing: RunTiming(startedAt: now, finishedAt: now, durationMs: 900))),
      TeamAnswer(memberId: "model_opus#0", modelId: "model_opus", role: "review",
                 result: WorkerRunResult(status: .failed, errorReason: "auth expired",
                                         timing: RunTiming(startedAt: now, finishedAt: now, durationMs: 400))),
      TeamAnswer(memberId: "model_opus#1", modelId: "model_opus", role: "plan",
                 result: WorkerRunResult(status: .done, output: leadMarkdown,
                                         timing: RunTiming(startedAt: now, finishedAt: now, durationMs: 2200))),
    ]
    let plan = StageOutput(id: "stage_plan", purpose: .plan, status: .done,
                           payload: .plan(markdown: leadMarkdown))
    return TeamRun(
      id: "run_artifact1", prompt: "Should we ship the artifact CLI?", status: status,
      presetId: "code_spec_review", workers: workers, workerAnswers: answers,
      stages: [plan], createdAt: now, teamDisplayName: "Spec Review", outputKind: .specReview
    )
  }

  private let leadCallMarkdown = """
  Status: Ready — all forks decided.

  ```lead-call
  {
    "schemaVersion": 1,
    "status": "Ready",
    "call": "Ship the artifact CLI first.",
    "changed": "spec only → ship CLI path",
    "recommendations": [{"decision":"Verb","lean":"artifact","why":"locked in S00b"}]
  }
  ```

  Craft notes stay below the envelope.
  """

  func testHonestyStringExactInHTML() {
    let card = ArtifactProjector.project(multiSeatRun(leadMarkdown: leadCallMarkdown))
    let html = ArtifactProjector.renderHTML(card)
    XCTAssertTrue(html.contains(ArtifactProjector.honesty))
    XCTAssertEqual(ArtifactProjector.honesty, "alln-attested multi-seat artifact · not vendor-signed")
  }

  func testNonTerminalRunCannotProject() {
    let run = multiSeatRun(leadMarkdown: leadCallMarkdown, status: .running)
    XCTAssertFalse(ArtifactProjector.canProject(run))
  }

  func testSeatSetAntiDriftWithFloor() {
    let run = multiSeatRun(leadMarkdown: leadCallMarkdown)
    let seatIds = TeamRunSeatSet.workers(for: run).map(\.id)
    let floorIds = FloorProjector.seatWorkers(for: run).map(\.id)
    XCTAssertEqual(seatIds, floorIds)
    let lanes = FloorProjector.project(run).workerLanes.map(\.workerId)
    for (offset, id) in seatIds.enumerated() {
      XCTAssertEqual(lanes[offset], id, "floor lane order must match seat-set order")
    }
  }

  func testLeadCallPreferredForCallAndVerdict() {
    let card = ArtifactProjector.project(multiSeatRun(leadMarkdown: leadCallMarkdown))
    XCTAssertEqual(card.verdict, "Ready")
    XCTAssertEqual(card.call, "Ship the artifact CLI first.")
    XCTAssertEqual(card.recommendations.first?.decision, "Verb")
  }

  func testLaw2SingleSeatHoistUsesAnswerMarkdownOnChip() {
    let worker = Worker(id: "model_sonnet#0", modelId: "model_sonnet", instanceIndex: 0, purpose: .answer)
    let answers = [
      TeamAnswer(memberId: "model_sonnet#0", modelId: "model_sonnet", role: "answer",
                 result: WorkerRunResult(status: .done, output: "Hoisted success one-liner",
                                         timing: RunTiming(durationMs: 1200))),
    ]
    let run = TeamRun(
      id: "run_single", prompt: "Say success.", status: .done,
      workers: [worker], workerAnswers: answers, stages: [], createdAt: now
    )
    let card = ArtifactProjector.project(run)
    XCTAssertEqual(card.seats.count, 1)
    XCTAssertEqual(card.seats[0].oneLiner, "Hoisted success one-liner")
  }

  func testReproduceElisionAt96Chars() {
    let long = String(repeating: "a", count: 120)
    let card = ArtifactProjector.project(
      multiSeatRun(leadMarkdown: leadCallMarkdown),
      reproduceCommand: long
    )
    XCTAssertEqual(card.reproduceLine, String(repeating: "a", count: 96) + "…")
    XCTAssertEqual(card.reproduceRunIdLine, "run_artifact1")
  }

  func testFailedSeatVisibleInHTML() {
    let html = ArtifactProjector.renderHTML(
      ArtifactProjector.project(multiSeatRun(leadMarkdown: leadCallMarkdown))
    )
    XCTAssertTrue(html.contains("data-status=\"failed\""))
    XCTAssertTrue(html.contains("model_opus"))
  }

  func testSubstringTruthOnlyDeclaredStrings() {
    let card = ArtifactProjector.project(multiSeatRun(leadMarkdown: leadCallMarkdown))
    let html = ArtifactProjector.renderHTML(card)
    XCTAssertTrue(html.contains("Ship the artifact CLI first."))
    XCTAssertTrue(html.contains("Reader one-liner line"))
    XCTAssertFalse(html.contains("not ready to build"))
    XCTAssertFalse(html.contains("outcome.headline"))
  }

  func testG13GatePassesOnSettledArtifact() {
    let html = ArtifactProjector.renderHTML(
      ArtifactProjector.project(multiSeatRun(leadMarkdown: leadCallMarkdown))
    )
    XCTAssertTrue(ArtifactProjector.g13Violations(in: html).isEmpty)
  }

  func testQuestionAndOneLinerCaps() {
    let longPrompt = String(repeating: "q", count: 150)
    var run = multiSeatRun(leadMarkdown: leadCallMarkdown)
    run.prompt = longPrompt
    let card = ArtifactProjector.project(run)
    XCTAssertEqual(card.question.count, 121)
    XCTAssertTrue(card.question.hasSuffix("…"))
  }

  func testScoutExcludedFromSeatSet() {
    let workers = [
      Worker(id: "scout#0", modelId: "model_grok", instanceIndex: 0, purpose: .scout),
      Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0, purpose: .answer),
    ]
    let run = TeamRun(
      id: "run_scout", prompt: "x", status: .done, workers: workers,
      workerAnswers: [], stages: [], createdAt: now
    )
    XCTAssertEqual(TeamRunSeatSet.workers(for: run).map(\.id), ["model_opus#0"])
  }
}
