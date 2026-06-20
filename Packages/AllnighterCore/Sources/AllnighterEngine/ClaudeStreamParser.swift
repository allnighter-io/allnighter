import Foundation
import AllnighterCore

/// Parses Claude Code's `--output-format stream-json --include-partial-messages
/// --verbose` NDJSON (03_Mac_Streaming §Claude Code Parser). Visible answer text is
/// `stream_event` → `content_block_delta` → `text_delta.text`, bucketed by
/// `event.index`. Claude also exposes extended thinking as `thinking_delta.thinking`,
/// which we stream to the reasoning surface. The canonical final answer is the
/// terminal `result.result`; the per-message `assistant` snapshots are ignored for
/// rendering (the deltas already built the text).
public final class ClaudeStreamParser: WorkerStreamParser, @unchecked Sendable {
    private let lines = LineAssembler()
    private var blocks: [Int: String] = [:]   // content-block index → accumulated text
    private var order: [Int] = []
    private var resultText: String?
    private var sequence = 0
    private var reasoningSeq = 0

    public init() {}

    public func receiveStdout(_ data: Data) -> [WorkerStreamEvent] {
        lines.feed(data).flatMap(handle)
    }

    public func finalAnswer(result: CommandResult, outputFileText: String?) -> String? {
        if let tail = lines.flush() { _ = handle(tail) }
        if let r = resultText, !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return r }
        let acc = order.compactMap { blocks[$0] }.joined()
        return acc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : acc
    }

    private func handle(_ line: String) -> [WorkerStreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let lineData = trimmed.data(using: .utf8),
              let event = try? JSONDecoder().decode(Event.self, from: lineData) else { return [] }

        switch event.type {
        case "stream_event":
            guard let ev = event.event, ev.type == "content_block_delta", let delta = ev.delta else { return [] }
            switch delta.type {
            case "text_delta":
                guard let text = delta.text, !text.isEmpty else { return [] }
                let idx = ev.index ?? 0
                if blocks[idx] == nil { order.append(idx) }
                blocks[idx, default: ""] += text
                sequence += 1
                return [.answerDelta(text: text, sequence: sequence, isMarkdown: true)]
            case "thinking_delta":
                guard let thought = delta.thinking, !thought.isEmpty else { return [] }
                reasoningSeq += 1
                return [.reasoningDelta(text: thought, sequence: reasoningSeq)]
            default:
                // input_json_delta / signature_delta — never answer text.
                return []
            }
        case "result":
            if let r = event.result { resultText = r }
            return []
        default:
            // system / assistant snapshot / user / message_* / content_block_* — audit.
            return []
        }
    }

    private struct Event: Decodable {
        let type: String
        let event: Ev?
        let result: String?

        struct Ev: Decodable {
            let type: String
            let index: Int?
            let delta: Delta?
            struct Delta: Decodable {
                let type: String
                let text: String?
                let thinking: String?
            }
        }
    }
}
