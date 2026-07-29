import Foundation

/// Normalizes an AGY/Antigravity run into a clean answer + separated step narration.
///
/// AGY has no streaming and no structured-output mode. Its `agy --print` stdout is usually
/// just the final answer — but on long, file-heavy runs that trip a mid-run context
/// "compaction", it dumps every `PLANNER_RESPONSE` step ("I will list… I will view…") before
/// the real answer, which then renders as the message. The session's structured transcript
/// (`<brain>/<sessionId>/.system_generated/logs/transcript.jsonl`) always keeps the split we
/// want: each `PLANNER_RESPONSE` is one step, the earlier ones are the narration. We read that
/// and hand back (answer, reasoning).
///
/// The final answer is the last `PLANNER_RESPONSE` **before the first `SYSTEM_MESSAGE`** — not
/// simply the last one overall. AGY injects `SYSTEM_MESSAGE` turns after the model has already
/// answered the user, and the model dutifully replies to them; those replies are addressed to
/// the system, not the user, and degrade into content-free pleasantries:
///
///     step 17  PLANNER_RESPONSE  "Line 73. Returns \"\(modelId)#\(instanceIndex)\"."  ← the answer
///     step 18  SYSTEM_MESSAGE    "The following is a <SYSTEM_MESSAGE> not actually sent by…"
///     step 19  PLANNER_RESPONSE  "Thank you, task-6 completed."                       ← NOT the answer
///
/// Taking the last step made every such run report the pleasantry as the worker's answer while
/// still settling `done` — a silently faked success, and the reason agy seats looked useless.
/// Transcripts with no `SYSTEM_MESSAGE` are unaffected: the last step is still the answer.
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

    /// Parse `transcript.jsonl`: answer = the last user-directed `PLANNER_RESPONSE` content;
    /// reasoning = the earlier `PLANNER_RESPONSE` contents (the "I will X" step narration)
    /// joined in order. Returns nil when the file is missing/unreadable or has no planner
    /// response — the caller then keeps the raw stdout (never worse than today).
    public static func split(transcriptAt url: URL) -> Split? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size <= maxBytes,
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return split(transcriptText: contents)
    }

    /// Pure split over the raw transcript text (testable without the filesystem).
    public static func split(transcriptText: String) -> Split? {
        var steps: [String] = []
        // Once AGY injects a SYSTEM_MESSAGE and we already have a real answer, every later
        // PLANNER_RESPONSE is the model replying to the system rather than to the user — stop
        // collecting. Guarded on `!steps.isEmpty` so a SYSTEM_MESSAGE that arrives BEFORE any
        // answer (e.g. an early permission notice) can never starve us into returning nil.
        var systemTurnAfterAnswer = false
        JSONLScanner.forEachObject(transcriptText) { obj in
            let type = obj["type"] as? String
            if type == "SYSTEM_MESSAGE", !steps.isEmpty {
                systemTurnAfterAnswer = true
                return true
            }
            guard !systemTurnAfterAnswer else { return true }
            if type == "PLANNER_RESPONSE",
               let content = (obj["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                steps.append(content)
            }
            return true
        }
        guard let answer = steps.last else { return nil }
        let reasoning = steps.dropLast().joined(separator: "\n")
        return Split(answer: answer, reasoning: reasoning)
    }
}
