import Foundation
import AllnighterCore
import AllnighterEngine

/// Shared Boost window read/write path for CLI and MCP (same JSON envelopes).
enum BoostWindowOperations {
    enum Failure: Error {
        case envelope(ErrorEnvelope)
    }

    static func projection(runtime: ToolRuntime, settings: BoostWindowSettings? = nil) -> BoostWindowSettingsJSON {
        let s = settings ?? persistence().load()
        return BoostWindowProjector.build(
            settings: s,
            providers: providerStates(settings: s, runtime: runtime),
            contractVersion: ContractRegistry.contractVersion
        )
    }

    static func update(
        runtime: ToolRuntime,
        enabled: Bool?,
        windowStart rawWindow: String?,
        appliesTo rawApplies: String?
    ) throws -> BoostWindowSettingsJSON {
        var s = persistence().load()
        if let on = enabled { s.enabled = on }
        if let raw = rawWindow { s.windowStart = try parseWindowStart(raw) }
        if let raw = rawApplies {
            s.appliesTo = raw.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        try save(s)
        return projection(runtime: runtime, settings: s)
    }

    static func seed(runtime: ToolRuntime, sourceId: String) async throws -> UtilizationSeedEvent {
        guard runtime.registry.manifest(id: sourceId) != nil else {
            throw Failure.envelope(utilizationError("UTILIZATION_SOURCE_NOT_FOUND", "unknown source: \(sourceId)"))
        }
        let settings = persistence().load()
        guard settings.appliesToSet.contains(sourceId) else {
            throw Failure.envelope(utilizationError("UTILIZATION_SOURCE_UNCONFIGURED", "\(sourceId) is not in appliesTo"))
        }
        let executor = UtilizationSeedExecutor(
            models: runtime.models,
            registry: runtime.registry,
            commandRunner: SubprocessCommandRunner(),
            invocations: runtime.invocations
        )
        let event = await executor.execute(sourceId: sourceId, settings: settings, force: true)
        switch event.outcome {
        case .authRequired:
            throw Failure.envelope(utilizationError("UTILIZATION_AUTH_REQUIRED", event.rawSnippet ?? "auth required"))
        case .billingPrompt:
            throw Failure.envelope(utilizationError("UTILIZATION_BILLING_PROMPT", event.rawSnippet ?? "billing prompt"))
        default:
            return event
        }
    }

    static func clearObservations(sourceId: String?) throws -> UtilizationObservationsClearJSON {
        try UtilizationSeedLedger().clear(sourceId: sourceId)
        return UtilizationObservationsClearJSON(cleared: true, sourceId: sourceId)
    }

    static func parseWindowStart(_ raw: String) throws -> Int {
        if let minutes = Int(raw), (0..<1440).contains(minutes) {
            return BoostWindowTiming.snap15(minutes)
        }
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else {
            throw Failure.envelope(utilizationError(
                "CLI_USAGE_ERROR",
                "--window-start must be HH:MM or minutes-from-midnight (got: \(raw))"
            ))
        }
        return BoostWindowTiming.snap15(h * 60 + m)
    }

    private static func persistence() -> BoostWindowSettingsPersistence { BoostWindowSettingsPersistence() }

    private static func save(_ s: BoostWindowSettings) throws {
        do { try persistence().save(s) }
        catch { throw Failure.envelope(utilizationError("INTERNAL_ERROR", "\(error)")) }
    }

    private static func providerStates(settings: BoostWindowSettings, runtime: ToolRuntime) -> [ProviderBoostState] {
        let ready = Set(runtime.readyModels.map(\.driverId))
        let records = SetupStore().load().records
        let resets = UtilizationCapacityReader.lastObservedResetPerSource()
        let outcomes = UtilizationCapacityReader.recentSeedOutcomes()
        return BoostWindowProviderBuilder.providerStates(
            settings: settings,
            manifests: runtime.registry.all,
            models: runtime.models,
            readyDriverIds: ready,
            probeRecords: records,
            observedResets: resets,
            recentSeedOutcomes: outcomes
        )
    }

    private static func utilizationError(_ code: String, _ message: String) -> ErrorEnvelope {
        let spec = ContractRegistry.milestone1.errors.first { $0.code == code }
        return ErrorEnvelope(
            code: code,
            message: message,
            requiresManual: spec?.requiresManual ?? true,
            retryable: spec?.retryable ?? false
        )
    }
}
