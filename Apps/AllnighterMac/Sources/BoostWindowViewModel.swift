import SwiftUI
import AllnighterCore

@Observable
@MainActor
final class BoostWindowViewModel {
    private(set) var projection: BoostWindowSettingsJSON =
        BoostWindowProjector.build(settings: .fresh, providers: [], contractVersion: ContractRegistry.contractVersion)
    private(set) var latestReceipt: BoostSeedReceipt?
    private(set) var scheduleHistory: [BoostSeedHistoryEntry] = []

    private let persistence = BoostWindowSettingsPersistence()
    private let seedLedger = UtilizationSeedLedger()
    private var driverCatalog: [(id: String, name: String)] = []
    private var readyDrivers: Set<String> = []
    private var probeByDriver: [String: ModelSetupStatus.Kind] = [:]
    private var observedResets: [String: Date] = [:]
    private var recentSeedOutcomes: [String: UtilizationSeedOutcome] = [:]

    func load(
        drivers: [(id: String, name: String)],
        readyDrivers: Set<String>,
        probeKinds: [String: ModelSetupStatus.Kind],
        observedResets: [String: Date] = [:],
        recentSeedOutcomes: [String: UtilizationSeedOutcome] = [:]
    ) {
        self.driverCatalog = drivers
        self.readyDrivers = readyDrivers
        self.probeByDriver = probeKinds
        self.observedResets = observedResets
        self.recentSeedOutcomes = recentSeedOutcomes
        reproject()
    }

    var displayState: BoostWindowDisplayState {
        BoostWindowDisplayState(rawValue: projection.displayState) ?? .off
    }

    var windowStart: Int { projection.windowStart }
    var seedAt: Int { projection.derivedSeedAt }
    var resetMid: Int { projection.derivedResetMid }

    func setEnabled(_ on: Bool) { mutate { $0.enabled = on } }
    func setWindowStart(_ minutes: Int) { mutate { $0.windowStart = BoostWindowTiming.snap15(minutes) } }
    func toggleProvider(_ id: String) {
        mutate { s in
            var set = s.appliesToSet
            if set.contains(id) { set.remove(id) } else { set.insert(id) }
            s.appliesTo = Array(set).sorted()
        }
    }

    private func mutate(_ change: (inout BoostWindowSettings) -> Void) {
        var s = persistence.load()
        change(&s)
        try? persistence.save(s)
        project(from: s)
    }

    private func reproject() { project(from: persistence.load()) }

    private func project(from settings: BoostWindowSettings) {
        let providers = driverCatalog.map { entry in
            let kind = probeByDriver[entry.id]
            let needsAttention: Bool = {
                if kind == .installedNotSignedIn { return true }
                if let outcome = recentSeedOutcomes[entry.id],
                   outcome == .authRequired || outcome == .billingPrompt { return true }
                return false
            }()
            return ProviderBoostState(
                id: entry.id,
                displayName: entry.name,
                connected: readyDrivers.contains(entry.id) || kind != nil,
                signedIn: readyDrivers.contains(entry.id),
                included: settings.appliesToSet.contains(entry.id),
                lastObservedReset: observedResets[entry.id],
                needsAttention: needsAttention
            )
        }
        projection = BoostWindowProjector.build(
            settings: settings,
            providers: providers,
            contractVersion: ContractRegistry.contractVersion
        )
        let displayNames = Dictionary(uniqueKeysWithValues: driverCatalog.map { ($0.id, $0.name) })
        let events = seedLedger.load()
        let seedMinutes = BoostWindowTiming.seedFiresAt(settings.windowStart)
        latestReceipt = BoostSeedScheduleProjector.latestReceipt(
            events: events,
            enabled: settings.enabled,
            appliesTo: settings.appliesTo,
            seedMinutes: seedMinutes,
            displayNames: displayNames
        )
        scheduleHistory = BoostSeedScheduleProjector.history(
            events: events,
            enabled: settings.enabled,
            appliesTo: settings.appliesTo,
            seedMinutes: seedMinutes,
            displayNames: displayNames
        )
    }
}
