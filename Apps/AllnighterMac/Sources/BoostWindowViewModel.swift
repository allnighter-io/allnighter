import SwiftUI
import AllnighterCore
import AllnighterEngine

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
    private var eligibleSeedDriverIds: Set<String> = []

    func load(
        drivers: [(id: String, name: String)],
        readyDrivers: Set<String>,
        probeKinds: [String: ModelSetupStatus.Kind],
        observedResets: [String: Date] = [:],
        recentSeedOutcomes: [String: UtilizationSeedOutcome] = [:],
        eligibleSeedDriverIds: Set<String> = []
    ) {
        self.driverCatalog = drivers
        self.readyDrivers = readyDrivers
        self.probeByDriver = probeKinds
        self.observedResets = observedResets
        self.recentSeedOutcomes = recentSeedOutcomes
        self.eligibleSeedDriverIds = eligibleSeedDriverIds
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
        let eligible = eligibleSeedDriverIds.isEmpty
            ? Set(driverCatalog.map(\.id))
            : eligibleSeedDriverIds
        let nameById = Dictionary(uniqueKeysWithValues: driverCatalog.map { ($0.id, $0.name) })
        let providers: [ProviderBoostState] = BoostSeatCatalog.seats.compactMap { seat in
            guard eligible.contains(seat.seedDriverId) else { return nil }
            let kind = probeByDriver[seat.seedDriverId]
            let needsAttention: Bool = {
                if kind == .installedNotSignedIn { return true }
                if let outcome = recentSeedOutcomes[seat.seedDriverId],
                   outcome == .authRequired || outcome == .billingPrompt { return true }
                return false
            }()
            return ProviderBoostState(
                id: seat.seedDriverId,
                displayName: nameById[seat.seedDriverId] ?? seat.seedDriverId,
                connected: readyDrivers.contains(seat.seedDriverId) || kind != nil,
                signedIn: readyDrivers.contains(seat.seedDriverId),
                included: settings.appliesToSet.contains(seat.seedDriverId),
                lastObservedReset: observedResets[seat.seedDriverId],
                needsAttention: needsAttention
            )
        }
        projection = BoostWindowProjector.build(
            settings: settings,
            providers: providers,
            contractVersion: ContractRegistry.contractVersion
        )
        let displayNames = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.displayName) })
        let activeApplies = settings.appliesTo.filter { eligible.contains($0) }
        let events = seedLedger.load()
        let seedMinutes = BoostWindowTiming.seedFiresAt(settings.windowStart)
        latestReceipt = BoostSeedScheduleProjector.latestReceipt(
            events: events,
            enabled: settings.enabled,
            appliesTo: activeApplies,
            seedMinutes: seedMinutes,
            displayNames: displayNames
        )
        scheduleHistory = BoostSeedScheduleProjector.history(
            events: events,
            enabled: settings.enabled,
            appliesTo: activeApplies,
            seedMinutes: seedMinutes,
            displayNames: displayNames
        )
    }
}
