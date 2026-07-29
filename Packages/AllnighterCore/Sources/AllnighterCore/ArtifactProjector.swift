import Foundation
import AgentOSTeam

/// Projects a terminal `TeamRun` into a private HTML team artifact (TRR-S01).
/// Pure and deterministic — no filesystem or run store.
///
/// Reading contract: full-bleed memo page (K3 dogfood 2026-07-26) — sticky
/// masthead with mark + verdict; Design board + team at content width; prose at
/// reading measure; mockup click → lightbox; chips → Evidence; full craft below.

public enum ArtifactProjector {
  public static let honesty = "alln-attested multi-seat artifact · not vendor-signed"

  public struct Recommendation: Equatable, Sendable {
    public var decision: String
    public var lean: String
    public var why: String
  }

  public struct Seat: Equatable, Sendable {
    public var agentId: String
    /// Role / skill label — primary headline on the chip.
    public var roleLabel: String
    /// Model display name — muted attribution.
    public var modelLabel: String
    public var sourceId: String
    public var status: String
    public var durationMs: Int?
    public var oneLiner: String?
    public var isLead: Bool
  }

  /// Design-board mockup tile (hero). `relSrc` is relative to the HTML file.
  public struct Mockup: Equatable, Sendable {
    public var agentId: String
    public var label: String
    public var relSrc: String?
    public var status: String
    public var failureReason: String?
  }

  /// Full seat craft under Evidence — chip `#seat-<agentId>` lands here.
  public struct Evidence: Equatable, Sendable {
    public var agentId: String
    public var roleLabel: String
    public var modelLabel: String
    public var bodyMarkdown: String
    public var isLead: Bool
  }

  public struct Card: Equatable, Sendable {
    public var runId: String
    /// Outcome headline (from Lead call) — never the raw prompt.
    public var title: String
    /// Muted “Asked” line (capped prompt).
    public var asked: String
    public var teamLabel: String
    public var verdict: String?
    public var verdictPartial: Bool
    public var call: String?
    /// Only shown when substantive (not worker-meta gossip).
    public var whyItMatters: String?
    public var recommendations: [Recommendation]
    public var nextMove: String?
    public var cta: String
    public var mockups: [Mockup]
    public var seats: [Seat]
    /// CMR-S05 (Cross_Model_Review_Hardening.md) — which model(s) drafted
    /// (`.answer`) vs reviewed (`.review`) this run's crew, when the team
    /// carries both roles. Derived from existing `Agent.purpose`; nil when
    /// the team has no review-stage seat (nothing to pair against a writer).
    public var writerReviewerLine: String?
    public var evidence: [Evidence]
    public var reproduceLine: String?
    public var runIdLine: String
    public var honesty: String
  }

  public struct Context {
    public var modelDisplayName: (String) -> String
    public var sourceId: (String) -> String

    public init(
      models: [Model] = [],
      manifests _: [DriverManifest] = []
    ) {
      let modelById = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
      modelDisplayName = { modelById[$0]?.displayName ?? $0 }
      sourceId = { modelById[$0]?.driverId ?? "" }
    }

    public init(
      modelDisplayName: @escaping (String) -> String,
      sourceId: @escaping (String) -> String
    ) {
      self.modelDisplayName = modelDisplayName
      self.sourceId = sourceId
    }
  }

  public static func canProject(_ run: TeamRun) -> Bool { run.status.isTerminal }

  public static func project(
    _ run: TeamRun,
    reproduceCommand: String? = nil,
    context: Context = .init(),
    runDirectory: URL? = nil,
    mockupRelSrc: [String: String] = [:]
  ) -> Card {
    let trj = TeamRunJSONMapper.map(
      run, models: [], manifests: [],
      context: .init(runJournalPath: "", runDirectory: runDirectory)
    )
    let leadMarkdown = trj.answer?.markdown ?? run.plan
    let leadCall = LeadCallParser.parse(from: leadMarkdown)

    let teamLabel = run.teamDisplayName ?? run.presetId ?? "Team run"
    let verdict = normalizedVerdict(leadCall?.status)
    let call = leadCall?.call
      ?? fallbackCall(from: leadMarkdown)
      ?? "(no synthesized output — status \(run.status.rawValue))"
    let title = resolveTitle(leadCall: leadCall, call: call, teamLabel: teamLabel)
    let asked = resolveAsked(leadCall: leadCall, prompt: run.prompt)
    let recommendations = (leadCall?.recommendations ?? [])
      .compactMap { rec -> Recommendation? in
        guard let decision = rec.decision, !decision.isEmpty else { return nil }
        return Recommendation(
          decision: decision,
          lean: rec.lean ?? "",
          why: rec.why ?? ""
        )
      }

    let whyItMatters = substantiveChanged(leadCall?.changed)
    let nextMove = leadCall?.nextMove.flatMap { $0.isEmpty ? nil : $0 }
    let cta = primaryCTA(partial: verdict == "Partial", nextMove: nextMove)
    let nextMoveForCard: String? = {
      guard let nextMove else { return nil }
      if nextMove == cta { return nil }
      return nextMove
    }()
    let seats = seatCards(for: run, hoistedAnswer: trj.answer, context: context)
    let writerReviewerLine = writerReviewerPairingLine(for: run, context: context)
    let mockups = mockupTiles(
      board: trj.designBoard,
      mockupRelSrc: mockupRelSrc,
      context: context
    )
    let evidence = evidenceSections(
      for: run,
      seats: seats,
      hoistedAnswer: trj.answer
    )

    let (reproduceLine, _) = elidedReproduce(
      command: reproduceCommand,
      runId: run.id
    )

    return Card(
      runId: run.id,
      title: title,
      asked: asked,
      teamLabel: teamLabel,
      verdict: verdict,
      verdictPartial: verdict == "Partial",
      call: capped(call, max: 320),
      whyItMatters: whyItMatters.map { capped($0, max: 200) },
      recommendations: recommendations,
      nextMove: nextMoveForCard.map { capped($0, max: 200) },
      cta: cta,
      mockups: mockups,
      seats: seats,
      writerReviewerLine: writerReviewerLine,
      evidence: evidence,
      reproduceLine: reproduceLine,
      runIdLine: run.id,
      honesty: honesty
    )
  }

