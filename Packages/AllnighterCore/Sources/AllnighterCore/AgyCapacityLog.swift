import Foundation

/// Represents the limit window duration kind for an agy model pool.
public enum AgyWindowKind: String, Sendable, Equatable, CaseIterable {
    case weekly
    case fiveHour
}

/// One capacity limit window (e.g., Weekly or Five Hour) for an agy model pool.
///
/// Semantics:
/// - `remainingPercent` is normalized to the percentage remaining (0…100).
///   Note: `agy` displays quota in terms of remaining capacity.
/// - `resetAt` is calculated as `observedAt + resetDuration`.
public struct AgyCapacityWindow: Sendable, Equatable {
    public let kind: AgyWindowKind
    /// Normalized remaining capacity percentage (0…100).
    public let remainingPercent: Double
    /// Wall clock time when the render was captured.
    public let observedAt: Date
    /// Computed absolute reset time (`observedAt + resetDuration`).
    public let resetAt: Date

    public init(
        kind: AgyWindowKind,
        remainingPercent: Double,
        observedAt: Date,
        resetAt: Date
    ) {
        self.kind = kind
        self.remainingPercent = remainingPercent
        self.observedAt = observedAt
        self.resetAt = resetAt
    }

    /// Normalize into the shared `CapacityWindow` surface.
    ///
    /// Agy is remaining-polarity; relative duration → minute precision; TUI probe tier.
    /// `poolLabel` must carry the pool heading — two pools is why the label exists.
    public func asCapacityWindow(poolLabel: String) -> CapacityWindow {
        let scope: CapacityWindowScope
        switch kind {
        case .weekly: scope = .weekly
        case .fiveHour: scope = .fiveHour
        }
        return CapacityWindow(
            remaining: remainingPercent,
            source: "agy",
            scope: scope,
            resetAt: resetAt,
            resetPrecision: .minute,
            observedAt: observedAt,
            sourceTier: .tuiProbe,
            poolLabel: poolLabel
        )
    }
}

/// A group/pool of models in agy (e.g., "GEMINI MODELS") sharing quota limits.
public struct AgyPoolCapacity: Sendable, Equatable {
    /// Account identifier associated with this render if present (e.g. "support@allnighter.io").
    /// Note: Account string is PII — carried here so a later slice can redact it. Do not log it.
    public let account: String?
    /// Name of the model group/pool (e.g. "GEMINI MODELS").
    public let name: String
    /// List of models belonging to this pool (e.g. ["Gemini Flash", "Gemini Pro"]).
    public let memberModels: [String]
    /// Capacity windows for this pool (e.g. weekly, fiveHour).
    public let windows: [AgyCapacityWindow]

    public init(
        account: String?,
        name: String,
        memberModels: [String],
        windows: [AgyCapacityWindow]
    ) {
        self.account = account
        self.name = name
        self.memberModels = memberModels
        self.windows = windows
    }

    /// Normalize every window in this pool; pool `name` becomes `poolLabel`.
    public func asCapacityWindows() -> [CapacityWindow] {
        windows.map { $0.asCapacityWindow(poolLabel: name) }
    }
}

/// Extractor for agy (Antigravity driver) TUI `/usage` renders.
/// Pure parser — fail closed. Never throws, never calls `Date()`.
public enum AgyCapacityLog {

    /// Parses model pools and capacity windows from raw `/usage` render text.
    ///
    /// - Parameters:
    ///   - renderText: Raw text output captured from `agy /usage` (may include ANSI escapes or box characters).
    ///   - observedAt: Caller-provided timestamp for the capture.
    /// - Returns: Array of parsed `AgyPoolCapacity` structs.
    public static func parse(renderText: String, observedAt: Date) -> [AgyPoolCapacity] {
        parsePools(fromRender: renderText, observedAt: observedAt)
    }

    /// Parse then normalize every pool window into shared `CapacityWindow` values.
    public static func capacityWindows(fromRender renderText: String, observedAt: Date) -> [CapacityWindow] {
        parse(renderText: renderText, observedAt: observedAt).flatMap { $0.asCapacityWindows() }
    }

