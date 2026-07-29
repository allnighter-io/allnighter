import Foundation

/// Parsed `seat` fenced JSON — elevator one-liner from a crew seat (not a mini Lead Call).
public struct SeatSummary: Codable, Equatable, Sendable {
    public var schemaVersion: Int?
    /// One plain sentence — the chip headline. Agent-authored; never projector-invented.
    public var summary: String?
}

public enum SeatSummaryParser {
    public static func parse(from markdown: String?) -> SeatSummary? {
        guard let markdown,
              let json = FencedBlock.extract(from: markdown, fence: "seat") else { return nil }
        return try? CoreJSON.decode(SeatSummary.self, from: Data(json.utf8))
    }

    public static func summary(from markdown: String?) -> String? {
        guard let s = parse(from: markdown)?.summary?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return s
    }

    /// Remove the machine `seat` fence so craft/detail rendering stays honest.
    public static func stripFence(from markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var kept: [String] = []
        var skipping = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !skipping {
                if trimmed == "```seat" || trimmed == "``` seat" {
                    skipping = true
                    continue
                }
                kept.append(line)
            } else if trimmed == "```" {
                skipping = false
            }
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
