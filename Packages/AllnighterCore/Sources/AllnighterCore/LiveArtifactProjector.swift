import Foundation
import AgentOSTeam

/// Maps live `RunEvent`s into a seat snapshot for Mac artifact preview (TRR-S01c).
/// Settled artifacts still use `ArtifactProjector` — this path is live-only.
public enum LiveArtifactProjector {
  public struct SeatState: Equatable, Sendable {
    public var workerId: String
    public var displayName: String
    public var sourceId: String
    public var status: String
    public var startedAt: Date?
    public var durationMs: Int?
    public var oneLiner: String?
    public var isLead: Bool
  }

  public struct State: Equatable, Sendable {
    public var runId: String
    public var question: String
    public var teamLabel: String
    fileprivate var seats: [String: SeatState]
    fileprivate var seatOrder: [String]

    public var seatList: [SeatState] {
      seatOrder.compactMap { seats[$0] }
    }
  }

  public static func bootstrap(
    runId: String,
    question: String,
    teamLabel: String
  ) -> State {
    State(
      runId: runId,
      question: capped(question, max: 120),
      teamLabel: teamLabel,
      seats: [:],
      seatOrder: []
    )
  }

  public static func seed(
    run: TeamRun,
    context: ArtifactProjector.Context = .init()
  ) -> State {
    let teamLabel = run.teamDisplayName ?? run.presetId ?? "Team run"
    let seatWorkers = TeamRunSeatSet.workers(for: run)
    let modelCounts = Dictionary(grouping: seatWorkers, by: \.modelId).mapValues(\.count)
    var seats: [String: SeatState] = [:]
    var order: [String] = []
    for worker in seatWorkers {
      let answer = run.workerAnswer(workerId: worker.id)
      let status = answer?.result.status.rawValue ?? WorkerAnswerStatus.queued.rawValue
      let sharesModel = (modelCounts[worker.modelId] ?? 0) > 1
      let display = worker.displayName(
        modelName: context.modelDisplayName(worker.modelId),
        sharesModel: sharesModel
      )
      seats[worker.id] = SeatState(
        workerId: worker.id,
        displayName: display,
        sourceId: context.sourceId(worker.modelId),
        status: status,
        startedAt: answer?.result.timing.startedAt,
        durationMs: answer?.result.timing.durationMs,
        oneLiner: oneLiner(from: answer?.output),
        isLead: worker.purpose == .plan
      )
      order.append(worker.id)
    }
    return State(
      runId: run.id,
      question: capped(run.prompt, max: 120),
      teamLabel: teamLabel,
      seats: seats,
      seatOrder: order
    )
  }

  /// Applies board events (`worker.status_changed`, `worker.answer_delta`). Returns true when
  /// the state changed. Unknown kinds are ignored — never invent RunEvent kinds here.
  public static func apply(_ event: RunEvent, to state: inout State) -> Bool {
    switch event.kind {
    case RunEventKind.workerStatusChanged:
      guard let workerId = event.payload["workerId"]?.stringValue,
            let to = event.payload["to"]?.stringValue else { return false }
      guard var seat = state.seats[workerId] else { return false }
      seat.status = to
      if to == WorkerAnswerStatus.running.rawValue {
        seat.startedAt = event.ts
      }
      if case .int(let ms) = event.payload["durationMs"] {
        seat.durationMs = ms
      }
      state.seats[workerId] = seat
      return true
    case RunEventKind.workerAnswerDelta:
      guard let workerId = event.payload["workerId"]?.stringValue,
            let text = event.payload["text"]?.stringValue else { return false }
      guard var seat = state.seats[workerId] else { return false }
      seat.oneLiner = oneLiner(from: text)
      state.seats[workerId] = seat
      return true
    default:
      return false
    }
  }

  // MARK: - Helpers

  private static func oneLiner(from text: String?) -> String? {
    guard let line = firstLine(text) else { return nil }
    return capped(line, max: 120)
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
}
