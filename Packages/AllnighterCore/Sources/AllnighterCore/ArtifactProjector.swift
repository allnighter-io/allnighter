import Foundation
import AgentOSTeam

/// Projects a terminal `TeamRun` into a private HTML team artifact (TRR-S01).
/// Pure and deterministic — no filesystem or run store.
///
/// Reading contract: Amazon one-pager / CEO memo — decision first, appendix last.
public enum ArtifactProjector {
  public static let honesty = "alln-attested multi-seat artifact · not vendor-signed"

  public struct Recommendation: Equatable, Sendable {
    public var decision: String
    public var lean: String
    public var why: String
  }

  public struct Seat: Equatable, Sendable {
    public var workerId: String
    public var displayName: String
    public var sourceId: String
    public var status: String
    public var durationMs: Int?
    public var oneLiner: String?
    /// Optional short body for click-to-expand (not the Floor).
    public var detailExcerpt: String?
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
    public var seats: [Seat]
    public var craftBody: String?
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
    context: Context = .init()
  ) -> Card {
    let trj = TeamRunJSONMapper.map(
      run, models: [], manifests: [],
      context: .init(runJournalPath: "")
    )
    let leadMarkdown = trj.answer?.markdown ?? run.plan
    let leadCall = LeadCallParser.parse(from: leadMarkdown)

    let teamLabel = run.teamDisplayName ?? run.presetId ?? "Team run"
    let verdict = normalizedVerdict(leadCall?.status)
    let call = leadCall?.call
      ?? fallbackCall(from: leadMarkdown)
      ?? "(no synthesized output — status \(run.status.rawValue))"
    let title = headlineTitle(call: call, teamLabel: teamLabel)
    let recommendations = (leadCall?.recommendations ?? [])
      .prefix(5)
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
    let seats = seatCards(for: run, hoistedAnswer: trj.answer, context: context)
    let craftBody = leadMarkdown.map { LeadCallParser.stripFence(from: $0) }
      .flatMap { $0.isEmpty ? nil : $0 }
      .map { shortenCraft($0) }

    let (reproduceLine, _) = elidedReproduce(
      command: reproduceCommand,
      runId: run.id
    )

    return Card(
      runId: run.id,
      title: capped(title, max: 140),
      asked: capped(run.prompt, max: 120),
      teamLabel: teamLabel,
      verdict: verdict,
      verdictPartial: verdict == "Partial",
      call: capped(call, max: 320),
      whyItMatters: whyItMatters.map { capped($0, max: 200) },
      recommendations: recommendations,
      nextMove: nextMove.map { capped($0, max: 200) },
      cta: cta,
      seats: seats,
      craftBody: craftBody,
      reproduceLine: reproduceLine,
      runIdLine: run.id,
      honesty: honesty
    )
  }

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
      <style>\(css)</style>
    </head>
    <body>
      <main class="artifact">
        \(body)
      </main>
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
    return seatWorkers.map { worker in
      let answer = run.workerAnswer(workerId: worker.id)
      let (status, durationMs) = resolvedSeatStatus(
        worker: worker,
        answer: answer,
        hoistedAnswer: hoistedAnswer
      )
      let sharesModel = (modelCounts[worker.modelId] ?? 0) > 1
      let display = worker.displayName(
        modelName: context.modelDisplayName(worker.modelId),
        sharesModel: sharesModel
      )
      let markdown = seatMarkdown(
        worker: worker, answer: answer, hoistedAnswer: hoistedAnswer
      )
      return Seat(
        workerId: worker.id,
        displayName: display,
        sourceId: context.sourceId(worker.modelId),
        status: status,
        durationMs: durationMs,
        oneLiner: seatOneLiner(from: markdown),
        detailExcerpt: seatDetailExcerpt(from: markdown),
        isLead: worker.purpose == .plan
      )
    }
  }

  /// Law-2 + trust: Lead chip must not stay `queued` when the synthesized answer exists.
  private static func resolvedSeatStatus(
    worker: Worker,
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
    worker: Worker,
    answer: TeamAnswer?,
    hoistedAnswer: TeamRunJSON.Answer?
  ) -> String? {
    var markdown = answer?.output
    if markdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
       hoistedAnswer?.source.workerId == worker.id {
      markdown = hoistedAnswer?.markdown
    }
    return markdown
  }

  private static func seatOneLiner(from markdown: String?) -> String? {
    guard let line = firstSubstantiveLine(markdown) else { return nil }
    return capped(line, max: 120)
  }

  private static func seatDetailExcerpt(from markdown: String?) -> String? {
    guard let markdown else { return nil }
    let stripped = LeadCallParser.stripFence(from: markdown)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard stripped.count > 140 else { return nil }
    return capped(stripped, max: 480)
  }

  // MARK: - HTML

  private static func htmlBody(_ card: Card) -> String {
    var parts: [String] = []
    parts.append("<header class=\"card-header\">")
    if let verdict = card.verdict {
      // Ready: calm ink. Partial: amber lives on Needs you (one accent-event), not the pill.
      let cls = card.verdictPartial ? "verdict verdict-partial" : "verdict verdict-ready"
      let label = card.verdictPartial ? "Needs you" : "Ready"
      parts.append("<div class=\"\(cls)\">\(escape(label))</div>")
    }
    parts.append("<div class=\"team-line\">\(escape(card.teamLabel))</div>")
    parts.append("<h1 class=\"title\">\(escape(card.title))</h1>")
    parts.append("<p class=\"asked\"><span class=\"asked-label\">Asked</span> \(escape(card.asked))</p>")
    parts.append("</header>")

    if card.verdictPartial {
      parts.append(needsYouHTML(card))
    }

    if let call = card.call, !call.isEmpty {
      parts.append(
        "<section class=\"call\"><h2>The decision</h2><p class=\"call-text\">\(escape(call))</p></section>"
      )
    }

    if let why = card.whyItMatters, !why.isEmpty {
      parts.append(
        "<section class=\"why\"><h2>Why it matters</h2><p>\(escape(why))</p></section>"
      )
    }

    if !card.recommendations.isEmpty {
      let heading = card.verdictPartial ? "Options for you" : "Do this next"
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

    parts.append("<section class=\"seats\"><h2>Who weighed in</h2><div class=\"seat-grid\">")
    for seat in card.seats {
      parts.append(seatChipHTML(seat))
    }
    parts.append("</div></section>")

    if let craft = card.craftBody, !craft.isEmpty {
      parts.append(
        "<section class=\"craft\">"
        + "<details><summary>Full notes (appendix)</summary>"
        + "<div class=\"craft-body\">\(renderSimpleMarkdown(craft))</div>"
        + "</details></section>"
      )
    }

    parts.append("<footer class=\"footer\">")
    parts.append("<div class=\"honesty\">\(escape(card.honesty))</div>")
    if let reproduce = card.reproduceLine, !reproduce.isEmpty {
      parts.append("<div class=\"reproduce\"><code>\(escape(reproduce))</code></div>")
    }
    parts.append("<div class=\"run-id\">Run \(escape(card.runIdLine))</div>")
    parts.append("</footer>")

    return parts.joined(separator: "\n")
  }

  private static func needsYouHTML(_ card: Card) -> String {
    var items = ""
    if card.recommendations.isEmpty {
      items = "<li>Reply with the decision you want locked — the team left this open.</li>"
    } else {
      for rec in card.recommendations.prefix(5) {
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
    let glyph = seat.sourceId.isEmpty
      ? String(seat.displayName.prefix(1)).uppercased()
      : String(seat.sourceId.prefix(1)).uppercased()
    let duration = seat.durationMs.map { formatDuration(ms: $0) } ?? ""
    let leadClass = seat.isLead ? " seat-lead" : ""
    let oneLiner = seat.oneLiner.map { "<div class=\"one-liner\">\(escape($0))</div>" } ?? ""
    let summary = """
      <div class="glyph">\(escape(glyph))</div>
      <div class="seat-main">
        <div class="seat-name">\(escape(seat.displayName))\(seat.isLead ? " <span class=\"lead-label\">Lead</span>" : "")</div>
        \(oneLiner)
      </div>
      <div class="seat-meta">
        <span class="status-dot status-\(escape(seat.status))" aria-label="\(escape(seat.status))"></span>
        <span class="duration">\(escape(duration))</span>
      </div>
    """
    if let detail = seat.detailExcerpt, !detail.isEmpty {
      return """
      <details class="seat-chip\(leadClass)" data-status="\(escape(seat.status))">
        <summary class="seat-summary">\(summary)</summary>
        <div class="seat-detail">\(escape(detail))</div>
      </details>
      """
    }
    return """
    <article class="seat-chip\(leadClass)" data-status="\(escape(seat.status))">
      <div class="seat-summary">\(summary)</div>
    </article>
    """
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
      --ink-900: #090B13;
      --amber-400: #FFC169;
      --amber-500: #FFA630;
      --green-500: #3FD18B;
      --red-500: #F76B6B;
      --blue-500: #5B9DFF;
      --yellow-500: #F5C84B;
      --bg-base: var(--ink-900);
      --bg-raised: var(--ink-750s);
      --text-primary: var(--ink-100);
      --text-secondary: var(--ink-200);
      --text-muted: var(--ink-300);
      --text-faint: var(--ink-400);
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
      --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.35);
      --container-reading: 680px;
      --space-2: 8px;
      --space-3: 12px;
      --space-4: 16px;
      --space-5: 20px;
      --space-6: 24px;
      --space-8: 32px;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg-base);
      color: var(--text-primary);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
      line-height: 1.45;
    }
    .artifact {
      max-width: var(--container-reading);
      margin: var(--space-6) auto;
      padding: var(--space-8) var(--space-5);
      background: var(--bg-raised);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      box-shadow: var(--shadow-sm);
    }
    h1, h2 { margin: 0 0 var(--space-3); font-weight: 600; }
    h1.title { font-size: 1.45rem; line-height: 1.25; letter-spacing: -0.02em; }
    h2 { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.06em; color: var(--text-muted); }
    .card-header { margin-bottom: var(--space-6); }
    .verdict {
      display: inline-block;
      padding: var(--space-2) var(--space-3);
      border-radius: 999px;
      border: 1px solid var(--border-default);
      font-size: 0.8rem;
      font-weight: 600;
      margin-bottom: var(--space-3);
    }
    .verdict-ready { color: var(--text-primary); background: transparent; }
    .verdict-partial {
      color: var(--accent-text);
      background: var(--accent-surface);
      border-color: var(--accent-border);
    }
    .team-line { color: var(--text-secondary); font-size: 0.9rem; margin-bottom: var(--space-2); }
    .asked { color: var(--text-muted); font-size: 0.85rem; margin: var(--space-3) 0 0; }
    .asked-label { text-transform: uppercase; letter-spacing: 0.05em; font-size: 0.7rem; margin-right: var(--space-2); }
    section { margin-bottom: var(--space-6); }
    .call-text { font-size: 1.15rem; margin: 0; line-height: 1.4; }
    .why p { margin: 0; color: var(--text-secondary); }
    .needs-you {
      border: 1px solid var(--accent-border);
      background: var(--accent-surface);
      border-radius: var(--radius-lg);
      padding: var(--space-4);
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
      background: var(--bg-base);
    }
    .cta-block.cta-partial {
      border-color: var(--accent-border);
      background: var(--accent-surface);
    }
    .cta-label { font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.06em; color: var(--text-muted); margin-bottom: var(--space-2); }
    .cta-text { margin: 0; font-size: 1.05rem; font-weight: 600; }
    .cta-detail { margin: var(--space-2) 0 0; color: var(--text-secondary); font-size: 0.9rem; }
    .seat-grid { display: flex; flex-direction: column; gap: var(--space-3); }
    .seat-chip {
      display: block;
      padding: var(--space-3);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      background: var(--bg-base);
    }
    .seat-summary {
      display: grid;
      grid-template-columns: auto 1fr auto;
      gap: var(--space-3);
      align-items: start;
      list-style: none;
    }
    details.seat-chip > summary.seat-summary { cursor: pointer; }
    .seat-summary::-webkit-details-marker { display: none; }
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
    .seat-name { font-size: 0.95rem; }
    .lead-label { color: var(--text-muted); font-size: 0.8rem; }
    .one-liner { color: var(--text-secondary); font-size: 0.85rem; margin-top: 2px; }
    .seat-meta { display: flex; align-items: center; gap: var(--space-2); }
    .seat-detail {
      margin-top: var(--space-3);
      padding-top: var(--space-3);
      border-top: 1px solid var(--border-subtle);
      color: var(--text-secondary);
      font-size: 0.85rem;
      white-space: pre-wrap;
    }
    .status-dot {
      width: 8px; height: 8px; border-radius: 999px;
      display: inline-block;
    }
    .status-queued { background: var(--status-queued); }
    .status-running { background: var(--status-running); }
    .status-done { background: var(--status-done); }
    .status-failed { background: var(--status-failed); }
    .status-timed_out { background: var(--status-timed_out); }
    .duration { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--text-faint); font-size: 0.8rem; }
    .craft details { border: 1px solid var(--border-subtle); border-radius: var(--radius-lg); padding: var(--space-3) var(--space-4); background: var(--bg-base); }
    .craft summary { cursor: pointer; color: var(--text-secondary); font-size: 0.9rem; }
    .craft-body {
      margin-top: var(--space-4);
      font-size: 0.9rem;
      color: var(--text-secondary);
    }
    .craft-body h3 { font-size: 0.95rem; color: var(--text-primary); margin: var(--space-4) 0 var(--space-2); text-transform: none; letter-spacing: 0; }
    .craft-body p { margin: 0 0 var(--space-3); }
    .craft-body ul, .craft-body ol { margin: 0 0 var(--space-3); padding-left: 1.2rem; }
    .craft-body code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.85em; }
    .footer {
      margin-top: var(--space-8);
      padding-top: var(--space-4);
      border-top: 1px solid var(--border-subtle);
      font-size: 0.8rem;
      color: var(--text-muted);
    }
    .reproduce code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    .run-id { margin-top: var(--space-2); color: var(--text-faint); }
    @media (max-width: 430px) {
      .artifact { margin: 0; padding: var(--space-5) var(--space-4); border-radius: 0; border-left: 0; border-right: 0; }
      .seat-summary { grid-template-columns: auto 1fr; }
      .seat-meta { grid-column: 2; }
      h1.title { font-size: 1.25rem; }
    }
    @media (min-width: 1280px) {
      .artifact { padding: var(--space-8) var(--space-6); margin: var(--space-8) auto; }
      h1.title { font-size: 1.6rem; }
    }
    """
  }

  // MARK: - Helpers

  private static func headlineTitle(call: String, teamLabel: String) -> String {
    let trimmed = call.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("(") { return "\(teamLabel) · result" }
    // Prefer first sentence; keep the period if present.
    if let dot = trimmed.firstIndex(of: "."), trimmed.distance(from: trimmed.startIndex, to: dot) < 140 {
      return String(trimmed[...dot]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let nl = trimmed.firstIndex(of: "\n") {
      return String(trimmed[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return trimmed
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
      if trimmed.lowercased().hasPrefix("i'll ") || trimmed.lowercased().hasPrefix("i will ") {
        continue
      }
      if trimmed.lowercased().hasPrefix("reviewing ") { continue }
      return trimmed
    }
    return nil
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
