import Foundation

/// Quit-time teaching for background features the Dock app does not own.
/// Pure evaluation — AppKit presents; this type never shows UI.
///
/// Capacity refresh lives in `alln serve` — do not teach "leave the app open
/// for capacity." Boost needs the Mac awake at seed time (`alln serve`), not
/// the app — do not teach "leave the app open for Boost."
public struct QuitBackgroundReminder: Equatable, Sendable {
    public let bullets: [String]

    public init(bullets: [String]) {
        self.bullets = bullets
    }

    /// Returns a reminder when Boost is ON and the user has not suppressed the
    /// sheet. Empty / irrelevant → `nil` (quit immediately).
    public static func evaluate(
        boostEnabled: Bool,
        boostWindowStart: Int,
        suppressed: Bool
    ) -> QuitBackgroundReminder? {
        guard !suppressed else { return nil }
        var bullets: [String] = []
        if boostEnabled {
            let seed = BoostWindowTiming.seedFiresAt(boostWindowStart)
            let time = BoostWindowTiming.formatMinutes(seed)
            bullets.append(
                "Boost is on — seed at \(time) needs the Mac awake (sleep skips it)."
            )
        }
        guard !bullets.isEmpty else { return nil }
        return QuitBackgroundReminder(bullets: bullets)
    }

    public var informativeText: String {
        bullets.map { "• \($0)" }.joined(separator: "\n")
    }
}

/// Persists "Don't show again" for the quit background reminder.
/// Missing file → not suppressed.
public struct QuitBackgroundReminderPersistence: Sendable {
    private struct File: Codable {
        var suppressed: Bool
    }

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AllnighterSupportRoot.config
            .appendingPathComponent("quit_background_reminder.json")
    }

    public func loadSuppressed() -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            try? data.write(to: fileURL.appendingPathExtension("corrupt"), options: .atomic)
            return false
        }
        return file.suppressed
    }

    public func saveSuppressed(_ suppressed: Bool) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(File(suppressed: suppressed)).write(to: fileURL, options: .atomic)
    }
}