  /// Brand mark for browser tabs. Base64 (not percent-encoded SVG) so
  /// gradient `url(#…)` fragments never truncate the data URI — the usual
  /// reason a relative/file favicon appears only on mockups or intermittently.
  public static let faviconDataURI =
    "data:image/svg+xml;base64,"
    + "PHN2ZyB3aWR0aD0iMTAyNCIgaGVpZ2h0PSIxMDI0IiB2aWV3Qm94PSIwIDAgMTAwIDEwMCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KICA8ZGVmcz4KICAgIDxyYWRpYWxHcmFkaWVudCBpZD0iYmciIGN4PSI1MCUiIGN5PSIzMCUiIHI9Ijg4JSI+CiAgICAgIDxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiMxQjIxMzgiPjwvc3RvcD48c3RvcCBvZmZzZXQ9IjUyJSIgc3RvcC1jb2xvcj0iIzBCMEUxQSI+PC9zdG9wPjxzdG9wIG9mZnNldD0iMTAwJSIgc3RvcC1jb2xvcj0iIzA1MDYwQyI+PC9zdG9wPgogICAgPC9yYWRpYWxHcmFkaWVudD4KICAgIDxyYWRpYWxHcmFkaWVudCBpZD0iZ2xvdyIgY3g9IjUwJSIgY3k9IjUwJSIgcj0iNTAlIj4KICAgICAgPHN0b3Agb2Zmc2V0PSIwJSIgc3RvcC1jb2xvcj0iI0ZGQTYzMCIgc3RvcC1vcGFjaXR5PSIwLjUiPjwvc3RvcD4KICAgICAgPHN0b3Agb2Zmc2V0PSI0NiUiIHN0b3AtY29sb3I9IiNGRkE2MzAiIHN0b3Atb3BhY2l0eT0iMC4xNCI+PC9zdG9wPgogICAgICA8c3RvcCBvZmZzZXQ9IjEwMCUiIHN0b3AtY29sb3I9IiNGRkE2MzAiIHN0b3Atb3BhY2l0eT0iMCI+PC9zdG9wPgogICAgPC9yYWRpYWxHcmFkaWVudD4KICAgIDxsaW5lYXJHcmFkaWVudCBpZD0iY2ciIHgxPSIyMCIgeTE9IjI0IiB4Mj0iNjYiIHkyPSI4MCIgZ3JhZGllbnRVbml0cz0idXNlclNwYWNlT25Vc2UiPgogICAgICA8c3RvcCBvZmZzZXQ9IjAiIHN0b3AtY29sb3I9IiNGRkQ3OUUiPjwvc3RvcD48c3RvcCBvZmZzZXQ9Ii41IiBzdG9wLWNvbG9yPSIjRkZBNjMwIj48L3N0b3A+PHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSIjRjA5MDFDIj48L3N0b3A+CiAgICA8L2xpbmVhckdyYWRpZW50PgogICAgPG1hc2sgaWQ9ImNtIj48cmVjdCB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgZmlsbD0iYmxhY2siPjwvcmVjdD4KICAgICAgPGNpcmNsZSBjeD0iNDciIGN5PSI1MCIgcj0iMzIiIGZpbGw9IndoaXRlIj48L2NpcmNsZT48Y2lyY2xlIGN4PSI2MiIgY3k9IjQxIiByPSIyOCIgZmlsbD0iYmxhY2siPjwvY2lyY2xlPjwvbWFzaz4KICA8L2RlZnM+CiAgPHJlY3Qgd2lkdGg9IjEwMCIgaGVpZ2h0PSIxMDAiIHJ4PSIyMyIgZmlsbD0idXJsKCNiZykiPjwvcmVjdD4KICA8Y2lyY2xlIGN4PSI0NiIgY3k9IjQ4IiByPSI0NCIgZmlsbD0idXJsKCNnbG93KSI+PC9jaXJjbGU+CiAgPHJlY3Qgd2lkdGg9IjEwMCIgaGVpZ2h0PSIxMDAiIGZpbGw9InVybCgjY2cpIiBtYXNrPSJ1cmwoI2NtKSI+PC9yZWN0PgogIDxyZWN0IHg9IjAuNSIgeT0iMC41IiB3aWR0aD0iOTkiIGhlaWdodD0iOTkiIHJ4PSIyMi41IiBmaWxsPSJub25lIiBzdHJva2U9IiNmZmYiIHN0cm9rZS1vcGFjaXR5PSIwLjA3Ij48L3JlY3Q+Cjwvc3ZnPg=="

