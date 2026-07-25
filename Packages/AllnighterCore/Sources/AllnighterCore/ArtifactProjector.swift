import Foundation
import AgentOSTeam

/// Projects a terminal `TeamRun` into a private HTML team artifact (TRR-S01).
/// Pure and deterministic — no filesystem or run store.
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
    public var isLead: Bool
  }

  public struct Card: Equatable, Sendable {
    public var runId: String
    public var question: String
    public var teamLabel: String
    public var verdict: String?
    public var verdictPartial: Bool
    public var call: String?
    public var changed: String?
    public var recommendations: [Recommendation]
    public var seats: [Seat]
    public var craftBody: String?
    public var reproduceLine: String?
    public var reproduceRunIdLine: String?
    public var honesty: String
  }

  public struct Context {
    public var modelDisplayName: (String) -> String
    public var sourceId: (String) -> String

    public init(
      models: [Model] = [],
      manifests: [DriverManifest] = []
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
    let call = leadCall?.call ?? fallbackCall(from: leadMarkdown)
    let recommendations = (leadCall?.recommendations ?? [])
      .prefix(3)
      .compactMap { rec -> Recommendation? in
        guard let decision = rec.decision, !decision.isEmpty else { return nil }
        return Recommendation(
          decision: decision,
          lean: rec.lean ?? "",
          why: rec.why ?? ""
        )
      }

    let seats = seatCards(for: run, hoistedAnswer: trj.answer, context: context)
    let craftBody = leadMarkdown.map { LeadCallParser.stripFence(from: $0) }
      .flatMap { $0.isEmpty ? nil : $0 }

  let (reproduceLine, reproduceRunIdLine) = elidedReproduce(
      command: reproduceCommand,
      runId: run.id
    )

    return Card(
      runId: run.id,
      question: capped(run.prompt, max: 120),
      teamLabel: teamLabel,
      verdict: verdict,
      verdictPartial: verdict == "Partial",
      call: call.map { capped($0, max: 280) },
      changed: leadCall?.changed,
      recommendations: recommendations,
      seats: seats,
      craftBody: craftBody,
      reproduceLine: reproduceLine,
      reproduceRunIdLine: reproduceRunIdLine,
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
      <title>Team artifact · \(escape(card.runId))</title>
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
    let amberEvents = header.components(separatedBy: "verdict-partial").count - 1
      + header.components(separatedBy: "accent-event").count - 1
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
      let status = answer?.result.status.rawValue ?? "queued"
      let sharesModel = (modelCounts[worker.modelId] ?? 0) > 1
      let display = worker.displayName(
        modelName: context.modelDisplayName(worker.modelId),
        sharesModel: sharesModel
      )
      return Seat(
        workerId: worker.id,
        displayName: display,
        sourceId: context.sourceId(worker.modelId),
        status: status,
        durationMs: answer?.result.timing.durationMs,
        oneLiner: seatOneLiner(
          worker: worker,
          answer: answer,
          hoistedAnswer: hoistedAnswer
        ),
        isLead: worker.purpose == .plan
      )
    }
  }

  private static func seatOneLiner(
    worker: Worker,
    answer: TeamAnswer?,
    hoistedAnswer: TeamRunJSON.Answer?
  ) -> String? {
    var markdown = answer?.output
    if markdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
       hoistedAnswer?.source.workerId == worker.id {
      markdown = hoistedAnswer?.markdown
    }
    guard let line = firstLine(markdown) else { return nil }
    return capped(line, max: 120)
  }

  // MARK: - HTML

  private static func htmlBody(_ card: Card) -> String {
    var parts: [String] = []
    parts.append("<header class=\"card-header\">")
    if let verdict = card.verdict {
      let cls = card.verdictPartial ? "verdict verdict-partial accent-event" : "verdict verdict-ready"
      let label = card.verdictPartial ? "Partial · needs you" : verdict
      parts.append("<div class=\"\(cls)\">\(escape(label))</div>")
    }
    parts.append("<div class=\"team-line\">\(escape(card.teamLabel))</div>")
    parts.append("<h1 class=\"question\">\(escape(card.question))</h1>")
    parts.append("</header>")

    if let call = card.call, !call.isEmpty {
      parts.append("<section class=\"call\"><h2>The call</h2><p>\(escape(call))</p></section>")
    }
    if let changed = card.changed, !changed.isEmpty {
      parts.append("<section class=\"changed\"><h2>What changed</h2><p>\(escape(changed))</p></section>")
    }
    if !card.recommendations.isEmpty {
      parts.append("<section class=\"recommendations\"><h2>Recommendations</h2><ul>")
      for rec in card.recommendations {
        parts.append(
          "<li><strong>\(escape(rec.decision))</strong> — \(escape(rec.lean))"
          + (rec.why.isEmpty ? "" : " <span class=\"muted\">(\(escape(rec.why)))</span>")
          + "</li>"
        )
      }
      parts.append("</ul></section>")
    }

    parts.append("<section class=\"seats\"><h2>Seats</h2><div class=\"seat-grid\">")
    for seat in card.seats {
      parts.append(seatChipHTML(seat))
    }
    parts.append("</div></section>")

    if let craft = card.craftBody, !craft.isEmpty {
      parts.append(
        "<section class=\"craft\"><h2>Craft body</h2>"
        + "<div class=\"craft-body\">\(escape(craft))</div></section>"
      )
    }

    parts.append("<footer class=\"footer\">")
    parts.append("<div class=\"honesty\">\(escape(card.honesty))</div>")
    if let reproduce = card.reproduceLine, !reproduce.isEmpty {
      parts.append("<div class=\"reproduce\"><code>\(escape(reproduce))</code></div>")
    }
    if let runLine = card.reproduceRunIdLine {
      parts.append("<div class=\"run-micro\">\(escape(runLine))</div>")
    }
    parts.append("<div class=\"run-id\">\(escape(card.runId))</div>")
    parts.append("</footer>")

    return parts.joined(separator: "\n")
  }

  private static func seatChipHTML(_ seat: Seat) -> String {
    let glyph = seat.sourceId.isEmpty
      ? String(seat.displayName.prefix(1)).uppercased()
      : String(seat.sourceId.prefix(1)).uppercased()
    let duration = seat.durationMs.map { formatDuration(ms: $0) } ?? ""
    let leadClass = seat.isLead ? " seat-lead" : ""
    let oneLiner = seat.oneLiner.map { "<div class=\"one-liner\">\(escape($0))</div>" } ?? ""
    return """
    <article class="seat-chip\(leadClass)" data-status="\(escape(seat.status))">
      <div class="glyph">\(escape(glyph))</div>
      <div class="seat-main">
        <div class="seat-name">\(escape(seat.displayName))\(seat.isLead ? " <span class=\"lead-label\">Lead</span>" : "")</div>
        \(oneLiner)
      </div>
      <div class="seat-meta">
        <span class="status-dot status-\(escape(seat.status))" aria-label="\(escape(seat.status))"></span>
        <span class="duration">\(escape(duration))</span>
      </div>
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
      margin: 0 auto;
      padding: var(--space-8) var(--space-5);
      background: var(--bg-raised);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      box-shadow: var(--shadow-sm);
    }
    h1, h2 { margin: 0 0 var(--space-3); font-weight: 600; }
    h1.question { font-size: 1.25rem; }
    h2 { font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); }
    .card-header { margin-bottom: var(--space-6); }
    .verdict {
      display: inline-block;
      padding: var(--space-2) var(--space-3);
      border-radius: var(--radius-lg);
      border: 1px solid var(--border-default);
      font-size: 0.9rem;
      margin-bottom: var(--space-3);
    }
    .verdict-ready { color: var(--text-primary); background: transparent; }
    .verdict-partial {
      color: var(--accent-text);
      background: var(--accent-surface);
      border-color: var(--accent-border);
    }
    .team-line { color: var(--text-secondary); font-size: 0.95rem; margin-bottom: var(--space-2); }
    section { margin-bottom: var(--space-6); }
    .call p, .changed p { font-size: 1.05rem; margin: 0; }
    .recommendations ul { margin: 0; padding-left: 1.2rem; }
    .recommendations li { margin-bottom: var(--space-2); }
    .muted { color: var(--text-muted); }
    .seat-grid { display: flex; flex-direction: column; gap: var(--space-3); }
    .seat-chip {
      display: grid;
      grid-template-columns: auto 1fr auto;
      gap: var(--space-3);
      align-items: start;
      padding: var(--space-3);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      background: var(--bg-base);
    }
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
    .craft-body {
      white-space: pre-wrap;
      font-size: 0.9rem;
      color: var(--text-secondary);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      padding: var(--space-4);
      background: var(--bg-base);
      overflow-x: auto;
    }
    .footer {
      margin-top: var(--space-8);
      padding-top: var(--space-4);
      border-top: 1px solid var(--border-subtle);
      font-size: 0.8rem;
      color: var(--text-muted);
    }
    .reproduce code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    .run-micro, .run-id { margin-top: var(--space-2); color: var(--text-faint); }
    @media (max-width: 430px) {
      .artifact { padding: var(--space-5) var(--space-4); border-radius: 0; border-left: 0; border-right: 0; }
      .seat-chip { grid-template-columns: auto 1fr; }
      .seat-meta { grid-column: 2; }
    }
    @media (min-width: 1280px) {
      .artifact { padding: var(--space-8) var(--space-6); }
      h1.question { font-size: 1.35rem; }
    }
    """
  }

  // MARK: - Helpers

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
      }
    guard !lines.isEmpty else { return nil }
    return lines.prefix(2).joined(separator: " ")
  }

  private static func elidedReproduce(command: String?, runId: String) -> (String?, String?) {
    guard let command, !command.isEmpty else { return (nil, nil) }
    if command.count <= 96 { return (command, nil) }
    return (String(command.prefix(96)) + "…", runId)
  }

  private static func firstLine(_ text: String?) -> String? {
    guard let text else { return nil }
    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty { return trimmed }
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
