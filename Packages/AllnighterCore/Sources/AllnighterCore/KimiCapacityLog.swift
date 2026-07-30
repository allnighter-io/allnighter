import Foundation

/// Limit window duration kind for Kimi Code plan usage.
public enum KimiWindowKind: String, Sendable, Equatable, CaseIterable {
    case weekly
    case fiveHour
}

/// One capacity limit window (e.g., Weekly limit or 5h limit) for Kimi Code.
///
/// Semantics:
/// - Kimi displays plan quota in terms of percentage USED (e.g., `100% used`, `0% used`).
/// - `usedPercent` is the percentage used (0…100+).
/// - `remainingPercent` is normalized remaining capacity percentage (100.0 - usedPercent).
/// - `resetAt` is calculated as `observedAt + resetDuration`.
public struct KimiCapacityWindow: Sendable, Equatable {
    public let kind: KimiWindowKind
    /// Percentage of quota used (0…100+).
    public let usedPercent: Double
    /// Normalized remaining capacity percentage (100.0 - usedPercent).
    public let remainingPercent: Double
    /// Wall clock time when the render was captured.
    public let observedAt: Date
    /// Computed absolute reset time (`observedAt + resetDuration`).
    public let resetAt: Date

    public init(
        kind: KimiWindowKind,
        usedPercent: Double,
        observedAt: Date,
        resetAt: Date
    ) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.remainingPercent = max(0.0, 100.0 - usedPercent)
        self.observedAt = observedAt
        self.resetAt = resetAt
    }

    /// Normalize into the shared `CapacityWindow` surface.
    ///
    /// Kimi is used-polarity; relative duration → minute precision; TUI probe tier.
    public func asCapacityWindow() -> CapacityWindow {
        let scope: CapacityWindowScope
        switch kind {
        case .weekly: scope = .weekly
        case .fiveHour: scope = .fiveHour
        }
        return CapacityWindow(
            used: usedPercent,
            source: "kimi",
            scope: scope,
            resetAt: resetAt,
            resetPrecision: .minute,
            observedAt: observedAt,
            sourceTier: .tuiProbe
        )
    }
}

/// Parsed snapshot of Kimi Code plan usage capacity.
public struct KimiPlanCapacity: Sendable, Equatable {
    /// Session ID if parsed from `/status` header, or nil.
    public let sessionId: String?
    /// Model name if parsed from `/status` header, or nil.
    public let model: String?
    /// Extracted plan capacity windows (e.g. weekly, fiveHour).
    public let windows: [KimiCapacityWindow]

    public init(
        sessionId: String? = nil,
        model: String? = nil,
        windows: [KimiCapacityWindow]
    ) {
        self.sessionId = sessionId
        self.model = model
        self.windows = windows
    }

    /// Normalize every plan window into shared `CapacityWindow` values.
    public func asCapacityWindows() -> [CapacityWindow] {
        windows.map { $0.asCapacityWindow() }
    }
}

/// Extractor for Kimi Code TUI `/usage` and `/status` renders.
/// Pure parser — fail closed. Never throws, never calls `Date()`.
public enum KimiCapacityLog {

    /// Parse then normalize plan windows into shared `CapacityWindow` values.
    /// Returns `[]` when the render yields no valid windows (same fail-closed rule as parse).
    public static func capacityWindows(fromRender renderText: String, observedAt: Date) -> [CapacityWindow] {
        parseWindows(fromRender: renderText, observedAt: observedAt).map { $0.asCapacityWindow() }
    }

    /// Parses plan capacity windows and metadata from raw `/usage` or `/status` render text.
    ///
    /// - Parameters:
    ///   - renderText: Raw text output captured from `kimi` TUI (`/usage` or `/status`).
    ///   - observedAt: Caller-provided timestamp for the capture.
    /// - Returns: `KimiPlanCapacity` containing parsed windows and optional metadata, or nil if no valid windows found.
    public static func parsePlanCapacity(fromRender renderText: String, observedAt: Date) -> KimiPlanCapacity? {
        let cleanText = stripANSI(renderText)
        let rawLines = cleanText.components(separatedBy: .newlines)
        
        let sessionId = extractHeaderValue(from: rawLines, key: "Session")
            ?? extractHeaderValue(from: rawLines, key: "Session ID")
            ?? extractHeaderValue(from: rawLines, key: "Session id")
        let model = extractHeaderValue(from: rawLines, key: "Model")
        
        let windows = parseWindows(fromRender: renderText, observedAt: observedAt)
        guard !windows.isEmpty else { return nil }
        
        return KimiPlanCapacity(
            sessionId: sessionId,
            model: model,
            windows: windows
        )
    }

