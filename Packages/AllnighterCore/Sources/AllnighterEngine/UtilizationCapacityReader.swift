import Foundation
import AllnighterCore

/// Reads sourced reset observations for Boost window calibration.
public enum UtilizationCapacityReader {
  public static let lookbackSeconds: TimeInterval = 12 * 60 * 60

  public static func observations(from runStore: RunStore, since: Date) -> [CapacityObservation] {
    runStore.list()
      .filter { $0.createdAt >= since }
      .flatMap(\.failedWorkerAnswers)
      .compactMap(\.capacityObservation)
  }

  public static func observations(from seedLedger: UtilizationSeedLedger) -> [CapacityObservation] {
    seedLedger.load().compactMap(\.capacityObservation)
  }

  public static func lastObservedResetPerSource(
    runStore: RunStore = RunStore(),
    seedLedger: UtilizationSeedLedger = UtilizationSeedLedger(),
    now: Date = Date()
  ) -> [String: Date] {
    let since = now.addingTimeInterval(-lookbackSeconds)
    let all = observations(from: runStore, since: since) + observations(from: seedLedger)
    var map: [String: Date] = [:]
    for obs in all {
      guard let reset = obs.observedResetAt ?? obs.wakeAfter else { continue }
      let key = normalizeSource(obs.source)
      if map[key] == nil || reset > map[key]! { map[key] = reset }
    }
    return map
  }

  public static func recentSeedOutcomes(
    seedLedger: UtilizationSeedLedger = UtilizationSeedLedger(),
    calendar: Calendar = .current,
    now: Date = Date()
  ) -> [String: UtilizationSeedOutcome] {
    var map: [String: UtilizationSeedOutcome] = [:]
    for event in seedLedger.load() where calendar.isDate(event.startedAt, inSameDayAs: now) {
      map[event.sourceId] = event.outcome
    }
    return map
  }

  private static func normalizeSource(_ source: String) -> String {
    source.replacingOccurrences(of: "-", with: "_")
  }
}
