import Foundation
import AllnighterCore

/// Resident loop: fire utilization seeds at `SEED_FIRES_AT` for enabled sources.
public struct BoostSeedScheduler: Sendable {
    public var settingsPersistence: BoostWindowSettingsPersistence
    public var seedLedger: UtilizationSeedLedger
    public var registry: DriverRegistry
    public var now: @Sendable () -> Date
    public var calendar: Calendar
    public var sleeper: any PendingWakeSleeper

    public init(
        settingsPersistence: BoostWindowSettingsPersistence = BoostWindowSettingsPersistence(),
        seedLedger: UtilizationSeedLedger = UtilizationSeedLedger(),
        registry: DriverRegistry,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current,
        sleeper: any PendingWakeSleeper = DefaultPendingWakeSleeper()
    ) {
        self.settingsPersistence = settingsPersistence
        self.seedLedger = seedLedger
        self.registry = registry
        self.now = now
        self.calendar = calendar
        self.sleeper = sleeper
    }

    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        while !isCancelled() {
            let settings = settingsPersistence.load()
            if settings.enabled, let next = nextSeedDate(settings: settings) {
                if next <= now() {
                    await fireDueSeeds(settings: settings)
                } else {
                    do { try await sleeper.sleep(until: next, jitterSeconds: 0) } catch { break }
                    continue
                }
            }
            do { try await sleeper.sleep(until: now().addingTimeInterval(60), jitterSeconds: 0) } catch { break }
        }
    }

    public func nextSeedDate(settings: BoostWindowSettings) -> Date? {
        guard settings.enabled, !settings.appliesTo.isEmpty else { return nil }
        let seedMinutes = BoostWindowTiming.seedFiresAt(settings.windowStart)
        return date(on: now(), minutesFromMidnight: seedMinutes)
    }

    private func fireDueSeeds(settings: BoostWindowSettings) async {
        let current = now()
        let seedMinutes = BoostWindowTiming.seedFiresAt(settings.windowStart)
        guard calendar.isDate(current, equalTo: date(on: current, minutesFromMidnight: seedMinutes), toGranularity: .minute) else {
            return
        }
        for sourceId in settings.appliesTo where settings.appliesToSet.contains(sourceId) {
            if seedLedger.lastEvent(for: sourceId, on: current, calendar: calendar) != nil { continue }
            guard registry.manifest(id: sourceId) != nil else { continue }
            if !BoostWindowTiming.seedIsOvernightIdle(seedMinutes) {
                let event = UtilizationSeedEvent(
                    sourceId: sourceId,
                    scheduledAt: date(on: current, minutesFromMidnight: seedMinutes),
                    startedAt: current,
                    finishedAt: current,
                    outcome: .noQuietRunUp
                )
                try? seedLedger.append(event)
                continue
            }
            let event = UtilizationSeedEvent(
                sourceId: sourceId,
                scheduledAt: date(on: current, minutesFromMidnight: seedMinutes),
                startedAt: current,
                finishedAt: current,
                outcome: .skipped,
                rawSnippet: "seed scheduled; driver execution not yet wired"
            )
            try? seedLedger.append(event)
        }
    }

    private func date(on day: Date, minutesFromMidnight: Int) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = minutesFromMidnight / 60
        comps.minute = minutesFromMidnight % 60
        comps.second = 0
        return calendar.date(from: comps) ?? day
    }
}
