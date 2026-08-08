import Foundation

/// Reset date precision for Cursor capacity usage windows.
/// Bare month/day resets (e.g. "Resets Aug 25") lack a time-of-day component
/// and are marked as day-precision so callers do not treat them as minute-accurate.
public enum CursorResetPrecision: String, Sendable, Equatable {
    case dayPrecision
}

/// Scope of the limit window for Cursor usage (Monthly plan / On-demand).
public enum CursorWindowScope: String, Sendable, Equatable {
    case monthly
}

/// Hierarchy relationship for a usage category row.
public enum CursorCategoryKind: Sendable, Equatable {
    case parent(children: [String])
    case child(parent: String)
    case standalone
}

/// A percent-based capacity category (e.g., Included, Auto, API).
/// Percent semantics: `usedPercent` is percentage of quota used (0…100+).
/// `remainingPercent` is normalized remaining capacity (100.0 - usedPercent).
public struct CursorPercentCategory: Sendable, Equatable {
    /// Category name (e.g., "Included", "Auto", "API").
    public let name: String
    /// Percentage used (0…100+). Nil if missing — never defaulted to 0.
    public let usedPercent: Double?
    /// Hierarchy role (parent with children names, child referencing parent, or standalone).
    public let hierarchy: CursorCategoryKind

    /// Computed remaining percentage (100.0 - usedPercent) if usedPercent is non-nil.
    public var remainingPercent: Double? {
        guard let usedPercent else { return nil }
        return max(0.0, 100.0 - usedPercent)
    }

    public init(name: String, usedPercent: Double?, hierarchy: CursorCategoryKind = .standalone) {
        self.name = name
        self.usedPercent = usedPercent
        self.hierarchy = hierarchy
    }
}

/// On-demand money spend for Cursor.
/// Real paid spend — modeled strictly as currency values, never coerced into percentages.
public struct CursorMoneySpend: Sendable, Equatable {
    /// Amount spent so far in dollars.
    public let usedDollars: Double
    /// Hard spend cap in dollars.
    public let capDollars: Double
    /// Remaining dollar amount if present or computed (capDollars - usedDollars).
    public let remainingDollars: Double?
    /// Currency symbol (e.g. "$").
    public let currency: String

    public init(usedDollars: Double, capDollars: Double, remainingDollars: Double? = nil, currency: String = "$") {
        self.usedDollars = usedDollars
        self.capDollars = capDollars
        self.remainingDollars = remainingDollars ?? max(0.0, capDollars - usedDollars)
        self.currency = currency
    }
}

/// Parsed snapshot of Cursor CLI plan usage and on-demand spend.
public struct CursorCapacitySnapshot: Sendable, Equatable {
    /// Subscription tier parsed from header (e.g. "Ultra").
    public let planTier: String?
    /// Window scope (e.g. .monthly).
    public let scope: CursorWindowScope
    /// Calculated reset timestamp resolved from bare date ("Aug 25") using `observedAt`.
    public let resetAt: Date?
    /// Reset precision (e.g. .dayPrecision).
    public let resetPrecision: CursorResetPrecision
    /// Wall clock timestamp when the render was observed.
    public let observedAt: Date
    /// Included plan percent categories (preserving parent/child hierarchy).
    public let percentCategories: [CursorPercentCategory]
    /// On-demand monetary spend if present.
    public let onDemandSpend: CursorMoneySpend?

    public init(
        planTier: String?,
        scope: CursorWindowScope = .monthly,
        resetAt: Date?,
        resetPrecision: CursorResetPrecision = .dayPrecision,
        observedAt: Date,
        percentCategories: [CursorPercentCategory],
        onDemandSpend: CursorMoneySpend?
    ) {
        self.planTier = planTier
        self.scope = scope
        self.resetAt = resetAt
        self.resetPrecision = resetPrecision
        self.observedAt = observedAt
        self.percentCategories = percentCategories
        self.onDemandSpend = onDemandSpend
    }

