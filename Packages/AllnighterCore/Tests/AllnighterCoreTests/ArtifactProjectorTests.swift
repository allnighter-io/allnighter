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

  func testSeatSetSharedHelperKeepsDeclarationOrder() {
    let run = multiSeatRun(leadMarkdown: leadCallMarkdown)
    let seatIds = TeamRunSeatSet.workers(for: run).map(\.id)
    XCTAssertEqual(seatIds, ["model_grok#0", "model_opus#0", "model_opus#1"])
    // Floor deep-reader may still include scout lanes; artifact seat-set is the shared law.
    let cardIds = ArtifactProjector.project(run).seats.map(\.workerId)
    XCTAssertEqual(cardIds, seatIds)
  }

  func testLeadCallPreferredForCallAndVerdict() {
    let card = ArtifactProjector.project(multiSeatRun(leadMarkdown: leadCallMarkdown))
    XCTAssertEqual(card.verdict, "Ready")
    XCTAssertEqual(card.call, "Ship the artifact CLI first.")
    XCTAssertEqual(card.title, "Ship the artifact CLI first.")
    XCTAssertTrue(card.asked.contains("Should we ship"))
    XCTAssertEqual(card.recommendations.first?.decision, "Verb")
    XCTAssertFalse(card.cta.isEmpty)
  }

  func testLaw2SingleSeatHoistUsesAnswerMarkdownOnChip() {
    // Worker row empty (Law-2 nulled); markdown lives on the synthesized answer via plan.
    let worker = Worker(id: "model_sonnet#0", modelId: "model_sonnet", instanceIndex: 0,
                        skillId: "lead", skillName: "Lead", purpose: .plan)
    let answers = [
      TeamAnswer(memberId: "model_sonnet#0", modelId: "model_sonnet", role: "plan",
                 result: WorkerRunResult(status: .done, output: "",
                                         timing: RunTiming(durationMs: 1200))),
    ]
    let plan = StageOutput(
      id: "stage_plan", purpose: .plan, producedByWorkerId: "model_sonnet#0",
      status: .done, payload: .plan(markdown: "Hoisted success one-liner")
    )
    let run = TeamRun(
      id: "run_single", prompt: "Say success.", status: .done,
      workers: [worker], workerAnswers: answers, stages: [plan], createdAt: now
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
    XCTAssertEqual(card.runIdLine, "run_artifact1")
    let html = ArtifactProjector.renderHTML(card)
    // Exactly one run id presentation in footer (no duplicate UUID lines).
    XCTAssertEqual(html.components(separatedBy: "run_artifact1").count - 1, 1)
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

  func testG13GatePassesOnPartialVerdict() {
    let partialMarkdown = """
    ```lead-call
    {"schemaVersion":1,"status":"Partial","call":"Needs a human decision."}
    ```
    """
    let html = ArtifactProjector.renderHTML(
      ArtifactProjector.project(multiSeatRun(leadMarkdown: partialMarkdown))
    )
    XCTAssertTrue(html.contains("verdict-partial"))
    XCTAssertTrue(html.contains("needs-you"))
    XCTAssertTrue(html.contains("accent-event"))
    XCTAssertTrue(
      ArtifactProjector.g13Violations(in: html).isEmpty,
      "Partial Needs-you is the one amber content event"
    )
  }

  func testCallFallbackWhenNoLeadCallOrBody() {
    let worker = Worker(id: "model_a#0", modelId: "model_a", instanceIndex: 0, purpose: .answer)
    let run = TeamRun(
      id: "run_empty", prompt: "Empty?", status: .failed,
      workers: [worker],
      workerAnswers: [
        TeamAnswer(memberId: "model_a#0", modelId: "model_a", role: "answer",
                   result: WorkerRunResult(status: .failed, errorReason: "boom",
                                           timing: RunTiming(durationMs: 10))),
      ],
      stages: [], createdAt: now
    )
    let card = ArtifactProjector.project(run)
    XCTAssertEqual(card.call, "(no synthesized output — status failed)")
  }

  func testQuestionAndOneLinerCaps() {
    let longPrompt = String(repeating: "q", count: 150)
    var run = multiSeatRun(leadMarkdown: leadCallMarkdown)
    run.prompt = longPrompt
    let card = ArtifactProjector.project(run)
    XCTAssertEqual(card.asked.count, 121)
    XCTAssertTrue(card.asked.hasSuffix("…"))
  }

  func testLeadSeatNotQueuedWhenAnswerHoisted() {
    let worker = Worker(id: "model_opus#1", modelId: "model_opus", instanceIndex: 1,
                        skillId: "lead", skillName: "Lead", purpose: .plan)
    let answers = [
      TeamAnswer(memberId: "model_opus#1", modelId: "model_opus", role: "plan",
                 result: WorkerRunResult(status: .queued, output: "",
                                         timing: RunTiming(durationMs: nil))),
    ]
    let plan = StageOutput(
      id: "stage_plan", purpose: .plan, producedByWorkerId: "model_opus#1",
      status: .done, payload: .plan(markdown: leadCallMarkdown)
    )
    let run = TeamRun(
      id: "run_lead_hoist", prompt: "Ship?", status: .complete,
      workers: [worker], workerAnswers: answers, stages: [plan], createdAt: now,
      teamDisplayName: "Spec Polish"
    )
    let card = ArtifactProjector.project(run)
    let lead = try! XCTUnwrap(card.seats.first)
    XCTAssertEqual(lead.status, "done")
    XCTAssertFalse(ArtifactProjector.renderHTML(card).contains("data-status=\"queued\""))
  }

  func testOnePagerUsesDecisionTitleNotPrompt() {
    let html = ArtifactProjector.renderHTML(
      ArtifactProjector.project(multiSeatRun(leadMarkdown: leadCallMarkdown))
    )
    XCTAssertTrue(html.contains("<h1 class=\"title\">"))
    XCTAssertTrue(html.contains("Ship the artifact CLI first."))
    XCTAssertTrue(html.contains("Asked"))
    XCTAssertTrue(html.contains("Full notes (appendix)"))
    XCTAssertTrue(html.contains("Do this next") || html.contains("Next"))
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

  func testArtifactWriterWritesIndexHTML() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("artifact-writer-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let run = multiSeatRun(leadMarkdown: leadCallMarkdown)
    let url = try ArtifactWriter.writeHTML(
      run: run,
      runDirectory: dir,
      reproduceCommand: "alln run \"test prompt\" --team default"
    )
    XCTAssertEqual(url.lastPathComponent, "index.html")
    XCTAssertTrue(url.path.hasSuffix("/artifact/index.html"))
    let html = try String(contentsOf: url, encoding: .utf8)
    XCTAssertTrue(html.contains(ArtifactProjector.honesty))
  }

  func testArtifactWriterRejectsNonTerminal() {
    var run = multiSeatRun(leadMarkdown: leadCallMarkdown)
    run.status = .running
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("artifact-writer-neg-\(UUID().uuidString)", isDirectory: true)
    XCTAssertThrowsError(
      try ArtifactWriter.writeHTML(run: run, runDirectory: dir, reproduceCommand: "alln run x")
    ) { error in
      XCTAssertEqual(error as? ArtifactWriter.WriteError, .notTerminal)
    }
  }

  func testArtifactWriterExportHTML() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("artifact-export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let run = multiSeatRun(leadMarkdown: leadCallMarkdown)
    let reproduce = "alln run \"test prompt\" --team default"
    let destination = dir.appendingPathComponent("receipt.html")
    let url = try ArtifactWriter.exportHTML(
      run: run,
      destination: destination,
      reproduceCommand: reproduce
    )
    XCTAssertEqual(url, destination)
    let html = try String(contentsOf: url, encoding: .utf8)
    XCTAssertTrue(html.contains(ArtifactProjector.honesty))
    XCTAssertTrue(html.contains("<!DOCTYPE html>"))
  }

  func testArtifactExportMatchesShowBody() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("artifact-export-match-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let run = multiSeatRun(leadMarkdown: leadCallMarkdown)
    let reproduce = "alln run \"test prompt\" --team default"
    let showURL = try ArtifactWriter.writeHTML(
      run: run,
      runDirectory: dir,
      reproduceCommand: reproduce
    )
    let exportURL = dir.appendingPathComponent("exported.html")
    _ = try ArtifactWriter.exportHTML(
      run: run,
      destination: exportURL,
      reproduceCommand: reproduce
    )
    let showHTML = try String(contentsOf: showURL, encoding: .utf8)
    let exportHTML = try String(contentsOf: exportURL, encoding: .utf8)
    XCTAssertEqual(showHTML, exportHTML)
  }

  func testArtifactWriterExportRejectsNonTerminal() {
    var run = multiSeatRun(leadMarkdown: leadCallMarkdown)
    run.status = .running
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("artifact-export-neg-\(UUID().uuidString).html")
    XCTAssertThrowsError(
      try ArtifactWriter.exportHTML(run: run, destination: destination, reproduceCommand: "alln run x")
    ) { error in
      XCTAssertEqual(error as? ArtifactWriter.WriteError, .notTerminal)
    }
  }
}
