import Foundation

/// Visual tone for Boost seed receipt / history rows (maps to status-done /
/// status-failed / muted ink in the Mac UI).
public enum BoostSeedReceiptTone: String, Codable, Sendable, Equatable {
    case success
    case failure
    case neutral
}

/// Latest seed outcome under the plan soft-note (setting above, receipt below).
public struct BoostSeedReceipt: Equatable, Sendable {
    public var tone: BoostSeedReceiptTone
    public var headline: String
    public var detail: String?

    public init(tone: BoostSeedReceiptTone, headline: String, detail: String? = nil) {
        self.tone = tone
        self.headline = headline
        self.detail = detail
    }
}

/// One day in the Boost schedule history list.
public struct BoostSeedHistoryEntry: Equatable, Sendable, Identifiable {
    public var id: String
    public var sortDate: Date
    public var tone: BoostSeedReceiptTone
    public var title: String
    public var detail: String

    public init(
        id: String,
        sortDate: Date,
        tone: BoostSeedReceiptTone,
        title: String,
        detail: String
    ) {
        self.id = id
        self.sortDate = sortDate
        self.tone = tone
        self.title = title
        self.detail = detail
    }
}

/// Projects ledger events (+ honest today-miss) into receipt and history.
/// Never invents "Mac was asleep" — absence is "no seed recorded."
public enum BoostSeedScheduleProjector {
    public static let defaultHistoryDays = 14

