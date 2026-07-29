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
      Agent(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0,
             skillId: "reader", skillName: "Reader", purpose: .answer),
      Agent(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0,
             skillId: "skeptic", skillName: "Skeptic", purpose: .review),
      Agent(id: "model_opus#1", modelId: "model_opus", instanceIndex: 1,
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
      presetId: "code_spec_review", workers: workers, answers: answers,
      stages: [plan], createdAt: now, teamDisplayName: "Spec Review", outputKind: .specReview
    )
  }

  private let leadCallMarkdown = """
  Status: Ready — all forks decided.

  Asked: Should we ship the artifact CLI?

  Title: Ship the artifact CLI first

  ```lead-call
  {
    "schemaVersion": 1,
    "status": "Ready",
    "asked": "Should we ship the artifact CLI?",
    "title": "Ship the artifact CLI first",
    "call": "Ship the artifact CLI first. Lock the verb and path.",
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
    // Reading order pins Lead first; declaration order stays on TeamRunSeatSet.
    let cardIds = ArtifactProjector.project(run).seats.map(\.workerId)
    XCTAssertEqual(cardIds, ["model_opus#1", "model_grok#0", "model_opus#0"])
  }

  // MARK: - CMR-S05 (Cross_Model_Review_Hardening.md): writer/reviewer pairing

  func testWriterReviewerLinePairsAnswerAndReviewStageModels() {
    let card = ArtifactProjector.project(multiSeatRun(leadMarkdown: leadCallMarkdown))
    XCTAssertEqual(card.writerReviewerLine, "Writer: model_grok · Reviewer: model_opus")
  }

  func testWriterReviewerLineNilWithoutReviewStageWorker() {
    let workers = [
      Agent(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0,
             skillId: "reader", skillName: "Reader", purpose: .answer),
      Agent(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0,
             skillId: "lead", skillName: "Lead", purpose: .plan),
    ]
    let answers = [
      TeamAnswer(memberId: "model_grok#0", modelId: "model_grok", role: "answer",
                 result: WorkerRunResult(status: .done, output: "Reader one-liner line",
                                         timing: RunTiming(startedAt: now, finishedAt: now, durationMs: 900))),
      TeamAnswer(memberId: "model_opus#0", modelId: "model_opus", role: "plan",
                 result: WorkerRunResult(status: .done, output: leadCallMarkdown,
                                         timing: RunTiming(startedAt: now, finishedAt: now, durationMs: 2200))),
    ]
    let plan = StageOutput(id: "stage_plan", purpose: .plan, status: .done,
                           payload: .plan(markdown: leadCallMarkdown))
    let run = TeamRun(
      id: "run_no_review", prompt: "Plan only, no review seat", status: .complete,
      presetId: "code_plan", workers: workers, answers: answers,
      stages: [plan], createdAt: now, teamDisplayName: "Plan", outputKind: .plan
    )
    XCTAssertNil(ArtifactProjector.project(run).writerReviewerLine)
  }

  func testLeadCallPreferredForCallAndVerdict() {
    let card = ArtifactProjector.project(multiSeatRun(leadMarkdown: leadCallMarkdown))
    XCTAssertEqual(card.verdict, "Ready")
    XCTAssertEqual(card.call, "Ship the artifact CLI first. Lock the verb and path.")
    XCTAssertEqual(card.title, "Ship the artifact CLI first")
    XCTAssertEqual(card.asked, "Should we ship the artifact CLI?")
    XCTAssertEqual(card.recommendations.first?.decision, "Verb")
    XCTAssertFalse(card.cta.isEmpty)
  }

  func testRoleFirstSeatsAndLeadPinned() {
    let card = ArtifactProjector.project(multiSeatRun(leadMarkdown: leadCallMarkdown))
    XCTAssertTrue(card.seats.first?.isLead == true)
    XCTAssertEqual(card.seats.map(\.roleLabel), ["Lead", "Reader", "Skeptic"])
    let html = ArtifactProjector.renderHTML(card)
    XCTAssertTrue(html.contains("class=\"masthead\""))
    XCTAssertTrue(html.contains("class=\"page\""))
    XCTAssertTrue(html.contains("The team"))
    XCTAssertTrue(html.contains("tag-lead"))
    XCTAssertTrue(html.contains("status-word"))
    XCTAssertTrue(html.contains("chip-model"))
    XCTAssertFalse(html.contains("Decided by"))
    XCTAssertFalse(html.contains("Who weighed in"))
    XCTAssertTrue(html.contains("Allnighter"))
    XCTAssertTrue(html.contains(ArtifactProjector.honesty))
  }

  func testSeatSummaryFencePreferredOverProcessProse() {
    let md = """
    I'll open the file and check everything carefully.

    Summary: Found 3 hierarchy wounds; Lead is correctly pinned first.

    ```seat
    {"schemaVersion":1,"summary":"Found 3 hierarchy wounds; Lead is correctly pinned first."}
    ```

    Longer craft evidence stays below.
    """
    let worker = Agent(id: "model_a#0", modelId: "model_a", instanceIndex: 0,
                        skillId: "hierarchy_sculptor", skillName: "Hierarchy Sculptor",
                        purpose: .answer)
    let run = TeamRun(
      id: "run_seat_sum", prompt: "Polish?", status: .done,
      workers: [worker],
      answers: [
        TeamAnswer(memberId: "model_a#0", modelId: "model_a", role: "answer",
                   result: WorkerRunResult(status: .done, output: md,
                                           timing: RunTiming(durationMs: 100))),
      ],
      stages: [], createdAt: now
    )
    let card = ArtifactProjector.project(run)
    XCTAssertEqual(
      card.seats[0].oneLiner,
      "Found 3 hierarchy wounds; Lead is correctly pinned first."
    )
    XCTAssertFalse(card.seats[0].oneLiner?.contains("I'll open") == true)
    XCTAssertEqual(card.evidence.count, 1)
    XCTAssertTrue(card.evidence[0].bodyMarkdown.contains("Longer craft"))
    XCTAssertFalse(card.evidence[0].bodyMarkdown.contains("```seat"))
    let html = ArtifactProjector.renderHTML(card)
    let anchor = ArtifactProjector.seatAnchorId("model_a#0")
    XCTAssertTrue(html.contains("href=\"#\(anchor)\""))
    XCTAssertTrue(html.contains("id=\"\(anchor)\""))
  }

  func testMockupColumnCount() {
    XCTAssertEqual(ArtifactProjector.mockupColumnCount(for: 1), 1)
    XCTAssertEqual(ArtifactProjector.mockupColumnCount(for: 2), 2)
    XCTAssertEqual(ArtifactProjector.mockupColumnCount(for: 3), 3)
    XCTAssertEqual(ArtifactProjector.mockupColumnCount(for: 4), 2)
    XCTAssertEqual(ArtifactProjector.mockupColumnCount(for: 5), 3)
  }

  func testMockupImageOpensLightboxNotEvidence() {
    let worker = Agent(id: "model_k3#0", modelId: "model_k3", instanceIndex: 0,
                        skillId: "visual_system_designer", skillName: "Visual System Designer",
                        purpose: .answer)
    let board = BoardPayload(targetShape: .desktop, options: [
      DesignOption(agentId: "model_k3#0", modelId: "model_k3", persona: "visual_system_designer",
                   imagePath: "option_model_k3-0.png", status: .done)
    ])
    let run = TeamRun(
      id: "run_mockup_click", prompt: "Redesign?", status: .done,
      workers: [worker],
      answers: [
        TeamAnswer(memberId: "model_k3#0", modelId: "model_k3", role: "answer",
                   result: WorkerRunResult(status: .done, output: """
                   ```seat
                   {"schemaVersion":1,"summary":"Widen the memo."}
                   ```
                   """, timing: RunTiming(durationMs: 10))),
      ],
      stages: [
        StageOutput(id: "board-1", purpose: .board, status: .done, payload: .board(board))
      ],
      createdAt: now,
      lane: .design,
      outputKind: .designBoard
    )
    let html = ArtifactProjector.renderHTML(ArtifactProjector.project(run))
    let seat = ArtifactProjector.seatAnchorId("model_k3#0")
    let lightbox = ArtifactProjector.mockupLightboxId("model_k3#0")
    XCTAssertTrue(html.contains("href=\"#\(lightbox)\""), "image should open lightbox")
    XCTAssertTrue(html.contains("id=\"\(lightbox)\""), "lightbox target present")
    XCTAssertTrue(html.contains("class=\"mockup-lightbox\""))
    // Image tile must not jump straight to Evidence; caption may still link there.
    XCTAssertFalse(
      html.contains("class=\"mockup-link\" href=\"#\(seat)\""),
      "mockup image must not be an Evidence jump"
    )
    XCTAssertTrue(html.contains("class=\"mockup-evidence\" href=\"#\(seat)\""))
  }

  func testNoSeatFenceMeansBlankOneLiner() {
    let worker = Agent(id: "model_a#0", modelId: "model_a", instanceIndex: 0,
                        skillId: "hierarchy_sculptor", skillName: "Hierarchy Sculptor",
                        purpose: .answer)
    let run = TeamRun(
      id: "run_no_seat", prompt: "x", status: .done,
      workers: [worker],
      answers: [
        TeamAnswer(memberId: "model_a#0", modelId: "model_a", role: "answer",
                   result: WorkerRunResult(status: .done, output: "I'll open the file.\nSome notes.",
                                           timing: RunTiming(durationMs: 10))),
      ],
      stages: [], createdAt: now
    )
    let card = ArtifactProjector.project(run)
    XCTAssertNil(card.seats[0].oneLiner)
  }

  func testEvidenceRepairsStreamJoinedSentences() {
    let md = """
    I'll read first, then produce a mockup that matches them.Checking how mockups are stored.path.Building one layout.Opening to verify.The private finish should open as a calm Ready memo.

    ### Mockup
    Real craft with a proper space after periods. Next sentence is fine.
    """
    let worker = Agent(id: "model_a#0", modelId: "model_a", instanceIndex: 0,
                        skillId: "visual_system_designer", skillName: "Visual System Designer",
                        purpose: .answer)
    let run = TeamRun(
      id: "run_spaces", prompt: "Design?", status: .done,
      workers: [worker],
      answers: [
        TeamAnswer(memberId: "model_a#0", modelId: "model_a", role: "answer",
                   result: WorkerRunResult(status: .done, output: md,
                                           timing: RunTiming(durationMs: 10))),
      ],
      stages: [], createdAt: now
    )
    let body = ArtifactProjector.project(run).evidence[0].bodyMarkdown
    XCTAssertFalse(body.contains("them.Checking"))
    XCTAssertFalse(body.contains("path.Building"))
    XCTAssertTrue(body.contains("### Mockup") || body.contains("Real craft"))
    XCTAssertTrue(body.contains("periods. Next") || body.contains("periods. Next sentence"))
    XCTAssertFalse(body.lowercased().hasPrefix("i'll"))
  }

  func testAskedFallsBackWithoutDumpingAgentBrief() {
    let brief = """
    ## Round 3 dogfood. Open these files and critique the HTML.
    Workers critique hierarchy. Should we polish again?
    """
    let md = """
    ```lead-call
    {"schemaVersion":1,"status":"Ready","call":"Polish once more.","title":"One more polish"}
    ```
    """
    var run = multiSeatRun(leadMarkdown: md)
    run.prompt = brief
    let card = ArtifactProjector.project(run)
    XCTAssertEqual(card.title, "One more polish")
    XCTAssertFalse(card.asked.lowercased().contains("open these"))
    XCTAssertFalse(card.asked.lowercased().contains("##"))
    XCTAssertTrue(card.asked.count <= 140)
  }

  func testLaw2SingleSeatHoistUsesAnswerMarkdownOnChip() {
    // Agent row empty (Law-2 nulled); markdown lives on the synthesized answer via plan.
    let worker = Agent(id: "model_sonnet#0", modelId: "model_sonnet", instanceIndex: 0,
                        skillId: "lead", skillName: "Lead", purpose: .plan)
    let answers = [
      TeamAnswer(memberId: "model_sonnet#0", modelId: "model_sonnet", role: "plan",
                 result: WorkerRunResult(status: .done, output: "",
                                         timing: RunTiming(durationMs: 1200))),
    ]
    let plan = StageOutput(
      id: "stage_plan", purpose: .plan, producedByAgentId: "model_sonnet#0",
      status: .done, payload: .plan(markdown: "Hoisted success one-liner")
    )
    let run = TeamRun(
      id: "run_single", prompt: "Say success.", status: .done,
      workers: [worker], answers: answers, stages: [plan], createdAt: now
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

  func testFaviconIsSelfContainedBrandMark() {
    let html = ArtifactProjector.renderHTML(
      ArtifactProjector.project(multiSeatRun(leadMarkdown: leadCallMarkdown))
    )
    XCTAssertTrue(
      html.contains("<link rel=\"icon\" type=\"image/svg+xml\" href=\"\(ArtifactProjector.faviconDataURI)\">")
    )
    // Must not depend on a repo-relative asset path (breaks for written artifacts).
    XCTAssertFalse(html.contains("allnighter-icon.svg"))
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
    let worker = Agent(id: "model_a#0", modelId: "model_a", instanceIndex: 0, purpose: .answer)
    let run = TeamRun(
      id: "run_empty", prompt: "Empty?", status: .failed,
      workers: [worker],
      answers: [
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
    // When Lead omits asked, prompt fallback is capped.
    let longPrompt = String(repeating: "q", count: 150)
    let md = """
    ```lead-call
    {"schemaVersion":1,"status":"Ready","call":"Ship it.","title":"Ship it"}
    ```
    """
    var run = multiSeatRun(leadMarkdown: md)
    run.prompt = longPrompt
    let card = ArtifactProjector.project(run)
    XCTAssertEqual(card.asked.count, 141)
    XCTAssertTrue(card.asked.hasSuffix("…"))
  }

  func testLeadSeatNotQueuedWhenAnswerHoisted() {
    let worker = Agent(id: "model_opus#1", modelId: "model_opus", instanceIndex: 1,
                        skillId: "lead", skillName: "Lead", purpose: .plan)
    let answers = [
      TeamAnswer(memberId: "model_opus#1", modelId: "model_opus", role: "plan",
                 result: WorkerRunResult(status: .queued, output: "",
                                         timing: RunTiming(durationMs: nil))),
    ]
    let plan = StageOutput(
      id: "stage_plan", purpose: .plan, producedByAgentId: "model_opus#1",
      status: .done, payload: .plan(markdown: leadCallMarkdown)
    )
    let run = TeamRun(
      id: "run_lead_hoist", prompt: "Ship?", status: .complete,
      workers: [worker], answers: answers, stages: [plan], createdAt: now,
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
    XCTAssertTrue(html.contains("Ship the artifact CLI first"))
    XCTAssertTrue(html.contains("Asked"))
    XCTAssertTrue(html.contains("Should we ship the artifact CLI?"))
    XCTAssertTrue(html.contains("Evidence"))
    XCTAssertTrue(html.contains("id=\"seat-"))
    XCTAssertTrue(html.contains("Do this next") || html.contains("Next"))
    XCTAssertFalse(html.contains("Full notes (appendix)"))
  }

  func testScoutExcludedFromSeatSet() {
    let workers = [
      Agent(id: "scout#0", modelId: "model_grok", instanceIndex: 0, purpose: .scout),
      Agent(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0, purpose: .answer),
    ]
    let run = TeamRun(
      id: "run_scout", prompt: "x", status: .done, workers: workers,
      answers: [], stages: [], createdAt: now
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
