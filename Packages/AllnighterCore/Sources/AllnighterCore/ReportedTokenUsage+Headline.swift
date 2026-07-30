import Foundation

public extension ReportedTokenUsage {
    /// Compact suffix for `outcome.headline`, e.g. `12.4k tok`.
    /// Prefer `ObservedUsagePresentation.compactTok` for input-only / output-only honesty.
    var headlineSuffix: String? {
        ObservedUsagePresentation.compactTok(self)
    }

    static func formatCompact(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 100_000 { return String(format: "%.0fk", Double(count) / 1000) }
        if count >= 1000 { return String(format: "%.1fk", Double(count) / 1000) }
        return String(count)
    }
}
