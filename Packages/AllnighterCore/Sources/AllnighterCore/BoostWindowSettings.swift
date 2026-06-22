import Foundation

/// Rolling-bucket window placement for utilization seeding (Boost window).
/// SSOT for Settings, CLI, and `alln serve` scheduling.
public struct BoostWindowSettings: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let defaultWindowStart = 8 * 60   // 08:00
    public static let snapMinutes = 15
    public static let windowLengthMinutes = 300     // 5h
    public static let halfWindowMinutes = 150       // auto-centered reset offset

    public var schemaVersion: Int
    public var enabled: Bool
    /// Minutes from midnight, snapped to 15.
    public var windowStart: Int
    /// Driver ids (e.g. `claude_code`, `codex`) the window covers.
    public var appliesTo: [String]
    public var updatedAt: Date?

    public init(
        schemaVersion: Int = BoostWindowSettings.currentSchemaVersion,
        enabled: Bool = false,
        windowStart: Int = BoostWindowSettings.defaultWindowStart,
        appliesTo: [String] = ["claude_code", "codex"],
        updatedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.enabled = enabled
        self.windowStart = BoostWindowTiming.snap15(windowStart)
        self.appliesTo = appliesTo
        self.updatedAt = updatedAt
    }

    public static let fresh = BoostWindowSettings()

    public var appliesToSet: Set<String> { Set(appliesTo) }

    public mutating func normalize() {
        windowStart = BoostWindowTiming.snap15(windowStart)
        appliesTo = Array(Set(appliesTo)).sorted()
    }
}

/// Derived timing from `windowStart` (minutes-from-midnight, mod 1440).
public enum BoostWindowTiming {
    public static func resetMid(_ windowStart: Int) -> Int {
        mod1440(windowStart + BoostWindowSettings.halfWindowMinutes)
    }

    public static func seedFiresAt(_ windowStart: Int) -> Int {
        mod1440(windowStart - BoostWindowSettings.halfWindowMinutes)
    }

    public static func windowEnd(_ windowStart: Int) -> Int {
        mod1440(windowStart + BoostWindowSettings.windowLengthMinutes)
    }

    public static func snap15(_ minutes: Int) -> Int {
        let clamped = max(0, min(1439, minutes))
        return Int((Double(clamped) / Double(BoostWindowSettings.snapMinutes)).rounded())
            * BoostWindowSettings.snapMinutes % 1440
    }

    public static func mod1440(_ minutes: Int) -> Int {
        let m = minutes % 1440
        return m < 0 ? m + 1440 : m
    }

    /// Seed falls in the overnight quiet band (22:00-06:00) — calm copy, not a guarantee.
    public static func seedIsOvernightIdle(_ seedMinutes: Int) -> Bool {
        seedMinutes >= 22 * 60 || seedMinutes < 6 * 60
    }

    public static func formatMinutes(_ minutes: Int) -> String {
        let m = mod1440(minutes)
        let h = m / 60
        let min = m % 60
        let period: String
        let hour12: Int
        switch h {
        case 0: period = "AM"; hour12 = 12
        case 12: period = "PM"; hour12 = 12
        case 1..<12: period = "AM"; hour12 = h
        default: period = "PM"; hour12 = h - 12
        }
        if min == 0 {
            return "\(hour12)\(period.lowercased())"
        }
        return String(format: "%d:%02d %@", hour12, min, period)
    }

    public static func formatWindowRange(start: Int) -> String {
        "\(formatMinutes(start))-\(formatMinutes(windowEnd(start)))"
    }
}

public enum BoostWindowDisplayState: String, Codable, Sendable {
    case off
    case calibrated
    case estimated
    case noQuietRunUp
    case needsYou
}

public struct ProviderBoostState: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public var connected: Bool
    public var signedIn: Bool
    public var included: Bool
    public var lastObservedReset: Date?
    public var needsAttention: Bool

    public init(
        id: String,
        displayName: String,
        connected: Bool,
        signedIn: Bool,
        included: Bool,
        lastObservedReset: Date? = nil,
        needsAttention: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.connected = connected
        self.signedIn = signedIn
        self.included = included
        self.lastObservedReset = lastObservedReset
        self.needsAttention = needsAttention
    }
}

/// Persists `BoostWindowSettings` to `Config/boost_window_settings.json`.
public struct BoostWindowSettingsPersistence: Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? BoostWindowSettingsPersistence.defaultFileURL
    }

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Allnighter/Config/boost_window_settings.json")
    }

    public func load() -> BoostWindowSettings {
        guard let data = try? Data(contentsOf: fileURL) else { return .fresh }
        guard var settings = try? CoreJSON.decode(BoostWindowSettings.self, from: data) else {
            let backup = fileURL.appendingPathExtension("corrupt")
            try? data.write(to: backup, options: .atomic)
            FileHandle.standardError.write(Data(
                "warning: \(fileURL.lastPathComponent) is unreadable; backed up to \(backup.lastPathComponent), using defaults\n".utf8))
            return .fresh
        }
        settings.normalize()
        return settings
    }

    public func save(_ settings: BoostWindowSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var settings = settings
        settings.normalize()
        settings.updatedAt = Date()
        try CoreJSON.encode(settings).write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public func reset() throws -> BoostWindowSettings {
        try save(.fresh)
        return load()
    }
}

public enum UtilizationSeedOutcome: String, Codable, Sendable {
    case succeeded, skipped, authRequired, billingPrompt, rateLimited
    case providerRejected, unsupported, failed, noQuietRunUp
}

public struct UtilizationSeedEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourceId: String
    public var scheduledAt: Date?
    public var startedAt: Date
    public var finishedAt: Date?
    public var outcome: UtilizationSeedOutcome
    public var rawSnippet: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        sourceId: String,
        scheduledAt: Date? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        outcome: UtilizationSeedOutcome,
        rawSnippet: String? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.scheduledAt = scheduledAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.rawSnippet = rawSnippet
    }
}

public struct UtilizationSeedLedger: Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.fileURL = fileURL ?? base.appendingPathComponent("Allnighter/Config/utilization_seed_events.json")
    }

    public func load() -> [UtilizationSeedEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let events = try? CoreJSON.decode([UtilizationSeedEvent].self, from: data) else { return [] }
        return events
    }

    public func append(_ event: UtilizationSeedEvent) throws {
        var events = load()
        events.append(event)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try CoreJSON.encode(events).write(to: fileURL, options: .atomic)
    }

    public func clear(sourceId: String? = nil) throws {
        if let sourceId {
            let kept = load().filter { $0.sourceId != sourceId }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try CoreJSON.encode(kept).write(to: fileURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    public func lastEvent(for sourceId: String, on localDay: Date, calendar: Calendar = .current) -> UtilizationSeedEvent? {
        load().filter { $0.sourceId == sourceId && calendar.isDate($0.startedAt, inSameDayAs: localDay) }
            .max(by: { $0.startedAt < $1.startedAt })
    }
}
