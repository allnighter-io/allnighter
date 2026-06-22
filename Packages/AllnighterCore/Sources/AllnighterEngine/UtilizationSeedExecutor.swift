import Foundation
import AllnighterCore

/// Runs one utilization seed through the same WorkerRunner path as real work (probe scratch, health==runs invocation).
public struct UtilizationSeedExecutor: Sendable {
  public var models: [Model]
  public var registry: DriverRegistry
  public var commandRunner: CommandRunner
  public var invocations: [String: ToolInvocation]
  public var seedLedger: UtilizationSeedLedger
  public var now: @Sendable () -> Date
  public var calendar: Calendar

  public init(
    models: [Model],
    registry: DriverRegistry,
    commandRunner: CommandRunner,
    invocations: [String: ToolInvocation] = [:],
    seedLedger: UtilizationSeedLedger = UtilizationSeedLedger(),
    now: @escaping @Sendable () -> Date = Date.init,
    calendar: Calendar = .current
  ) {
    self.models = models
    self.registry = registry
    self.commandRunner = commandRunner
    self.invocations = invocations
    self.seedLedger = seedLedger
    self.now = now
    self.calendar = calendar
  }

  public func execute(
    sourceId: String,
    settings: BoostWindowSettings,
    force: Bool = false,
    scheduledAt: Date? = nil
  ) async -> UtilizationSeedEvent {
    let startedAt = now()
    if !force, seedLedger.lastEvent(for: sourceId, on: startedAt, calendar: calendar) != nil {
      return finish(
        sourceId: sourceId,
        scheduledAt: scheduledAt,
        startedAt: startedAt,
        outcome: .skipped,
        rawSnippet: "already ran today"
      )
    }

    let seedMinutes = BoostWindowTiming.seedFiresAt(settings.windowStart)
    if !force, !BoostWindowTiming.seedIsOvernightIdle(seedMinutes) {
      return finish(
        sourceId: sourceId,
        scheduledAt: scheduledAt,
        startedAt: startedAt,
        outcome: .noQuietRunUp
      )
    }

    guard let manifest = registry.manifest(id: sourceId) else {
      return finish(sourceId: sourceId, scheduledAt: scheduledAt, startedAt: startedAt, outcome: .unsupported)
    }
    guard let worker = models.first(where: { $0.driverId == sourceId && $0.enabled }) else {
      return finish(sourceId: sourceId, scheduledAt: scheduledAt, startedAt: startedAt, outcome: .unsupported,
                    rawSnippet: "no enabled model for source")
    }

    let runner = WorkerRunner(commandRunner: commandRunner, invocations: invocations, now: now)
    let run = await runner.invoke(
      worker: worker,
      manifest: manifest,
      prompt: UtilizationSeedPrompt.text,
      effort: .low,
      workingDirectoryOverride: AllnighterPaths.ensuredProbeScratchPath(),
      timeoutOverride: .seconds(min(manifest.invoke?.timeoutSeconds ?? 120, 120))
    )

    let outcome = mapOutcome(run)
    let snippet = run.capacityObservation?.rawSnippet
      ?? run.output.map { String($0.prefix(240)) }
      ?? run.errorReason
    let event = finish(
      sourceId: sourceId,
      scheduledAt: scheduledAt,
      startedAt: startedAt,
      outcome: outcome,
      rawSnippet: snippet,
      capacityObservation: run.capacityObservation
    )
    try? seedLedger.append(event)
    return event
  }

  private func finish(
    sourceId: String,
    scheduledAt: Date?,
    startedAt: Date,
    outcome: UtilizationSeedOutcome,
    rawSnippet: String? = nil,
    capacityObservation: CapacityObservation? = nil
  ) -> UtilizationSeedEvent {
    UtilizationSeedEvent(
      sourceId: sourceId,
      scheduledAt: scheduledAt,
      startedAt: startedAt,
      finishedAt: now(),
      outcome: outcome,
      rawSnippet: rawSnippet,
      capacityObservation: capacityObservation
    )
  }

  private func mapOutcome(_ run: WorkerRunOutcome) -> UtilizationSeedOutcome {
    if let obs = run.capacityObservation {
      switch obs.kind {
      case .authRequired:
        let lower = obs.rawSnippet.lowercased()
        if lower.contains("billing") || lower.contains("credit") || lower.contains("payment") {
          return .billingPrompt
        }
        return .authRequired
      case .manualRequired:
        return .billingPrompt
      case .accountRateLimit, .providerBusy, .cooldown:
        return .rateLimited
      case .unknownCapacity:
        return .providerRejected
      }
    }
    switch run.status {
    case .done: return .succeeded
    case .skipped: return .unsupported
    default: return .failed
    }
  }
}
