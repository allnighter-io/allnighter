import Foundation
import AllnighterCore

/// Parses Grok Build's `--output-format streaming-json` NDJSON into worker stream
/// events (03_Mac_Streaming §Grok Parser). Visible answer text is `type:"text"`
/// `$.data` (incremental deltas, concatenated in arrival order). `type:"thought"`
/// is reasoning — audit only, NEVER visible. `end`/`error`/unknown are non-answer.
/// The accumulator is the canonical final answer (`finalAnswerSource: parser_accumulator`).
public final class GrokStreamParser: WorkerStreamParser, @unchecked Sendable {
    private let lines = LineAssembler()
    private var accumulator = ""
    private var sequence = 0
    private var reasoningSeq = 0

    public init() {}

    public func receiveStdout(_ data: Data) -> [WorkerStreamEvent] {
        lines.feed(data).flatMap(handle)
    }

    public func finalAnswer(result: CommandResult, outputFileText: String?) -> String? {
        // Drain any trailing partial line (a last event without a newline at exit).
        if let tail = lines.flush() { _ = handle(tail) }
        let acc = accumulator.trimmingCharacters(in: .whitespacesAndNewlines)
        if !acc.isEmpty { return accumulator }
        // Degraded (we streamed nothing): fall back to the same post-exit extraction
        // the non-streaming path uses, over the full stdout buffer.
        let extracted = TextUtil.extractGrokStreamingVisibleText(result.stdout)
        return extracted.isEmpty ? nil : extracted
    }

    private func handle(_ line: String) -> [WorkerStreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let lineData = trimmed.data(using: .utf8),
              let event = try? JSONDecoder().decode(Event.self, from: lineData) else { return [] }
        switch event.type {
        case "text":
            guard let text = event.data, !text.isEmpty else { return [] }
            accumulator += text
            sequence += 1
            return [.answerDelta(text: text, sequence: sequence, isMarkdown: true)]
        case "thought":
            // Reasoning — streamed to the live "thinking" surface (never answer text).
            guard let text = event.data, !text.isEmpty else { return [] }
            reasoningSeq += 1
            return [.reasoningDelta(text: text, sequence: reasoningSeq)]
        default:
            // end / error / max_turns_reached / auto_compact_* / unknown.
            return [.rawEvent(sourceId: "grok", json: trimmed)]
        }
    }

    private struct Event: Decodable {
        let type: String
        let data: String?
    }
}

/// Picks the right per-invocation stream parser for a driver, or nil when the
/// driver is not stream-capable (caller falls back to non-streaming `invoke`).
public enum WorkerStreamParsers {
    public static func make(for manifest: DriverManifest) -> WorkerStreamParser? {
        guard manifest.canStream else { return nil }
        switch manifest.id {
        case "grok": return GrokStreamParser()
        case "cursor_agent": return CursorStreamParser()
        default: return nil   // STR-S10 adds Claude/Codex.
        }
    }
}
