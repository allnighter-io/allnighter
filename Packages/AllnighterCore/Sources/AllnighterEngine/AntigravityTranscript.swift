import Foundation

/// Normalizes an AGY/Antigravity run into a clean answer + separated step narration.
///
/// AGY has no streaming and no structured-output mode. Its `agy --print` stdout is usually
/// just the final answer — but on long, file-heavy runs that trip a mid-run context
/// "compaction", it dumps every `PLANNER_RESPONSE` step ("I will list… I will view…") before
/// the real answer, which then renders as the message. The session's structured transcript
/// (`<brain>/<sessionId>/.system_generated/logs/transcript.jsonl`) always keeps the split we
/// want: each `PLANNER_RESPONSE` is one step, the LAST one is the final answer, the earlier
/// ones are the narration. We read that and hand back (answer, reasoning).
public enum AntigravityTranscript {
    /// Cap the transcript read — it interleaves tool outputs (whole file contents) and can be
    /// large; we only need the `PLANNER_RESPONSE` lines, scanned line-by-line.
    static let maxBytes = 16 * 1024 * 1024

    public struct Split: Sendable, Equatable {
        public var answer: String
        public var reasoning: String
        public init(answer: String, reasoning: String) {
            self.answer = answer
            self.reasoning = reasoning
        }
    }

    /// The brain transcript for a session, or nil if it isn't there.
    public static func transcriptURL(brainDir: URL, sessionId: String) -> URL {
        brainDir.appendingPathComponent(sessionId, isDirectory: true)
            .appendingPathComponent(".system_generated/logs/transcript.jsonl")
    }

    /// Parse `transcript.jsonl`: answer = the last `PLANNER_RESPONSE` content; reasoning = the
    /// earlier `PLANNER_RESPONSE` contents (the "I will X" step narration) joined in order.
    /// Returns nil when the file is missing/unreadable or has no planner response — the caller
    /// then keeps the raw stdout (never worse than today).
    public static func split(transcriptAt url: URL) -> Split? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size <= maxBytes,
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return split(transcriptText: contents)
    }

    /// Pure split over the raw transcript text (testable without the filesystem).
    public static func split(transcriptText: String) -> Split? {
        var steps: [String] = []
        for line in transcriptText.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"),
                  let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "PLANNER_RESPONSE",
                  let content = (obj["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty
            else { continue }
            steps.append(content)
        }
        guard let answer = steps.last else { return nil }
        let reasoning = steps.dropLast().joined(separator: "\n")
        return Split(answer: answer, reasoning: reasoning)
    }
}
