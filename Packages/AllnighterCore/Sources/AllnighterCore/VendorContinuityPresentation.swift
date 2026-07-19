import Foundation

/// Truthful owner-facing copy for a durable vendor park.
///
/// The source id and wake instant are observed run facts. A missing wake instant
/// always takes the retry-soon path; this formatter never invents a clock.
public enum VendorContinuityPresentation {
    public static func vendorDisplayName(
        sourceId: String,
        sourceDisplayName: String? = nil
    ) -> String {
        switch sourceId {
        case "claude_code": return "Claude"
        case "codex": return "Codex"
        case "grok": return "Grok"
        case "cursor_agent": return "Cursor"
        case "agy", "antigravity": return "Antigravity"
        case "gemini", "gemini_cli": return "Gemini"
        case "aider": return "Aider"
        default:
            let source = sourceDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let source, !source.isEmpty {
                return source
                    .replacingOccurrences(of: " Build CLI", with: "")
                    .replacingOccurrences(of: " CLI", with: "")
                    .replacingOccurrences(of: " Code", with: "")
            }
            return sourceId
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    public static func waitStatus(
        vendorDisplayName: String,
        wakeAfter: Date?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        guard let wakeAfter else {
            return "Waiting for \(vendorDisplayName) — will retry soon"
        }
        let time = localTime(wakeAfter, locale: locale, timeZone: timeZone)
        return "Waiting for \(vendorDisplayName) — resumes around \(time)"
    }

    public static func parkNotification(
        vendorDisplayName: String,
        wakeAfter: Date?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        guard let wakeAfter else {
            return "\(vendorDisplayName) paused. Allnighter will retry soon."
        }
        let time = localTime(wakeAfter, locale: locale, timeZone: timeZone)
        return "\(vendorDisplayName) paused until ~\(time). No action needed."
    }

    public static func recoveryNotification(
        vendorDisplayName: String,
        resumedAt: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let time = localTime(resumedAt, locale: locale, timeZone: timeZone)
        return "\(vendorDisplayName) resumed at \(time)."
    }

    public static func localTime(
        _ date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Local receipt derived only from persisted attempt timestamps and resume origin.
public struct MorningReceipt: Codable, Sendable, Equatable {
    public static let automaticResumeOrigin = "vendorWake.automatic"
    public static let manualResumeOrigin = "vendorWake.manual"

    public var schemaVersion: Int
    public var since: Date
    public var until: Date
    public var vendorWaitSecondsCovered: Int
    public var resumedRunCount: Int
    public var runsResumedWithoutIntervention: Int
    public var completedRunsAfterAutomaticResume: Int

    public init(
        schemaVersion: Int = 1,
        since: Date,
        until: Date,
        vendorWaitSecondsCovered: Int,
        resumedRunCount: Int,
        runsResumedWithoutIntervention: Int,
        completedRunsAfterAutomaticResume: Int
    ) {
        self.schemaVersion = schemaVersion
        self.since = since
        self.until = until
        self.vendorWaitSecondsCovered = vendorWaitSecondsCovered
        self.resumedRunCount = resumedRunCount
        self.runsResumedWithoutIntervention = runsResumedWithoutIntervention
        self.completedRunsAfterAutomaticResume = completedRunsAfterAutomaticResume
    }

    public static func project(
        runs: [TeamRun],
        since: Date,
        until: Date
    ) -> MorningReceipt {
        var waitSeconds = 0
        var resumedRunIds = Set<String>()
        var automaticRunIds = Set<String>()
        var completedAutomaticRunIds = Set<String>()

        for run in runs {
            let attempts = run.attempts.sorted { $0.attemptNumber < $1.attemptNumber }
            guard attempts.count > 1 else { continue }
            for index in 0..<(attempts.count - 1) {
                let parked = attempts[index]
                let resumed = attempts[index + 1]
                guard parked.capacityObservation != nil,
                      let parkedAt = parked.endedAt,
                      resumed.startedAt >= since,
                      resumed.startedAt <= until else { continue }

                waitSeconds += max(0, Int(resumed.startedAt.timeIntervalSince(parkedAt)))
                resumedRunIds.insert(run.id)
                if resumed.selectionOrigin == automaticResumeOrigin {
                    automaticRunIds.insert(run.id)
                    if run.status == .complete || run.status == .done {
                        completedAutomaticRunIds.insert(run.id)
                    }
                }
            }
        }

        return MorningReceipt(
            since: since,
            until: until,
            vendorWaitSecondsCovered: waitSeconds,
            resumedRunCount: resumedRunIds.count,
            runsResumedWithoutIntervention: automaticRunIds.count,
            completedRunsAfterAutomaticResume: completedAutomaticRunIds.count
        )
    }

    public var humanSummary: String {
        let wait = Self.durationString(seconds: vendorWaitSecondsCovered)
        let runs = runsResumedWithoutIntervention == 1 ? "run" : "runs"
        return "Allnighter covered \(wait) of vendor waiting. \(runsResumedWithoutIntervention) \(runs) resumed without intervention."
    }

    private static func durationString(seconds: Int) -> String {
        let seconds = max(0, seconds)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }
}
