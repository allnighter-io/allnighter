import Foundation

/// Shared ingestion bridge: pull the contents of the first ```<fence> … ``` code block out
/// of a writer's markdown. Used to lift a typed structured block (Signal Insight, Fix
/// Packet) out of model prose — the prose still renders, so a missing/invalid block
/// degrades gracefully rather than fabricating structure.
public enum FencedBlock {
    public static func extract(from text: String, fence: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        var collecting = false
        var collected: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !collecting {
                if trimmed == "```\(fence)" || trimmed == "``` \(fence)" { collecting = true }
            } else {
                if trimmed == "```" { return collected.joined(separator: "\n") }
                collected.append(line)
            }
        }
        return nil
    }
}