    /// Parses capacity windows directly from raw `/usage` or `/status` render text.
    ///
    /// - Parameters:
    ///   - renderText: Raw text output captured from `kimi` TUI (`/usage` or `/status`).
    ///   - observedAt: Caller-provided timestamp for the capture.
    /// - Returns: Array of parsed `KimiCapacityWindow` structs.
    public static func parseWindows(fromRender renderText: String, observedAt: Date) -> [KimiCapacityWindow] {
        let cleanText = stripANSI(renderText)
        let lines = cleanText.components(separatedBy: .newlines)
        
        var windows: [KimiCapacityWindow] = []
        var inPlanUsageSection = false
        
        for line in lines {
            let cleaned = cleanFrame(line)
            if cleaned.isEmpty { continue }
            
            let lower = cleaned.lowercased()
            
            // Section tracking
            if lower.contains("plan usage") {
                inPlanUsageSection = true
                continue
            } else if lower.contains("session usage") || lower.contains("context window") {
                inPlanUsageSection = false
                continue
            }
            
            // BANNED: Context window lines must NEVER be emitted as capacity windows
            if lower.contains("context") || lower.contains("(0 /") || lower.contains("/ 1m)") {
                continue
            }
            
            // Parse window line
            guard let kind = parseWindowKind(from: cleaned) else { continue }
            
            // Require line to be in Plan usage section or explicitly a Plan usage window
            if let window = parseWindowLine(cleaned, kind: kind, observedAt: observedAt) {
                windows.append(window)
            }
        }
        
        return windows
    }

    // MARK: - Private Helpers

    private static func stripANSI(_ input: String) -> String {
        guard input.contains("\u{001B}") else { return input }
        return input.replacingOccurrences(
            of: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func cleanFrame(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        // Strip leading box border characters
        while let first = s.first, "│╭╰┆┊".contains(first) {
            s.removeFirst()
            s = s.trimmingCharacters(in: .whitespaces)
        }
        // Strip trailing box border characters
        while let last = s.last, "│╮╯┆┊".contains(last) {
            s.removeLast()
            s = s.trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    private static func extractHeaderValue(from lines: [String], key: String) -> String? {
        let prefix = key.lowercased() + ":"
        for line in lines {
            let cleaned = cleanFrame(line)
            let lower = cleaned.lowercased()
            if lower.hasPrefix(prefix) {
                let val = cleaned.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty {
                    return val
                }
            }
        }
        return nil
    }

    private static func parseWindowKind(from line: String) -> KimiWindowKind? {
        let lower = line.lowercased()
        if lower.contains("context") { return nil }
        
        if lower.contains("weekly limit") || lower.contains("weekly") {
            return .weekly
        } else if lower.contains("5h limit") || lower.contains("5 hour limit") || lower.contains("5-hour limit") || lower.contains("five hour limit") || lower.contains("five-hour limit") {
            return .fiveHour
        }
        return nil
    }

    private static func parseWindowLine(_ line: String, kind: KimiWindowKind, observedAt: Date) -> KimiCapacityWindow? {
        guard let usedPercent = parseUsedPercent(from: line) else { return nil }
        guard let resetDuration = parseResetDuration(from: line) else { return nil }
        
        let resetAt = observedAt.addingTimeInterval(resetDuration)
        return KimiCapacityWindow(
            kind: kind,
            usedPercent: usedPercent,
            observedAt: observedAt,
            resetAt: resetAt
        )
    }

    private static func parseUsedPercent(from line: String) -> Double? {
        // Match percentage used, e.g. "100% used", "0% used", "45.5% used"
        let pattern = #"(\d+(?:\.\d+)?)\s*%\s*(?:used)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        
        let nsString = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let valStr = nsString.substring(with: match.range(at: 1))
            if let val = Double(valStr) {
                return val
            }
        }
        return nil
    }

    private static func parseResetDuration(from line: String) -> TimeInterval? {
        // Look for "resets in ..." portion
        let searchString: String
        if let range = line.range(of: "resets in", options: .caseInsensitive) {
            searchString = String(line[range.upperBound...])
        } else {
            searchString = line
        }
        
        let pattern = #"(\d+)\s*([dhmsDHMS])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let nsString = searchString as NSString
        let matches = regex.matches(in: searchString, range: NSRange(location: 0, length: nsString.length))
        
        guard !matches.isEmpty else { return nil }
        
        var totalSeconds: TimeInterval = 0
        var foundUnit = false
        
        for match in matches {
            guard match.numberOfRanges == 3 else { continue }
            let numStr = nsString.substring(with: match.range(at: 1))
            let unitStr = nsString.substring(with: match.range(at: 2)).lowercased()
            guard let num = Double(numStr) else { continue }
            
            switch unitStr {
            case "d":
                totalSeconds += num * 86400
                foundUnit = true
            case "h":
                totalSeconds += num * 3600
                foundUnit = true
            case "m":
                totalSeconds += num * 60
                foundUnit = true
            case "s":
                totalSeconds += num
                foundUnit = true
            default:
                break
            }
        }
        
        return foundUnit ? totalSeconds : nil
    }
}
