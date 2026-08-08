import Foundation

public struct BoostWindowSettingsJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var enabled: Bool
    public var windowStart: Int
    public var appliesTo: [String]
    public var derivedSeedAt: Int
    public var derivedResetMid: Int
    public var derivedWindowEnd: Int
    public var displayState: String
    public var quietRunUp: Bool
    public var bucketHeadline: String
    public var providers: [ProviderBoostStateJSON]
}

public struct ProviderBoostStateJSON: Codable, Sendable, Equatable {
    public var sourceId: String
    public var displayName: String
    public var connected: Bool
    public var signedIn: Bool
    public var included: Bool
    public var lastObservedReset: String?
    public var needsAttention: Bool
    public var blockers: [String]
}

public struct UtilizationObservationsClearJSON: Codable, Sendable, Equatable {
    public var cleared: Bool
    public var sourceId: String?

    public init(cleared: Bool = true, sourceId: String? = nil) {
        self.cleared = cleared
        self.sourceId = sourceId
    }
}

public enum BoostWindowProjector {
    public static func build(
        settings: BoostWindowSettings,
        providers: [ProviderBoostState],
        contractVersion: String
    ) -> BoostWindowSettingsJSON {
        let seedAt = BoostWindowTiming.seedFiresAt(settings.windowStart)
        let quiet = BoostWindowTiming.seedIsOvernightIdle(seedAt)
        let display = displayState(settings: settings, providers: providers, quietRunUp: quiet)
        let buckets = bucketHeadline(display: display)
        return BoostWindowSettingsJSON(
            schemaVersion: settings.schemaVersion,
            contractVersion: contractVersion,
            enabled: settings.enabled,
            windowStart: settings.windowStart,
            appliesTo: settings.appliesTo,
            derivedSeedAt: seedAt,
            derivedResetMid: BoostWindowTiming.resetMid(settings.windowStart),
            derivedWindowEnd: BoostWindowTiming.windowEnd(settings.windowStart),
            displayState: display.rawValue,
            quietRunUp: quiet,
            bucketHeadline: buckets,
            providers: providers.map(projectProvider)
        )
    }

    public static func displayState(
        settings: BoostWindowSettings,
        providers: [ProviderBoostState],
        quietRunUp: Bool
    ) -> BoostWindowDisplayState {
        guard settings.enabled else { return .off }
        let included = providers.filter(\.included)
        if included.contains(where: \.needsAttention) { return .needsYou }
        if !quietRunUp { return .noQuietRunUp }
        if included.isEmpty { return .estimated }
        if included.allSatisfy({ $0.lastObservedReset != nil }) { return .calibrated }
        return .estimated
    }

    private static func bucketHeadline(display: BoostWindowDisplayState) -> String {
        switch display {
        case .off, .noQuietRunUp: return "1 -> 1"
        case .calibrated, .estimated, .needsYou: return "1 -> 2"
        }
    }

    private static func projectProvider(_ p: ProviderBoostState) -> ProviderBoostStateJSON {
        let iso = ISO8601DateFormatter()
        var blockers: [String] = []
        if !p.connected { blockers.append("not_configured") }
        if p.connected && !p.signedIn { blockers.append("sign_in_required") }
        if p.needsAttention { blockers.append("needs_attention") }
        return ProviderBoostStateJSON(
            sourceId: p.id,
            displayName: p.displayName,
            connected: p.connected,
            signedIn: p.signedIn,
            included: p.included,
            lastObservedReset: p.lastObservedReset.map { iso.string(from: $0) },
            needsAttention: p.needsAttention,
            blockers: blockers
        )
    }
}

/// Shared provider-row builder for Settings, CLI, and MCP.
///
/// Chips = capacity-eligible seats from `BoostSeatCatalog` (not a hard id list).
public enum BoostWindowProviderBuilder {
    public static func providerStates(
        settings: BoostWindowSettings,
        manifests: [DriverManifest],
        models: [Model],
        readyDriverIds: Set<String>,
        probeRecords: [ToolProbeRecord],
        observedResets: [String: Date] = [:],
        recentSeedOutcomes: [String: UtilizationSeedOutcome] = [:],
        eligibleSeedDriverIds: Set<String>
    ) -> [ProviderBoostState] {
        let byId = Dictionary(uniqueKeysWithValues: manifests.map { ($0.id, $0) })
        return BoostSeatCatalog.seats.compactMap { seat in
            guard eligibleSeedDriverIds.contains(seat.seedDriverId) else { return nil }
            let manifest = byId[seat.seedDriverId]
            let rec = probeRecords.first { $0.driverId == seat.seedDriverId }
            let needsAttention: Bool = {
                if case .installedNotSignedIn = rec?.status { return true }
                if let outcome = recentSeedOutcomes[seat.seedDriverId],
                   outcome == .authRequired || outcome == .billingPrompt { return true }
                return false
            }()
            return ProviderBoostState(
                id: seat.seedDriverId,
                displayName: manifest?.displayName ?? seat.seedDriverId,
                connected: readyDriverIds.contains(seat.seedDriverId) || rec != nil || manifest != nil,
                signedIn: readyDriverIds.contains(seat.seedDriverId),
                included: settings.appliesToSet.contains(seat.seedDriverId),
                lastObservedReset: observedResets[seat.seedDriverId],
                needsAttention: needsAttention
            )
        }
    }
}