  public static func renderHTML(_ card: Card) -> String {
    let css = embeddedStylesheet()
    let body = htmlBody(card)
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>\(escape(card.title))</title>
      <link rel="icon" type="image/svg+xml" href="\(faviconDataURI)">
      <style>\(css)</style>
    </head>
    <body>
      <div class="page">
        \(body)
      </div>
    </body>
    </html>
    """
  }

  /// G13 — deterministic static-render gate for settled artifacts.
  public static func g13Violations(in html: String) -> [String] {
    var issues: [String] = []
    if html.contains("animation:") { issues.append("animation") }
    if html.contains("@keyframes") { issues.append("keyframes") }
    if html.contains("--glow-") { issues.append("glow-token") }
    let outsideStyle = html.components(separatedBy: "</style>").dropFirst().joined(separator: "")
    if outsideStyle.range(of: "#[0-9A-Fa-f]{3,8}", options: .regularExpression) != nil {
      issues.append("hex-outside-token-layer")
    }
    let header = html.components(separatedBy: "<section class=\"seats\">").first ?? html
    let amberEvents = header.components(separatedBy: "accent-event").count - 1
    if amberEvents > 1 { issues.append("multiple-amber-content-events") }
    return issues
  }

  // MARK: - Seat cards

  private static func seatCards(
    for run: TeamRun,
    hoistedAnswer: TeamRunJSON.Answer?,
    context: Context
  ) -> [Seat] {
    let seatWorkers = TeamRunSeatSet.workers(for: run)
    let modelCounts = Dictionary(grouping: seatWorkers, by: \.modelId).mapValues(\.count)
    let mapped = seatWorkers.map { worker -> Seat in
      let answer = run.workerAnswer(workerId: worker.id)
      let (status, durationMs) = resolvedSeatStatus(
        worker: worker,
        answer: answer,
        hoistedAnswer: hoistedAnswer
      )
      let sharesModel = (modelCounts[worker.modelId] ?? 0) > 1
      let modelLabel = worker.displayName(
        modelName: context.modelDisplayName(worker.modelId),
        sharesModel: sharesModel
      )
      let markdown = seatMarkdown(
        worker: worker, answer: answer, hoistedAnswer: hoistedAnswer
      )
      let isLead = worker.purpose == .plan
      return Seat(
        agentId: worker.id,
        roleLabel: roleLabel(for: worker, isLead: isLead),
        modelLabel: modelLabel,
        sourceId: context.sourceId(worker.modelId),
        status: status,
        durationMs: durationMs,
        oneLiner: isLead
          ? leadSeatOneLiner(hoistedAnswer: hoistedAnswer, markdown: markdown)
          : crewSeatOneLiner(from: markdown),
        isLead: isLead
      )
    }
    // Lead first — decision owner before evidence seats.
    return mapped.sorted { a, b in
      if a.isLead != b.isLead { return a.isLead && !b.isLead }
      return false
    }
  }

  /// CMR-S05 (Cross_Model_Review_Hardening.md) — pairs the run's writer(s)
  /// (`.answer`-stage workers) against its reviewer(s) (`.review`-stage
  /// workers), by distinct model display name in declaration order. Reuses
  /// data already carried on `Agent.purpose` — no new stored field, no
  /// contract/schema change. Returns nil when the team has no review-stage
  /// seat (e.g. answer-only or plan-only teams — no pairing to report).
  private static func writerReviewerPairingLine(for run: TeamRun, context: Context) -> String? {
    let workers = TeamRunSeatSet.workers(for: run)
    func distinctNames(_ stage: AgentStage) -> [String] {
      var seen = Set<String>()
      var names: [String] = []
      for worker in workers where worker.purpose == stage {
        let name = context.modelDisplayName(worker.modelId)
        if seen.insert(name).inserted { names.append(name) }
      }
      return names
    }
    let reviewers = distinctNames(.review)
    guard !reviewers.isEmpty else { return nil }
    let writers = distinctNames(.answer)
    guard !writers.isEmpty else { return nil }
    return "Writer: \(writers.joined(separator: ", ")) · Reviewer: \(reviewers.joined(separator: ", "))"
  }

  private static func roleLabel(for worker: Agent, isLead: Bool) -> String {
    if isLead { return "Lead" }
    if let name = worker.skillName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return shortRole(name)
    }
    if let id = worker.skillId, !id.isEmpty {
      return shortRole(SkillCatalog.displayName(for: id))
    }
    switch worker.purpose {
    case .review: return "Review"
    case .answer: return "Seat"
    default: return "Seat"
    }
  }

  private static func shortRole(_ name: String) -> String {
    // "Hierarchy Sculptor" → "Hierarchy"; "Type & Spacing Auditor" → "Type & spacing"
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let dropSuffixes = [" Sculptor", " Auditor", " Critic", " Reviewer", " Writer", " Planner"]
    for suffix in dropSuffixes where trimmed.hasSuffix(suffix) {
      return String(trimmed.dropLast(suffix.count))
    }
    return trimmed
  }

  private static func leadSeatOneLiner(
    hoistedAnswer: TeamRunJSON.Answer?,
    markdown: String?
  ) -> String? {
    let md = hoistedAnswer?.markdown ?? markdown
    if let call = LeadCallParser.parse(from: md)?.call {
      return titleAtWordBoundary(call, max: 280)
    }
    if let summary = SeatSummaryParser.summary(from: md) {
      return titleAtWordBoundary(summary, max: 280)
    }
    // Lead without lead-call / seat fence: use the same call fallback as the memo.
    if let call = fallbackCall(from: md) {
      return titleAtWordBoundary(call, max: 280)
    }
    return nil
  }

  /// Law-2 + trust: Lead chip must not stay `queued` when the synthesized answer exists.
  private static func resolvedSeatStatus(
    worker: Agent,
    answer: TeamAnswer?,
    hoistedAnswer: TeamRunJSON.Answer?
  ) -> (String, Int?) {
    var status = answer?.result.status.rawValue ?? "queued"
    var durationMs = answer?.result.timing.durationMs
    let emptyOutput = answer?.output?
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    if worker.purpose == .plan,
       let hoisted = hoistedAnswer,
       (answer == nil || status == "queued" || emptyOutput) {
      status = hoisted.status.rawValue
      if durationMs == nil {
        durationMs = nil
      }
    }
    return (status, durationMs)
  }

  private static func seatMarkdown(
    worker: Agent,
    answer: TeamAnswer?,
    hoistedAnswer: TeamRunJSON.Answer?
  ) -> String? {
    var markdown = answer?.output
    if markdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
       hoistedAnswer?.source.agentId == worker.id {
      markdown = hoistedAnswer?.markdown
    }
    return markdown
  }

  private static func crewSeatOneLiner(from markdown: String?) -> String? {
    // Declared elevator only — no first-line scrape / debris lottery.
    guard let summary = SeatSummaryParser.summary(from: markdown) else { return nil }
    return titleAtWordBoundary(summary, max: 280)
  }

  private static func mockupTiles(
    board: TeamRunJSON.DesignBoard?,
    mockupRelSrc: [String: String],
    context _: Context
  ) -> [Mockup] {
    guard let board else { return [] }
    return board.options.map { opt in
      let label = SkillCatalog.displayName(for: opt.persona)
      let rel = mockupRelSrc[opt.agentId]
        ?? opt.imagePath.map { "mockups/\(($0 as NSString).lastPathComponent)" }
      return Mockup(
        agentId: opt.agentId,
        label: label,
        relSrc: opt.status == .done ? rel : nil,
        status: opt.status.rawValue,
        failureReason: opt.failureReason
      )
    }
  }

  private static func evidenceSections(
    for run: TeamRun,
    seats: [Seat],
    hoistedAnswer: TeamRunJSON.Answer?
  ) -> [Evidence] {
    seats.map { seat in
      let worker = run.workers.first { $0.id == seat.agentId }
      let answer = run.workerAnswer(workerId: seat.agentId)
      var markdown = seatMarkdown(
        worker: worker ?? Agent(id: seat.agentId, modelId: "", instanceIndex: 0),
        answer: answer,
        hoistedAnswer: seat.isLead ? hoistedAnswer : nil
      )
      if seat.isLead, markdown == nil || markdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
        markdown = hoistedAnswer?.markdown ?? run.plan
      }
      let body = evidenceBody(from: markdown, isLead: seat.isLead)
      return Evidence(
        agentId: seat.agentId,
        roleLabel: seat.roleLabel,
        modelLabel: seat.modelLabel,
        bodyMarkdown: body,
        isLead: seat.isLead
      )
    }
  }

  private static func evidenceBody(from markdown: String?, isLead: Bool) -> String {
    guard let markdown, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return "_(No written craft for this seat.)_"
    }
    let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    if looksLikeImagePath(trimmed) {
      return "Mockup is in the hero above."
    }
    var body = LeadCallParser.stripFence(from: trimmed)
    body = SeatSummaryParser.stripFence(from: body)
    // Drop the visible Summary: line — chip already has the elevator.
    let lines = body.components(separatedBy: "\n").filter { line in
      let t = line.trimmingCharacters(in: .whitespaces)
      let lower = t.lowercased()
      if lower.hasPrefix("summary:") { return false }
      if lower.hasPrefix("**summary:**") { return false }
      return true
    }
    body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    body = repairStreamJoinedSentences(body)
    body = stripProcessPreamble(from: body)
    if body.isEmpty { return "_(No written craft for this seat.)_" }
    return isLead ? shortenCraft(body) : body
  }

  /// Workers often mash tool narration onto one line: `done.Checking next`.
  /// Insert the missing space before a new English sentence (not `4.0` / `U.S.`).
  private static func repairStreamJoinedSentences(_ text: String) -> String {
    text.replacingOccurrences(
      of: #"([.!?])([A-Z][a-z]+)"#,
      with: "$1 $2",
      options: .regularExpression
    )
  }

  /// Drop leading I'll/Checking narration when real craft headings follow.
  private static func stripProcessPreamble(from text: String) -> String {
    let lines = text.components(separatedBy: "\n")
    guard let headingIdx = lines.firstIndex(where: { line in
      let t = line.trimmingCharacters(in: .whitespaces)
      return t.hasPrefix("### ") || t.hasPrefix("## ") || t.hasPrefix("# ")
    }) else { return text }
    let before = lines[..<headingIdx].joined(separator: "\n").lowercased()
    let looksLikeProcess =
      before.contains("i'll ") || before.contains("i will ")
      || before.contains("checking ") || before.contains("opening ")
      || before.contains("building ") || before.contains("reviewing ")
    guard looksLikeProcess else { return text }
    return lines[headingIdx...]
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func looksLikeImagePath(_ text: String) -> Bool {
    let lower = text.lowercased()
    return (lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")
      || lower.hasSuffix(".webp"))
      && !text.contains("\n") && text.count < 200
  }

  // MARK: - HTML

  private static let crescentSVG = """
  <svg class="crescent" width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
    <path fill-rule="evenodd" fill="var(--accent)"
      d="M 6.2 1.5 a 5.5 5.5 0 1 0 0 11 a 5.5 5.5 0 1 0 0 -11 Z
         M 8.6 2.4 a 4.6 4.6 0 1 1 0 9.2 a 4.6 4.6 0 1 1 0 -9.2 Z"/>
  </svg>
  """

  private static func htmlBody(_ card: Card) -> String {
    var parts: [String] = []

    // Sticky masthead: brand left, verdict right (same place every run).
    let verdictLabel: String = {
      guard card.verdict != nil else { return "" }
      return card.verdictPartial ? "Partial · needs you" : "Ready"
    }()
    let verdictClass = card.verdictPartial ? "verdict verdict-partial" : "verdict verdict-ready"
    parts.append(
      """
      <header class="masthead">
        <div class="brand">
          \(crescentSVG)
          <span class="brand-word">Allnighter</span>
          <span class="brand-sep">·</span>
          <span class="brand-what">Team artifact</span>
        </div>
        \(card.verdict == nil ? "" : "<div class=\"\(verdictClass)\">\(escape(verdictLabel))</div>")
      </header>
      """
    )

    parts.append("<main class=\"doc\">")

    // Memo head: team line + decision headline + asked (+ why as support).
    parts.append("<header class=\"run-head\">")
    parts.append("<div class=\"eyebrow\">\(escape(card.teamLabel))</div>")
    parts.append("<h1 class=\"title\">\(escape(card.title))</h1>")
    parts.append(
      "<p class=\"asked\"><span class=\"asked-label\">Asked</span> \(escape(card.asked))</p>"
    )
    if let why = card.whyItMatters, !why.isEmpty {
      parts.append(
        "<p class=\"changed\"><strong>What changed</strong> — \(escape(why))</p>"
      )
    }
    parts.append("</header>")

    if card.verdictPartial {
      parts.append(needsYouHTML(card))
    }

    // Design board under the header (full content width).
    if !card.mockups.isEmpty {
      parts.append(mockupsHTML(card.mockups))
    }

    // Call only when it adds beyond the H1.
    if let call = card.call, !call.isEmpty, !callRedundant(withTitle: card.title, call: call) {
      parts.append(
        "<section class=\"call prose\"><h2>The decision</h2>"
          + "<p class=\"call-text\">\(escape(call))</p></section>"
      )
    }

    if !card.recommendations.isEmpty {
      let heading = card.verdictPartial ? "Options for you" : "Recommendations"
      parts.append("<section class=\"recommendations\"><h2>\(heading)</h2><ol>")
      for rec in card.recommendations {
        let lean = rec.lean.isEmpty ? "" : " — \(escape(rec.lean))"
        let why = rec.why.isEmpty ? "" : "<div class=\"rec-why\">\(escape(rec.why))</div>"
        parts.append(
          "<li><strong>\(escape(rec.decision))</strong>\(lean)\(why)</li>"
        )
      }
      parts.append("</ol></section>")
    }

    parts.append(
      "<section class=\"cta-block\(card.verdictPartial ? " cta-partial" : "")\">"
        + "<div class=\"cta-label\">Next</div>"
        + "<p class=\"cta-text\">\(escape(card.cta))</p>"
        + (card.nextMove.map { "<p class=\"cta-detail\">\(escape($0))</p>" } ?? "")
        + "</section>"
    )

    // One team section: Lead first, then crew (full content width).
    if !card.seats.isEmpty {
      let ordered = card.seats.filter(\.isLead) + card.seats.filter { !$0.isLead }
      let pairingHTML = card.writerReviewerLine.map {
        "<p class=\"seat-pairing\">\(escape($0))</p>"
      } ?? ""
      parts.append(
        "<section class=\"seats\"><h2>The team</h2>\(pairingHTML)<div class=\"seat-grid\">"
      )
      for seat in ordered {
        parts.append(seatChipHTML(seat))
      }
      parts.append("</div></section>")
    }

    if !card.evidence.isEmpty {
      parts.append(
        "<section class=\"evidence\"><h2>Evidence"
          + "<span class=\"h2-note\">full seat craft — chips above jump here</span></h2>"
      )
      for item in card.evidence {
        parts.append(evidenceHTML(item))
      }
      parts.append("</section>")
    }

    parts.append("</main>")

    // Footer: crescent + honesty left; reproduce + run id right.
    parts.append("<footer class=\"footer\">")
    parts.append(
      "<div class=\"foot-brand\">\(crescentSVG)"
        + "<span class=\"honesty\">\(escape(card.honesty))</span></div>"
    )
    parts.append("<div class=\"foot-right\">")
    if let reproduce = card.reproduceLine, !reproduce.isEmpty {
      parts.append("<div class=\"reproduce\">\(escape(reproduce))</div>")
    }
    parts.append("<div class=\"run-id\">Run \(escape(card.runIdLine))</div>")
    parts.append("</div></footer>")

    return parts.joined(separator: "\n")
  }

  /// Stable HTML id / fragment for a seat (worker ids contain `#`).
  public static func seatAnchorId(_ workerId: String) -> String {
    "seat-" + workerId
      .replacingOccurrences(of: "#", with: "-")
      .replacingOccurrences(of: "/", with: "-")
  }

  /// Desktop columns: 1→1, 2→2, 3→3, 4→2×2, 5+→3 per row. Mobile always stacks.
  public static func mockupColumnCount(for count: Int) -> Int {
    switch count {
    case 0, 1: return 1
    case 2: return 2
    case 3: return 3
    case 4: return 2
    default: return 3
    }
  }

  /// Fragment id for the full-bleed mockup lightbox (not the Evidence seat).
  public static func mockupLightboxId(_ workerId: String) -> String {
    "mockup-" + seatAnchorId(workerId)
  }

  private static func mockupsHTML(_ mockups: [Mockup]) -> String {
    let cols = mockupColumnCount(for: mockups.count)
    var parts: [String] = [
      "<section class=\"mockups\">",
      "<h2>Design board</h2>",
      "<div class=\"mockup-grid\" data-count=\"\(mockups.count)\" data-cols=\"\(cols)\">"
    ]
    var lightboxes: [String] = []
    for m in mockups {
      let evidenceHref = "#\(seatAnchorId(m.agentId))"
      if let src = m.relSrc, !src.isEmpty {
        let lightboxId = mockupLightboxId(m.agentId)
        parts.append(
          """
          <figure class="mockup-tile" data-status="\(escape(m.status))">
            <a class="mockup-link" href="#\(lightboxId)" aria-label="Open \(escape(m.label)) full size">
              <img src="\(escape(src))" alt="\(escape(m.label))" loading="lazy">
            </a>
            <figcaption>
              <span class="mockup-label">\(escape(m.label))</span>
              <a class="mockup-evidence" href="\(evidenceHref)">Evidence</a>
            </figcaption>
          </figure>
          """
        )
        lightboxes.append(
          """
          <a class="mockup-lightbox" id="\(lightboxId)" href="#" aria-label="Close full-size mockup">
            <img src="\(escape(src))" alt="\(escape(m.label))">
          </a>
          """
        )
      } else {
        let reason = m.failureReason.map { escape($0) } ?? "No image"
        parts.append(
          """
          <figure class="mockup-tile mockup-failed" data-status="\(escape(m.status))">
            <a class="mockup-link" href="\(evidenceHref)">
              <div class="mockup-placeholder">\(reason)</div>
            </a>
            <figcaption>
              <span class="mockup-label">\(escape(m.label))</span>
              <a class="mockup-evidence" href="\(evidenceHref)">Evidence</a>
            </figcaption>
          </figure>
          """
        )
      }
    }
    parts.append("</div></section>")
    if !lightboxes.isEmpty {
      parts.append(contentsOf: lightboxes)
    }
    return parts.joined(separator: "\n")
  }

  private static func evidenceHTML(_ item: Evidence) -> String {
    let id = seatAnchorId(item.agentId)
    return """
    <article class="evidence-seat" id="\(escape(id))">
      <h3>\(escape(item.roleLabel)) <span class="model-via">via \(escape(item.modelLabel))</span></h3>
      <div class="evidence-body">\(renderSimpleMarkdown(item.bodyMarkdown))</div>
    </article>
    """
  }

  private static func needsYouHTML(_ card: Card) -> String {
    var items = ""
    if card.recommendations.isEmpty {
      items = "<li>Reply with the decision you want locked — the team left this open.</li>"
    } else {
      for rec in card.recommendations {
        items += "<li>\(escape(rec.decision))"
          + (rec.lean.isEmpty ? "" : " → <em>\(escape(rec.lean))</em>")
          + "</li>"
      }
    }
    return """
    <section class="needs-you accent-event">
      <h2>Needs you</h2>
      <p class="needs-lead">This page is not closed until you answer:</p>
      <ul>\(items)</ul>
    </section>
    """
  }

  private static func seatChipHTML(_ seat: Seat) -> String {
    let glyph = String(seat.roleLabel.prefix(1)).uppercased()
    let duration = seat.durationMs.map { formatDuration(ms: $0) } ?? ""
    let durationHTML = duration.isEmpty ? "" : "<span class=\"duration\">\(escape(duration))</span>"
    let leadClass = seat.isLead ? " seat-lead" : ""
    let leadTag = seat.isLead ? "<span class=\"tag-lead\">Lead</span>" : ""
    let oneLiner = seat.oneLiner.map { "<div class=\"one-liner\">\(escape($0))</div>" } ?? ""
    let href = "#\(seatAnchorId(seat.agentId))"
    let statusLabel = statusWord(seat.status)
    return """
    <a class="seat-chip\(leadClass)" href="\(href)" data-status="\(escape(seat.status))">
      <div class="glyph">\(escape(glyph))</div>
      <div class="seat-main">
        <div class="seat-name">\(escape(seat.roleLabel))\(leadTag)</div>
        \(oneLiner)
      </div>
      <div class="seat-meta">
        <span class="chip-model">\(escape(seat.modelLabel))</span>
        <span class="status-dot status-\(escape(seat.status))" aria-hidden="true"></span>
        <span class="status-word status-\(escape(seat.status))">\(escape(statusLabel))</span>
        \(durationHTML)
      </div>
    </a>
    """
  }

  private static func statusWord(_ status: String) -> String {
    switch status.lowercased() {
    case "done", "complete", "completed": return "done"
    case "failed", "fail": return "failed"
    case "running", "in_progress": return "running"
    case "timed_out", "timeout": return "timed out"
    case "queued": return "queued"
    default: return status
    }
  }

  private static func embeddedStylesheet() -> String {
    """
    :root {
      color-scheme: dark;
      --ink-100: #E1E5F0;
      --ink-200: #AEB5C9;
      --ink-300: #7E869E;
      --ink-400: #555C74;
      --ink-600: #252A39;
      --ink-750s: #151822;
      --ink-850: #0D101A;
      --ink-900: #090B13;
      --ink-950: #05060C;
      --amber-400: #FFC169;
      --amber-500: #FFA630;
      --green-500: #3FD18B;
      --red-500: #F76B6B;
      --blue-500: #5B9DFF;
      --yellow-500: #F5C84B;
      --bg-void: var(--ink-950);
      --bg-base: var(--ink-900);
      --bg-raised: var(--ink-750s);
      --text-primary: var(--ink-100);
      --text-secondary: var(--ink-200);
      --text-muted: var(--ink-300);
      --text-faint: var(--ink-400);
      --accent: var(--amber-500);
      --accent-text: var(--amber-400);
      --accent-surface: rgba(255, 166, 48, 0.12);
      --accent-border: rgba(255, 166, 48, 0.32);
      --border-subtle: rgba(255, 255, 255, 0.06);
      --border-default: rgba(255, 255, 255, 0.10);
      --status-queued: var(--ink-400);
      --status-running: var(--blue-500);
      --status-done: var(--green-500);
      --status-failed: var(--red-500);
      --status-timed_out: var(--yellow-500);
      --radius-lg: 10px;
      --page: 1280px;
      --prose: 680px;
      --space-2: 8px;
      --space-3: 12px;
      --space-4: 16px;
      --space-5: 20px;
      --space-6: 24px;
      --space-8: 32px;
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; }
    body {
      background: var(--bg-void);
      color: var(--text-primary);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
      font-size: 14px;
      line-height: 1.45;
      -webkit-font-smoothing: antialiased;
    }
    .page {
      max-width: var(--page);
      margin: 0 auto;
      min-height: 100vh;
      background: var(--bg-base);
      border-left: 1px solid var(--border-subtle);
      border-right: 1px solid var(--border-subtle);
      display: flex;
      flex-direction: column;
    }
    .masthead {
      position: sticky;
      top: 0;
      z-index: 20;
      height: 48px;
      display: flex;
      align-items: center;
      padding: 0 28px;
      border-bottom: 1px solid var(--border-subtle);
      background: var(--bg-base);
    }
    .brand { display: flex; align-items: center; gap: 8px; }
    .brand-word { font-size: 12px; font-weight: 600; letter-spacing: 0.02em; }
    .brand-sep { color: var(--text-faint); }
    .brand-what { font-size: 12px; color: var(--text-muted); }
    .crescent { display: block; flex-shrink: 0; }
    .masthead .verdict {
      margin-left: auto;
      margin-bottom: 0;
      font-size: 12px;
      font-weight: 600;
      padding: 5px 12px;
      border-radius: 999px;
      border: 1px solid var(--border-default);
    }
    .verdict-ready { color: var(--text-primary); background: transparent; }
    .verdict-partial {
      color: var(--accent-text);
      background: var(--accent-surface);
      border-color: var(--accent-border);
    }
    .doc {
      flex: 1;
      padding: 34px 28px 12px;
      width: 100%;
    }
    h1, h2 { margin: 0 0 var(--space-3); font-weight: 600; }
    h1.title {
      font-size: 1.7rem;
      line-height: 1.22;
      letter-spacing: -0.02em;
      max-width: var(--prose);
    }
    h2 {
      font-size: 0.72rem;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      color: var(--text-muted);
      display: flex;
      align-items: baseline;
      gap: var(--space-3);
    }
    .h2-note {
      text-transform: none;
      letter-spacing: 0;
      font-weight: 400;
      color: var(--text-faint);
      font-size: 0.75rem;
    }
    .eyebrow {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 11px;
      color: var(--text-muted);
      margin-bottom: var(--space-3);
    }
    .run-head { margin-bottom: var(--space-6); }
    .asked {
      color: var(--text-muted);
      font-size: 0.9rem;
      margin: var(--space-3) 0 0;
      max-width: var(--prose);
    }
    .asked-label {
      text-transform: uppercase;
      letter-spacing: 0.05em;
      font-size: 0.7rem;
      margin-right: var(--space-2);
    }
    .changed {
      margin: var(--space-3) 0 0;
      color: var(--text-secondary);
      font-size: 0.95rem;
      max-width: var(--prose);
    }
    section { margin-bottom: var(--space-6); }
    .prose, .call { max-width: var(--prose); }
    .call-text { font-size: 1.1rem; margin: 0; line-height: 1.4; }
    .needs-you {
      border: 1px solid var(--accent-border);
      background: var(--accent-surface);
      border-radius: var(--radius-lg);
      padding: var(--space-4);
      max-width: var(--prose);
    }
    .needs-you h2 { color: var(--accent-text); }
    .needs-lead { margin: 0 0 var(--space-3); color: var(--text-primary); }
    .needs-you ul { margin: 0; padding-left: 1.2rem; }
    .needs-you li { margin-bottom: var(--space-2); }
    .recommendations ol { margin: 0; padding-left: 1.2rem; }
    .recommendations li { margin-bottom: var(--space-3); }
    .rec-why { color: var(--text-muted); font-size: 0.9rem; margin-top: 2px; }
    .cta-block {
      border: 1px solid var(--border-default);
      border-radius: var(--radius-lg);
      padding: var(--space-4);
      background: var(--ink-850);
    }
    .cta-block.cta-partial {
      border-color: var(--accent-border);
      background: var(--accent-surface);
    }
    .cta-label {
      font-size: 0.7rem;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      color: var(--text-muted);
      margin-bottom: var(--space-2);
    }
    .cta-text { margin: 0; font-size: 1.05rem; font-weight: 600; }
    .cta-detail { margin: var(--space-2) 0 0; color: var(--text-secondary); font-size: 0.9rem; }
    .seat-pairing {
      color: var(--text-muted);
      font-size: 0.85rem;
      margin: calc(-1 * var(--space-2)) 0 var(--space-3);
    }
    .seat-grid { display: flex; flex-direction: column; gap: var(--space-3); }
    a.seat-chip {
      display: grid;
      grid-template-columns: auto 1fr auto;
      gap: var(--space-3);
      align-items: start;
      text-decoration: none;
      color: inherit;
      padding: var(--space-3) var(--space-4);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      background: var(--ink-850);
    }
    a.seat-chip:hover { border-color: var(--border-default); }
    .seat-lead { border-color: var(--border-default); }
    .glyph {
      width: 28px; height: 28px;
      display: grid; place-items: center;
      border-radius: 6px;
      background: var(--ink-600);
      color: var(--text-primary);
      font-size: 0.75rem;
      font-weight: 600;
    }
    .seat-name {
      font-size: 0.95rem;
      font-weight: 600;
      display: flex;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
    }
    .tag-lead {
      font-size: 0.65rem;
      font-weight: 600;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      color: var(--text-muted);
      border: 1px solid var(--border-default);
      border-radius: 999px;
      padding: 2px 8px;
    }
    .one-liner { color: var(--text-secondary); font-size: 0.85rem; margin-top: 4px; }
    .seat-meta {
      display: flex;
      align-items: center;
      gap: var(--space-2);
      flex-wrap: wrap;
      justify-content: flex-end;
    }
    .chip-model { color: var(--text-faint); font-size: 0.75rem; }
    .status-dot {
      width: 8px; height: 8px; border-radius: 999px;
      display: inline-block;
    }
    .status-word {
      font-size: 0.7rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .status-word.status-done, .status-dot.status-done { color: var(--status-done); }
    .status-dot.status-done { background: var(--status-done); }
    .status-word.status-failed, .status-dot.status-failed { color: var(--status-failed); }
    .status-dot.status-failed { background: var(--status-failed); }
    .status-word.status-running, .status-dot.status-running { color: var(--status-running); }
    .status-dot.status-running { background: var(--status-running); }
    .status-word.status-queued, .status-dot.status-queued { color: var(--status-queued); }
    .status-dot.status-queued { background: var(--status-queued); }
    .status-word.status-timed_out, .status-dot.status-timed_out { color: var(--status-timed_out); }
    .status-dot.status-timed_out { background: var(--status-timed_out); }
    .duration {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      color: var(--text-faint);
      font-size: 0.8rem;
    }
    .mockups { margin: var(--space-6) 0; }
    .mockup-grid {
      display: grid;
      gap: var(--space-4);
      grid-template-columns: 1fr;
    }
    @media (min-width: 900px) {
      .mockup-grid[data-cols="2"] { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .mockup-grid[data-cols="3"] { grid-template-columns: repeat(3, minmax(0, 1fr)); }
    }
    .mockup-tile {
      margin: 0;
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      overflow: hidden;
      background: var(--bg-raised);
    }
    .mockup-link { display: block; color: inherit; text-decoration: none; cursor: zoom-in; }
    .mockup-tile img {
      display: block;
      width: 100%;
      height: auto;
      background: var(--ink-900);
    }
    .mockup-placeholder {
      min-height: 160px;
      display: grid;
      place-items: center;
      padding: var(--space-4);
      color: var(--text-muted);
      font-size: 0.9rem;
      text-align: center;
    }
    .mockup-tile figcaption {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: var(--space-3);
      padding: var(--space-3);
      font-size: 0.85rem;
      color: var(--text-secondary);
      border-top: 1px solid var(--border-subtle);
    }
    .mockup-evidence {
      flex-shrink: 0;
      color: var(--text-faint);
      font-size: 0.75rem;
      text-decoration: none;
    }
    .mockup-evidence:hover { color: var(--amber-500); }
    .mockup-lightbox {
      display: none;
      position: fixed;
      inset: 0;
      z-index: 1000;
      margin: 0;
      background: rgba(5, 6, 12, 0.94);
      align-items: center;
      justify-content: center;
      padding: var(--space-4);
      cursor: zoom-out;
      text-decoration: none;
    }
    .mockup-lightbox:target { display: flex; }
    .mockup-lightbox img {
      max-width: min(1280px, 96vw);
      max-height: 94vh;
      width: auto;
      height: auto;
      object-fit: contain;
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      background: var(--ink-900);
    }
    .evidence { margin: var(--space-8) 0 var(--space-5); }
    .evidence-seat {
      margin: var(--space-5) 0;
      padding: var(--space-4);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      background: var(--ink-850);
      scroll-margin-top: 64px;
    }
    .evidence-seat h3 {
      font-size: 1rem;
      text-transform: none;
      letter-spacing: 0;
      color: var(--text-primary);
      margin: 0 0 var(--space-3);
    }
    .evidence-body {
      color: var(--text-secondary);
      font-size: 0.95rem;
      line-height: 1.55;
      white-space: pre-wrap;
    }
    .model-via { color: var(--text-faint); font-size: 0.75rem; font-weight: 400; margin-left: 0.35rem; }
    .footer {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: var(--space-4);
      margin-top: auto;
      padding: 16px 28px 22px;
      border-top: 1px solid var(--border-subtle);
      font-size: 0.75rem;
      color: var(--text-muted);
    }
    .foot-brand { display: flex; align-items: center; gap: 8px; }
    .foot-right { margin-left: auto; text-align: right; }
    .honesty { color: var(--text-muted); }
    .reproduce {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      color: var(--text-faint);
      max-width: 42rem;
    }
    .run-id { margin-top: 4px; color: var(--text-faint); }
    @media (max-width: 720px) {
      .masthead, .doc { padding-left: 18px; padding-right: 18px; }
      .footer {
        flex-direction: column;
        padding: 16px 18px 22px;
      }
      .foot-right { margin-left: 0; text-align: left; }
      a.seat-chip { grid-template-columns: auto 1fr; }
      .seat-meta { grid-column: 2; justify-content: flex-start; }
      h1.title { font-size: 1.35rem; }
      .page { border-left: 0; border-right: 0; }
    }
    """
  }

  // MARK: - Helpers

  private static func resolveTitle(
    leadCall: LeadCall?,
    call: String,
    teamLabel: String
  ) -> String {
    if let t = leadCall?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
      return titleAtWordBoundary(t, max: 72)
    }
    return titleAtWordBoundary(headlineTitle(call: call, teamLabel: teamLabel), max: 72)
  }

  private static func resolveAsked(leadCall: LeadCall?, prompt: String) -> String {
    if let a = leadCall?.asked?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty {
      return capped(a, max: 140)
    }
    return capped(deriveAskedFromPrompt(prompt), max: 140)
  }

  /// Last-resort Asked when Lead omitted `asked` — never dump agent briefs.
  private static func deriveAskedFromPrompt(_ prompt: String) -> String {
    let plain = plainAsked(prompt)
    let lower = plain.lowercased()
    if lower.contains("dogfood") || lower.contains("open these")
      || lower.contains("workers critique") || lower.contains("round 2")
      || lower.contains("round 3") || lower.hasPrefix("## ") {
      // First clause before structural junk, or a safe generic.
      if let cut = plain.split(separator: ".", maxSplits: 1).first {
        let s = String(cut).trimmingCharacters(in: .whitespaces)
        if s.count >= 12, s.count <= 100, !s.lowercased().contains("open these") {
          return s + "."
        }
      }
      return "Review this team result and decide what to do next."
    }
    // Stop at first markdown heading / numbered work-order section.
    var out = ""
    for part in plain.split(separator: " ", omittingEmptySubsequences: false) {
      let token = String(part)
      if token.hasPrefix("##") || token == "1." { break }
      if out.count + token.count > 100 { break }
      out = out.isEmpty ? token : out + " " + token
    }
    let trimmed = out.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty { return trimmed }
    // Unbroken long prompt (no spaces / no cut) — still never dump the raw blob.
    if plain.count >= 12 { return plain }
    return "Review this team result and decide what to do next."
  }

  private static func headlineTitle(call: String, teamLabel: String) -> String {
    let trimmed = call.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("(") { return "\(teamLabel) · result" }
    // Prefer first sentence; keep ≤ ~12 words when possible.
    let sentence: String
    if let dot = trimmed.firstIndex(of: "."), trimmed.distance(from: trimmed.startIndex, to: dot) < 90 {
      sentence = String(trimmed[...dot]).trimmingCharacters(in: .whitespacesAndNewlines)
    } else if let nl = trimmed.firstIndex(of: "\n") {
      sentence = String(trimmed[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      sentence = trimmed
    }
    let words = sentence.split(separator: " ")
    if words.count > 12 {
      return words.prefix(12).joined(separator: " ") + "…"
    }
    return sentence
  }

  private static func substantiveChanged(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return nil }
    let lower = t.lowercased()
    // Drop worker-meta / process gossip.
    let banned = ["both workers", "i rule", "closed partial", "lockable engineering", "founder fork", "averaging"]
    if banned.contains(where: { lower.contains($0) }) { return nil }
    return t
  }

  private static func primaryCTA(partial: Bool, nextMove: String?) -> String {
    if partial {
      return "Reply with your pick on the Needs you items above."
    }
    if let nextMove, !nextMove.isEmpty {
      return nextMove
    }
    return "Approve this plan — no open questions."
  }

  /// Keep the appendix short: drop repeated Lead Call prose sections if present.
  private static func shortenCraft(_ markdown: String) -> String {
    let lines = markdown.components(separatedBy: "\n")
    var kept: [String] = []
    var skipUntilNextHeading = false
    let dropHeadings = [
      "## status", "## the call", "## what changed", "## recommendations",
      "## contrarian flags", "## next move", "## proof", "## basis", "## worker credit",
    ]
    for line in lines {
      let lower = line.trimmingCharacters(in: .whitespaces).lowercased()
      if lower.hasPrefix("## ") {
        skipUntilNextHeading = dropHeadings.contains(where: { lower.hasPrefix($0) })
        if skipUntilNextHeading { continue }
      }
      if skipUntilNextHeading { continue }
      kept.append(line)
    }
    let joined = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return capped(joined, max: 3500)
  }

  private static func renderSimpleMarkdown(_ text: String) -> String {
    var html: [String] = []
    var inList = false
    for raw in text.components(separatedBy: "\n") {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty {
        if inList { html.append("</ul>"); inList = false }
        continue
      }
      if line.hasPrefix("### ") {
        if inList { html.append("</ul>"); inList = false }
        html.append("<h3>\(escape(String(line.dropFirst(4))))</h3>")
      } else if line.hasPrefix("## ") {
        if inList { html.append("</ul>"); inList = false }
        html.append("<h3>\(escape(String(line.dropFirst(3))))</h3>")
      } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
        if !inList { html.append("<ul>"); inList = true }
        html.append("<li>\(inlineFormat(String(line.dropFirst(2))))</li>")
      } else if line.hasPrefix("|") {
        if inList { html.append("</ul>"); inList = false }
        // Skip table chrome in appendix — keep as paragraph.
        html.append("<p>\(inlineFormat(line))</p>")
      } else {
        if inList { html.append("</ul>"); inList = false }
        html.append("<p>\(inlineFormat(line))</p>")
      }
    }
    if inList { html.append("</ul>") }
    return html.joined(separator: "\n")
  }

  private static func inlineFormat(_ text: String) -> String {
    var s = escape(text)
    // **bold**
    while let r = s.range(of: #"\*\*([^*]+)\*\*"#, options: .regularExpression) {
      let inner = String(s[r]).dropFirst(2).dropLast(2)
      s.replaceSubrange(r, with: "<strong>\(inner)</strong>")
    }
    // `code`
    while let r = s.range(of: #"`([^`]+)`"#, options: .regularExpression) {
      let inner = String(s[r]).dropFirst().dropLast()
      s.replaceSubrange(r, with: "<code>\(inner)</code>")
    }
    return s
  }

  private static func normalizedVerdict(_ raw: String?) -> String? {
    guard let raw else { return nil }
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "Ready": return "Ready"
    case "Partial": return "Partial"
    default: return nil
    }
  }

  private static func fallbackCall(from markdown: String?) -> String? {
    guard let markdown else { return nil }
    let stripped = LeadCallParser.stripFence(from: markdown)
    let lines = stripped.components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { line in
        !line.isEmpty && !line.hasPrefix("```") && !line.hasPrefix("#")
          && !line.lowercased().hasPrefix("status:")
          && !line.lowercased().hasPrefix("i'm the lead")
          && !line.lowercased().hasPrefix("i am the lead")
      }
    guard !lines.isEmpty else { return nil }
    return lines.prefix(2).joined(separator: " ")
  }

  private static func elidedReproduce(command: String?, runId: String) -> (String?, String?) {
    guard let command, !command.isEmpty else { return (nil, nil) }
    if command.count <= 96 { return (command, nil) }
    return (String(command.prefix(96)) + "…", runId)
  }

  private static func firstSubstantiveLine(_ text: String?) -> String? {
    guard let text else { return nil }
    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed.hasPrefix("```") { continue }
      if trimmed.hasPrefix("{") || trimmed.hasPrefix("}") { continue }
      if trimmed.hasPrefix("\"") && trimmed.contains("\":") { continue }
      if trimmed.hasPrefix("|") { continue }
      if trimmed.hasPrefix("#") { continue }
      if trimmed.hasPrefix("**Status") || trimmed.lowercased().hasPrefix("status:") { continue }
      let lower = trimmed.lowercased()
      if lower.hasPrefix("i'll ") || lower.hasPrefix("i will ") { continue }
      if lower.hasPrefix("i'm the lead") || lower.hasPrefix("i am the lead") { continue }
      if lower.hasPrefix("reviewing ") { continue }
      if lower.contains("lead call") && trimmed.count < 80 { continue }
      return trimmed
        .replacingOccurrences(of: "**", with: "")
        .replacingOccurrences(of: "`", with: "")
    }
    return nil
  }

  private static func callRedundant(withTitle title: String, call: String) -> Bool {
    let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      .trimmingCharacters(in: CharacterSet(charactersIn: ".…"))
    let c = call.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      .trimmingCharacters(in: CharacterSet(charactersIn: ".…"))
    return c == t || c.hasPrefix(t) || t.hasPrefix(c)
  }

  private static func plainAsked(_ prompt: String) -> String {
    prompt
      .replacingOccurrences(of: #"#+\s*"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\*\*"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: "`", with: "")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func titleAtWordBoundary(_ text: String, max: Int) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > max else { return trimmed }
    let idx = trimmed.index(trimmed.startIndex, offsetBy: max)
    var cut = idx
    while cut > trimmed.startIndex, !trimmed[trimmed.index(before: cut)].isWhitespace {
      cut = trimmed.index(before: cut)
    }
    if cut == trimmed.startIndex { cut = idx }
    return String(trimmed[..<cut]).trimmingCharacters(in: .whitespaces) + "…"
  }

  private static func capped(_ text: String, max: Int) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > max else { return trimmed }
    return String(trimmed.prefix(max)) + "…"
  }

  private static func formatDuration(ms: Int) -> String {
    if ms >= 1000 { return String(format: "%.1fs", Double(ms) / 1000.0) }
    return "\(ms)ms"
  }

  private static func escape(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
