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

    /// Escalating nudge after a failed executor attempt (check fail, worker error, or stall).
    public static func failureRetry(
        packet: WorkSlicePacket,
        attempt: Int,
        maxAttempts: Int,
        reason: String,
        checkStdoutTail: String?,
        stdoutTail: String?
    ) -> String {
        var parts = [
            "NUDGE — same slice \(packet.sliceId) (executor attempt \(attempt)/\(maxAttempts)).",
            "Reason: \(reason)",
            "Do not expand scope. Touch ONLY the allowlisted paths.",
            "Run the repo check when done.",
        ]

        if attempt >= 2 {
            parts.append(
                "Prior attempts failed. Re-read the intent and allowlist. Make the smallest change that satisfies the check."
            )
            if let tail = checkStdoutTail?.trimmingCharacters(in: .whitespacesAndNewlines), !tail.isEmpty {
                parts.append("Check output:\n```\n\(tail)\n```")
            }
        }

        if let tail = stdoutTail?.trimmingCharacters(in: .whitespacesAndNewlines), !tail.isEmpty, attempt < 2 {
            parts.append("Last output tail:\n```\n\(tail)\n```")
        }

        return parts.joined(separator: "\n")
    }
}
