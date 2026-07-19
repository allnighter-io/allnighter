import Foundation
import AllnighterCore

/// Reads sourced reset observations for Boost window calibration.
public enum UtilizationCapacityReader {
  public static let lookbackSeconds: TimeInterval = 12 * 60 * 60

  public static func observations(
    from runStore: RunStore,
    since: Date,
    now: Date = Date()
  ) -> [CapacityObservation] {
    runStore.list().flatMap { run in
      let observations = run.failedWorkerAnswers.compactMap {
        $0.result.capacityObservation
      } + run.attempts.compactMap(\.capacityObservation)
      guard run.createdAt < since else { return observations }
      // Weekly/monthly cooldown truth outlives the 12-hour run-origin lookback.
      return observations.filter { ($0.wakeAfter ?? $0.observedResetAt).map { $0 > now } == true }
    }
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
    let all = observations(from: runStore, since: since, now: now) + observations(from: seedLedger)
    var map: [String: Date] = [:]
    for obs in all {
      guard let reset = obs.wakeAfter ?? obs.observedResetAt else { continue }
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