    /// Normalize into shared `CapacityWindow` values.
    ///
    /// Cursor is used-polarity, **monthly** scope, **day** reset precision, TUI probe tier.
    /// Dollar spend lands in `onDemand` with `unit == "$"` — never coerced into a percentage.
    ///
    /// Auto and API are separate meters — different quotas, different burn. When the
    /// `/usage` render nests them under Included, emit **one monthly window per child**
    /// (`poolLabel` = `Auto` / `API`). Do not collapse to the Included parent rollup;
    /// that hid the split and made the strip look like one Cursor number. Fall back to
    /// the parent/first known percent only when no child meters have a usable percent.
    /// Categories without a percent are skipped (never zero-filled). Money-only snapshots
    /// with no usable percent yield `[]` — inventing 0% is banned.
    public func asCapacityWindows() -> [CapacityWindow] {
        let paid = onDemandSpend.map { spend in
            CapacityPaidAmount(
                used: spend.usedDollars,
                cap: spend.capDollars,
                remaining: spend.remainingDollars,
                unit: spend.currency
            )
        }

        let childMeters = percentCategories.filter { category in
            guard category.usedPercent != nil else { return false }
            if case .child = category.hierarchy { return true }
            let name = category.name.lowercased()
            return name == "auto" || name == "api"
        }

        let meters: [CursorPercentCategory]
        if !childMeters.isEmpty {
            // Stable product order: Auto before API when both present.
            meters = childMeters.sorted { lhs, rhs in
                Self.cursorMeterRank(lhs.name) < Self.cursorMeterRank(rhs.name)
            }
        } else if let primary = percentCategories.first(where: {
            if case .parent = $0.hierarchy, $0.name.lowercased() == "included", $0.usedPercent != nil {
                return true
            }
            return false
        }) ?? percentCategories.first(where: {
            if case .parent = $0.hierarchy { return $0.usedPercent != nil }
            return false
        }) ?? percentCategories.first(where: { $0.usedPercent != nil }) {
            meters = [primary]
        } else {
            return []
        }

        return meters.enumerated().compactMap { index, category in
            guard let used = category.usedPercent else { return nil }
            return CapacityWindow(
                used: used,
                source: "cursor_agent",
                scope: .monthly,
                resetAt: resetAt,
                resetPrecision: .day,
                observedAt: observedAt,
                sourceTier: .tuiProbe,
                poolLabel: category.name,
                planTier: planTier,
                // Paid spend is seat-level — attach once, on the first meter.
                onDemand: index == 0 ? paid : nil
            )
        }
    }

    /// Auto before API; everything else keeps input order after those two.
    private static func cursorMeterRank(_ name: String) -> Int {
        switch name.lowercased() {
        case "auto": return 0
        case "api": return 1
        default: return 100
        }
    }
}

/// Extractor for Cursor Agent TUI `/usage` renders.
/// Pure parser — fail closed. Never throws, never calls `Date()`.
public enum CursorCapacityLog {

    /// Parse then normalize into shared `CapacityWindow` values.
    /// Returns `[]` when the render yields no convertible snapshot.
    public static func capacityWindows(fromRender renderText: String, observedAt: Date) -> [CapacityWindow] {
        parse(renderText: renderText, observedAt: observedAt)?.asCapacityWindows() ?? []
    }

