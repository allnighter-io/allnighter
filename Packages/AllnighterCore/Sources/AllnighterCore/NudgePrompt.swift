import Foundation

/// Template nudge for a stalled slice unit (Pair_Programming_Team PPT-S09). Not LLM-authored.
public enum NudgePrompt {
    public static func assemble(
        packet: WorkSlicePacket,
        attempt: Int,
        maxRetries: Int,
        reason: String,
        stdoutTail: String?
    ) -> String {
        var parts = [
            "NUDGE — same slice \(packet.sliceId) (attempt \(attempt)/\(maxRetries)).",
            "Reason: \(reason)",
            "Do not expand scope. Touch ONLY the allowlisted paths.",
            "Run the repo check when done.",
        ]
        if let tail = stdoutTail?.trimmingCharacters(in: .whitespacesAndNewlines), !tail.isEmpty {
            parts.append("Last output tail:\n```\n\(tail)\n```")
        }
        return parts.joined(separator: "\n")
    }
}
