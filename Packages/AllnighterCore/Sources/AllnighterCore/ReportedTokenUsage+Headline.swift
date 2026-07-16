import Foundation

public extension ReportedTokenUsage {
    /// Compact suffix for `outcome.headline`, e.g. `12.4k tok`. Nil when nothing to report.
    var headlineSuffix: String? {
        guard let total = totalTokens, total > 0 else { return nil }
        return Self.formatCompact(total) + " tok"
    }

    static func formatCompact(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 10_000 { return String(format: "%.0fk", Double(count) / 1000) }
        if count >= 1000 { return String(format: "%.1fk", Double(count) / 1000) }
        return String(count)
    }
}