    /// Parses capacity snapshot from raw `/usage` render text.
    ///
    /// - Parameters:
    ///   - renderText: Raw text output captured from Cursor CLI TUI `/usage`.
    ///   - observedAt: Caller-provided timestamp for the capture.
    /// - Returns: `CursorCapacitySnapshot` or `nil` if no valid usage data could be parsed.
    public static func parse(renderText: String, observedAt: Date) -> CursorCapacitySnapshot? {
        let cleanText = stripANSI(renderText)
        let lines = cleanText.components(separatedBy: .newlines)

        var planTier: String? = nil
        var resetAt: Date? = nil
        var scope: CursorWindowScope = .monthly

        var rawCategories: [(name: String, usedPercent: Double?, indent: Int)] = []
        var onDemandSpend: CursorMoneySpend? = nil
        var parsedRemainingDollars: Double? = nil

        for line in lines {
            let lineWithoutFrame = stripFrame(line)
            let trimmed = lineWithoutFrame.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let lower = trimmed.lowercased()

            // Skip noise / dashboard URL
            if lower.contains("view in dashboard") || lower.contains("cursor.com/dashboard") {
                continue
            }

            // Detect Header / Plan Tier and Reset date
            // e.g. "Usage • Ultra   Resets Aug 25"
            if lower.contains("usage") && (lower.contains("resets") || lower.contains("•") || lower.contains("-")) {
                if let extractedTier = parsePlanTier(from: lineWithoutFrame) {
                    planTier = extractedTier
                }
                if let extractedReset = parseResetDate(from: lineWithoutFrame, observedAt: observedAt) {
                    resetAt = extractedReset
                }
            } else if lower.contains("resets ") && resetAt == nil {
                if let extractedReset = parseResetDate(from: lineWithoutFrame, observedAt: observedAt) {
                    resetAt = extractedReset
                }
            }

            // Scope detection
            if lower.contains("monthly plan") || lower.contains("monthly") {
                scope = .monthly
            }

            // Category header line (e.g. "Category  Current  Usage")
            if lower.hasPrefix("category") && lower.contains("current") {
                continue
            }

            // On-demand spend remaining line (e.g. "$1 remaining")
            if lower.contains("remaining") && lower.contains("$") {
                if let dollars = parseRemainingDollars(from: trimmed) {
                    parsedRemainingDollars = dollars
                }
                continue
            }

            // Check if On-Demand dollar row (e.g. "On-Demand  $0 / $1")
            if lower.contains("on-demand") || lower.contains("on demand") {
                if let money = parseMoneySpend(from: trimmed, remainingOverride: parsedRemainingDollars) {
                    onDemandSpend = money
                }
                continue
            }

            // Try parsing as category percent row (e.g. "Included  27% used", "  Auto  27% used")
            if let cat = parseCategoryRow(from: lineWithoutFrame) {
                rawCategories.append(cat)
            }
        }

        // If we found parsedRemainingDollars after creating onDemandSpend, update remainingDollars if needed
        if let remaining = parsedRemainingDollars, let currentMoney = onDemandSpend {
            onDemandSpend = CursorMoneySpend(
                usedDollars: currentMoney.usedDollars,
                capDollars: currentMoney.capDollars,
                remainingDollars: remaining,
                currency: currentMoney.currency
            )
        }

        // Build parent/child hierarchy for percent categories
        let percentCategories = buildHierarchy(from: rawCategories)

        // Fail closed: return nil if no tier, no reset, no categories, and no on-demand spend parsed
        if planTier == nil && resetAt == nil && percentCategories.isEmpty && onDemandSpend == nil {
            return nil
        }

        return CursorCapacitySnapshot(
            planTier: planTier,
            scope: scope,
            resetAt: resetAt,
            resetPrecision: .dayPrecision,
            observedAt: observedAt,
            percentCategories: percentCategories,
            onDemandSpend: onDemandSpend
        )
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

    private static func stripFrame(_ line: String) -> String {
        var s = line
        // Strip rule box lines like ────
        if s.allSatisfy({ "─━│┌┐└┘├┤┬┴┼═║╔╗╚╝╠╣╦╩╬ ".contains($0) }) {
            return ""
        }
        // Strip leading box borders
        while let first = s.first, "│─┌└├".contains(first) {
            s.removeFirst()
        }
        // Strip trailing box borders
        while let last = s.last, "│─┐┘┤".contains(last) {
            s.removeLast()
        }
        return s
    }

    private static func parsePlanTier(from line: String) -> String? {
        // e.g. "Usage • Ultra", "Usage - Ultra", "Usage (Ultra)"
        let pattern = #"Usage\s*(?:•|-|\:|\()?\s*([A-Za-z0-9_\-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = line as NSString
        if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
           match.numberOfRanges >= 2 {
            let tier = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tier.isEmpty && tier.lowercased() != "monthly" && tier.lowercased() != "resets" {
                return tier
            }
        }
        return nil
    }

    private static func parseResetDate(from line: String, observedAt: Date) -> Date? {
        // e.g. "Resets Aug 25", "Resets August 25"
        let pattern = #"Resets\s+([A-Za-z]+)\s+(\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 3 else { return nil }

        let monthStr = ns.substring(with: match.range(at: 1))
        let dayStr = ns.substring(with: match.range(at: 2))
        guard let dayInt = Int(dayStr), dayInt >= 1, dayInt <= 31 else { return nil }

        return resolveResetDate(monthStr: monthStr, dayInt: dayInt, observedAt: observedAt)
    }

    private static func resolveResetDate(monthStr: String, dayInt: Int, observedAt: Date) -> Date? {
        guard let monthInt = parseMonthNumber(monthStr) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let obsComponents = calendar.dateComponents([.year, .month, .day], from: observedAt)
        guard let obsYear = obsComponents.year else { return nil }

        var target = DateComponents()
        target.calendar = calendar
        target.year = obsYear
        target.month = monthInt
        target.day = dayInt
        target.hour = 0
        target.minute = 0
        target.second = 0

        guard var candidate = calendar.date(from: target) else { return nil }

        let startOfObservedDay = calendar.startOfDay(for: observedAt)
        if candidate < startOfObservedDay {
            target.year = obsYear + 1
            if let nextCandidate = calendar.date(from: target) {
                candidate = nextCandidate
            }
        }

        return candidate
    }

    private static func parseMonthNumber(_ str: String) -> Int? {
        let lower = str.lowercased()
        let months = [
            "jan": 1, "january": 1,
            "feb": 2, "february": 2,
            "mar": 3, "march": 3,
            "apr": 4, "april": 4,
            "may": 5,
            "jun": 6, "june": 6,
            "jul": 7, "july": 7,
            "aug": 8, "august": 8,
            "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10,
            "nov": 11, "november": 11,
            "dec": 12, "december": 12
        ]
        return months[lower]
    }

    private static func parseCategoryRow(from line: String) -> (name: String, usedPercent: Double?, indent: Int)? {
        // Calculate leading indent space count
        var indent = 0
        for char in line {
            if char == " " { indent += 1 }
            else { break }
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }

        // Must not be header or noise or money spend
        let lower = trimmed.lowercased()
        if lower.hasPrefix("category") || lower.contains("on-demand") || lower.contains("on demand") || lower.contains("remaining") {
            return nil
        }

        // Split by multiple spaces or usage bar to extract category name and percentage
        let namePattern = #"^([A-Za-z0-9_\-\s]+?)\s{2,}"#
        guard let nameRegex = try? NSRegularExpression(pattern: namePattern) else { return nil }
        let ns = trimmed as NSString
        guard let match = nameRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else {
            return nil
        }

        let categoryName = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        if categoryName.isEmpty { return nil }

        // Parse percentage if present (e.g. "27% used" or "27%")
        let usedPercent = parseUsedPercent(from: trimmed)

        return (name: categoryName, usedPercent: usedPercent, indent: indent)
    }

    private static func parseUsedPercent(from text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*%\s*(?:used)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
           match.numberOfRanges >= 2 {
            let valStr = ns.substring(with: match.range(at: 1))
            return Double(valStr)
        }
        return nil
    }

    private static func parseMoneySpend(from line: String, remainingOverride: Double?) -> CursorMoneySpend? {
        // Match e.g. "$0 / $1" or "$10.50 / $50"
        let pattern = #"\$\s*(\d+(?:\.\d+)?)\s*/\s*\$\s*(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 3 else { return nil }

        let usedStr = ns.substring(with: match.range(at: 1))
        let capStr = ns.substring(with: match.range(at: 2))

        guard let used = Double(usedStr), let cap = Double(capStr) else { return nil }

        return CursorMoneySpend(
            usedDollars: used,
            capDollars: cap,
            remainingDollars: remainingOverride ?? max(0.0, cap - used),
            currency: "$"
        )
    }

    private static func parseRemainingDollars(from line: String) -> Double? {
        // e.g. "$1 remaining" or "$50.00 remaining"
        let pattern = #"\$\s*(\d+(?:\.\d+)?)\s+remaining"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = line as NSString
        if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
           match.numberOfRanges >= 2 {
            let valStr = ns.substring(with: match.range(at: 1))
            return Double(valStr)
        }
        return nil
    }

    private static func buildHierarchy(
        from raw: [(name: String, usedPercent: Double?, indent: Int)]
    ) -> [CursorPercentCategory] {
        guard !raw.isEmpty else { return [] }

        let minIndent = raw.map(\.indent).min() ?? 0

        var result: [CursorPercentCategory] = []
        var currentParentIndex: Int? = nil
        var parentChildrenMap: [Int: [String]] = [:]

        for i in 0..<raw.count {
            let item = raw[i]
            if item.indent > minIndent, let parentIdx = currentParentIndex {
                parentChildrenMap[parentIdx, default: []].append(item.name)
            } else {
                currentParentIndex = i
            }
        }

        currentParentIndex = nil
        for i in 0..<raw.count {
            let item = raw[i]
            if item.indent > minIndent, let parentIdx = currentParentIndex {
                let parentName = raw[parentIdx].name
                result.append(CursorPercentCategory(
                    name: item.name,
                    usedPercent: item.usedPercent,
                    hierarchy: .child(parent: parentName)
                ))
            } else {
                currentParentIndex = i
                let children = parentChildrenMap[i] ?? []
                let hierarchy: CursorCategoryKind = children.isEmpty ? .standalone : .parent(children: children)
                result.append(CursorPercentCategory(
                    name: item.name,
                    usedPercent: item.usedPercent,
                    hierarchy: hierarchy
                ))
            }
        }

        return result
    }
}