    /// Parses model pools and capacity windows from raw `/usage` render text.
    public static func parsePools(fromRender renderText: String, observedAt: Date) -> [AgyPoolCapacity] {
        let cleanText = stripANSI(renderText)
        let lines = cleanText.components(separatedBy: .newlines)
        
        let account = extractAccount(from: lines)
        let poolStarts = findPoolStarts(in: lines)
        
        var results: [AgyPoolCapacity] = []
        
        for (index, pool) in poolStarts.enumerated() {
            let nextHeadingIndex = (index + 1 < poolStarts.count) ? poolStarts[index + 1].headingLineIndex : lines.count
            let poolLineSlice = lines[pool.startIndex..<nextHeadingIndex]
            let poolLines = Array(poolLineSlice)
            
            let windows = parseWindows(from: poolLines, observedAt: observedAt)
            if !windows.isEmpty {
                results.append(AgyPoolCapacity(
                    account: account,
                    name: pool.name,
                    memberModels: pool.memberModels,
                    windows: windows
                ))
            }
        }
        
        return results
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

    private static func extractAccount(from lines: [String]) -> String? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Account:") {
                let val = trimmed.dropFirst("Account:".count).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty {
                    return val
                }
            }
        }
        return nil
    }

    private struct InternalPoolStart {
        let name: String
        let memberModels: [String]
        let headingLineIndex: Int
        let startIndex: Int
    }

    private static func findPoolStarts(in lines: [String]) -> [InternalPoolStart] {
        var starts: [InternalPoolStart] = []
        
        for i in 0..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            guard trimmed.contains("Models within this group:") else { continue }
            
            let parts = trimmed.components(separatedBy: "Models within this group:")
            guard parts.count > 1 else { continue }
            let rawModels = parts[1].components(separatedBy: ",")
            let memberModels = rawModels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !memberModels.isEmpty else { continue }
            
            // Look backward for pool heading name
            var poolName: String? = nil
            var headingIdx: Int = i
            for j in (0..<i).reversed() {
                let prevTrimmed = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                if !prevTrimmed.isEmpty {
                    if isValidPoolName(prevTrimmed) {
                        poolName = prevTrimmed
                        headingIdx = j
                    }
                    break
                }
            }
            
            guard let validName = poolName else { continue }
            
            starts.append(InternalPoolStart(
                name: validName,
                memberModels: memberModels,
                headingLineIndex: headingIdx,
                startIndex: i + 1
            ))
        }
        
        return starts
    }

    private static func isValidPoolName(_ name: String) -> Bool {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.isEmpty { return false }
        if lower.hasPrefix("account:") { return false }
        if lower == "models & quota" || lower == "models and quota" { return false }
        return true
    }

    private static func parseWindows(from lines: [String], observedAt: Date) -> [AgyCapacityWindow] {
        var windows: [AgyCapacityWindow] = []
        
        var currentKind: AgyWindowKind? = nil
        var currentLines: [String] = []
        
        for line in lines {
            if let kind = parseWindowKind(in: line) {
                if let k = currentKind {
                    if let w = buildWindow(kind: k, lines: currentLines, observedAt: observedAt) {
                        windows.append(w)
                    }
                }
                currentKind = kind
                currentLines = []
            } else if currentKind != nil {
                currentLines.append(line)
            }
        }
        
        if let k = currentKind {
            if let w = buildWindow(kind: k, lines: currentLines, observedAt: observedAt) {
                windows.append(w)
            }
        }
        
        return windows
    }

    private static func parseWindowKind(in line: String) -> AgyWindowKind? {
        let lower = line.lowercased()
        if lower.contains("models within") || lower.contains("account:") { return nil }
        if lower.contains("weekly") {
            return .weekly
        } else if lower.contains("five hour") || lower.contains("5 hour") || lower.contains("five-hour") || lower.contains("5-hour") {
            return .fiveHour
        }
        return nil
    }

    private static func buildWindow(kind: AgyWindowKind, lines: [String], observedAt: Date) -> AgyCapacityWindow? {
        guard let remainingPercent = parseRemainingPercent(from: lines) else { return nil }
        guard let durationSeconds = parseDurationInSeconds(from: lines) else { return nil }
        
        let resetAt = observedAt.addingTimeInterval(durationSeconds)
        return AgyCapacityWindow(
            kind: kind,
            remainingPercent: remainingPercent,
            observedAt: observedAt,
            resetAt: resetAt
        )
    }

    private static func parseRemainingPercent(from lines: [String]) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        var floatMatch: Double? = nil
        var firstMatch: Double? = nil
        
        for line in lines {
            let nsString = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                guard match.numberOfRanges >= 2 else { continue }
                let valStr = nsString.substring(with: match.range(at: 1))
                guard let val = Double(valStr) else { continue }
                if firstMatch == nil {
                    firstMatch = val
                }
                if valStr.contains(".") {
                    floatMatch = val
                    break
                }
            }
            if floatMatch != nil { break }
        }
        
        return floatMatch ?? firstMatch
    }

    private static func parseDurationInSeconds(from lines: [String]) -> TimeInterval? {
        let combined = lines.joined(separator: "\n")
        let range = combined.range(of: "Refreshes in", options: .caseInsensitive)
        guard let range else { return nil }
        
        let durationSubstring = combined[range.upperBound...]
        let pattern = #"(\d+)\s*([dhmsDHMS])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let str = String(durationSubstring)
        let nsString = str as NSString
        let matches = regex.matches(in: str, range: NSRange(location: 0, length: nsString.length))
        
        guard !matches.isEmpty else { return nil }
        
        var totalSeconds: TimeInterval = 0
        for match in matches {
            guard match.numberOfRanges == 3 else { continue }
            let numStr = nsString.substring(with: match.range(at: 1))
            let unitStr = nsString.substring(with: match.range(at: 2)).lowercased()
            guard let num = Double(numStr) else { continue }
            
            switch unitStr {
            case "d":
                totalSeconds += num * 86400
            case "h":
                totalSeconds += num * 3600
            case "m":
                totalSeconds += num * 60
            case "s":
                totalSeconds += num
            default:
                break
            }
        }
        
        return matches.isEmpty ? nil : totalSeconds
    }
}