    public static func latestReceipt(
        events: [UtilizationSeedEvent],
        enabled: Bool,
        appliesTo: [String],
        seedMinutes: Int,
        displayNames: [String: String] = [:],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BoostSeedReceipt? {
        let sources = normalizedSources(appliesTo)
        if let miss = todayMissIfNeeded(
            events: events,
            enabled: enabled,
            sources: sources,
            seedMinutes: seedMinutes,
            displayNames: displayNames,
            now: now,
            calendar: calendar
        ) {
            return BoostSeedReceipt(
                tone: miss.tone,
                headline: miss.title,
                detail: miss.detail
            )
        }

        guard let day = mostRecentSeedDay(
            events: events, sources: sources, now: now, calendar: calendar
        ) else {
            guard enabled else { return nil }
            return BoostSeedReceipt(
                tone: .neutral,
                headline: "No seed recorded yet",
                detail: "History appears after the first scheduled seed."
            )
        }

        let summary = daySummary(
            dayStart: day,
            events: eventsOnDay(events, dayStart: day, calendar: calendar),
            sources: sources,
            displayNames: displayNames,
            calendar: calendar,
            headlinePrefix: "Last seed"
        )
        return BoostSeedReceipt(
            tone: summary.tone,
            headline: summary.title,
            detail: summary.detail
        )
    }

    public static func history(
        events: [UtilizationSeedEvent],
        enabled: Bool,
        appliesTo: [String],
        seedMinutes: Int,
        displayNames: [String: String] = [:],
        dayCount: Int = defaultHistoryDays,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [BoostSeedHistoryEntry] {
        let sources = normalizedSources(appliesTo)
        var entries: [BoostSeedHistoryEntry] = []

        if let miss = todayMissIfNeeded(
            events: events,
            enabled: enabled,
            sources: sources,
            seedMinutes: seedMinutes,
            displayNames: displayNames,
            now: now,
            calendar: calendar
        ) {
            entries.append(miss)
        }

        let start = calendar.startOfDay(for: now)
        guard let earliest = calendar.date(byAdding: .day, value: -(max(1, dayCount) - 1), to: start) else {
            return entries
        }

        // Event-backed days only (plus today's miss above). No invented past "asleep."
        var dayCursor = start
        while dayCursor >= earliest {
            if calendar.isDate(dayCursor, inSameDayAs: now),
               entries.contains(where: { calendar.isDate($0.sortDate, inSameDayAs: now) }) {
                // already have today's miss
            } else {
                let dayEvents = eventsOnDay(events, dayStart: dayCursor, calendar: calendar)
                    .filter { sources.isEmpty || sources.contains($0.sourceId) }
                if !dayEvents.isEmpty {
                    let summary = daySummary(
                        dayStart: dayCursor,
                        events: dayEvents,
                        sources: sources,
                        displayNames: displayNames,
                        calendar: calendar,
                        headlinePrefix: nil
                    )
                    entries.append(summary)
                }
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: dayCursor) else { break }
            dayCursor = prev
        }

        return entries.sorted { $0.sortDate > $1.sortDate }
    }

    // MARK: - Internals

    private static func normalizedSources(_ appliesTo: [String]) -> [String] {
        Array(Set(appliesTo)).sorted()
    }

    private static func todayMissIfNeeded(
        events: [UtilizationSeedEvent],
        enabled: Bool,
        sources: [String],
        seedMinutes: Int,
        displayNames: [String: String],
        now: Date,
        calendar: Calendar
    ) -> BoostSeedHistoryEntry? {
        guard enabled else { return nil }
        let dayStart = calendar.startOfDay(for: now)
        let seedDate = date(on: dayStart, minutesFromMidnight: seedMinutes, calendar: calendar)
        guard now >= seedDate else { return nil }
        let todayEvents = eventsOnDay(events, dayStart: dayStart, calendar: calendar)
            .filter { sources.isEmpty || sources.contains($0.sourceId) }
        guard todayEvents.isEmpty else { return nil }

        let detail: String
        if sources.isEmpty {
            detail = "No seed recorded"
        } else {
            detail = sources.map { source in
                "\(displayName(source, displayNames)) — no seed recorded"
            }.joined(separator: " · ")
        }
        return BoostSeedHistoryEntry(
            id: "miss-\(dayKey(dayStart, calendar: calendar))",
            sortDate: seedDate,
            tone: .failure,
            title: "No seed recorded this morning",
            detail: detail
        )
    }

    private static func mostRecentSeedDay(
        events: [UtilizationSeedEvent],
        sources: [String],
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let filtered = events.filter { sources.isEmpty || sources.contains($0.sourceId) }
        guard let latest = filtered.max(by: { $0.startedAt < $1.startedAt }) else { return nil }
        return calendar.startOfDay(for: latest.startedAt)
    }

    private static func eventsOnDay(
        _ events: [UtilizationSeedEvent],
        dayStart: Date,
        calendar: Calendar
    ) -> [UtilizationSeedEvent] {
        events.filter { calendar.isDate($0.startedAt, inSameDayAs: dayStart) }
    }

    private static func daySummary(
        dayStart: Date,
        events: [UtilizationSeedEvent],
        sources: [String],
        displayNames: [String: String],
        calendar: Calendar,
        headlinePrefix: String?
    ) -> BoostSeedHistoryEntry {
        let bySource = latestPerSource(events)
        let orderedSources: [String]
        if sources.isEmpty {
            orderedSources = bySource.keys.sorted()
        } else {
            orderedSources = sources
        }

        var parts: [String] = []
        var tones: [BoostSeedReceiptTone] = []
        for source in orderedSources {
            if let event = bySource[source] {
                parts.append("\(displayName(source, displayNames)) — \(outcomeLabel(event.outcome))")
                tones.append(tone(for: event.outcome))
            } else if !sources.isEmpty {
                parts.append("\(displayName(source, displayNames)) — no seed recorded")
                tones.append(.failure)
            }
        }

        let rollup = rollupTone(tones)
        let clock = events.compactMap { event -> String? in
            let mins = minutesFromMidnight(event.startedAt, calendar: calendar)
            return BoostWindowTiming.formatMinutes(mins)
        }.first ?? BoostWindowTiming.formatMinutes(0)

        let title: String
        if let headlinePrefix {
            switch rollup {
            case .success:
                title = "\(headlinePrefix) succeeded · \(clock)"
            case .failure:
                title = "\(headlinePrefix) had problems · \(clock)"
            case .neutral:
                title = "\(headlinePrefix) · \(clock)"
            }
        } else {
            let dayLabel = dayTitle(dayStart, calendar: calendar)
            switch rollup {
            case .success:
                title = "\(dayLabel) · seeded"
            case .failure:
                title = "\(dayLabel) · problems"
            case .neutral:
                title = "\(dayLabel) · seeded"
            }
        }

        return BoostSeedHistoryEntry(
            id: "day-\(dayKey(dayStart, calendar: calendar))",
            sortDate: dayStart.addingTimeInterval(TimeInterval(minutesFromMidnight(
                events.map(\.startedAt).max() ?? dayStart, calendar: calendar
            ) * 60)),
            tone: rollup,
            title: title,
            detail: parts.joined(separator: " · ")
        )
    }

    private static func latestPerSource(
        _ events: [UtilizationSeedEvent]
    ) -> [String: UtilizationSeedEvent] {
        var map: [String: UtilizationSeedEvent] = [:]
        for event in events.sorted(by: { $0.startedAt < $1.startedAt }) {
            map[event.sourceId] = event
        }
        return map
    }

    private static func tone(for outcome: UtilizationSeedOutcome) -> BoostSeedReceiptTone {
        switch outcome {
        case .succeeded:
            return .success
        case .skipped, .noQuietRunUp:
            return .neutral
        case .authRequired, .billingPrompt, .rateLimited,
             .providerRejected, .unsupported, .failed:
            return .failure
        }
    }

    private static func rollupTone(_ tones: [BoostSeedReceiptTone]) -> BoostSeedReceiptTone {
        if tones.contains(.failure) { return .failure }
        if tones.contains(.success) { return .success }
        return .neutral
    }

    public static func outcomeLabel(_ outcome: UtilizationSeedOutcome) -> String {
        switch outcome {
        case .succeeded: return "ready"
        case .skipped: return "already ran"
        case .authRequired: return "needs sign-in"
        case .billingPrompt: return "billing prompt"
        case .rateLimited: return "rate-limited"
        case .providerRejected: return "provider rejected"
        case .unsupported: return "unsupported"
        case .failed: return "failed"
        case .noQuietRunUp: return "no quiet run-up"
        }
    }

    private static func displayName(_ sourceId: String, _ names: [String: String]) -> String {
        if let name = names[sourceId], !name.isEmpty { return name }
        switch sourceId {
        case "claude_code": return "Claude Code"
        case "codex": return "Codex"
        default: return sourceId
        }
    }

    private static func dayKey(_ dayStart: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: dayStart)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func dayTitle(_ dayStart: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: dayStart)
    }

    private static func minutesFromMidnight(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static func date(on day: Date, minutesFromMidnight: Int, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = minutesFromMidnight / 60
        comps.minute = minutesFromMidnight % 60
        comps.second = 0
        return calendar.date(from: comps) ?? day
    }
}
