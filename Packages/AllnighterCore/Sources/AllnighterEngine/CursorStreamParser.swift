import Foundation
import AllnighterCore

/// Parses Cursor Agent's `--output-format stream-json --stream-partial-output` NDJSON
/// (03_Mac_Streaming §Cursor Agent Parser). With partial output enabled, the visible
/// incremental deltas are `type:"assistant"` events that HAVE `timestamp_ms` and do
/// NOT have `model_call_id`; their text is `message.content[*].text` (type "text").
/// Everything else is skipped:
///   - assistant with BOTH `timestamp_ms` + `model_call_id` → buffered flush before a tool call
///   - assistant WITHOUT `timestamp_ms` → duplicate full end-of-turn flush
///   - system / user / tool_call / thinking / result(as delta)
/// The canonical final answer is `type:"result"` `$.result`; it replaces/repairs the
/// accumulator at settlement (never appended as one more delta).
public final class CursorStreamParser: WorkerStreamParser, @unchecked Sendable {
    private let lines = LineAssembler()
    private var accumulator = ""
    private var sequence = 0
    private var resultText: String?

    public init() {}

    public func receiveStdout(_ data: Data) -> [WorkerStreamEvent] {
        lines.feed(data).flatMap(handle)
    }

    public func finalAnswer(result: CommandResult, outputFileText: String?) -> String? {
        if let tail = lines.flush() { _ = handle(tail) }
        // result.result is canonical; fall back to the streamed accumulator.
        if let r = resultText, !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return r }
        let acc = accumulator.trimmingCharacters(in: .whitespacesAndNewlines)
        return acc.isEmpty ? nil : accumulator
    }

    private func handle(_ line: String) -> [WorkerStreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let lineData = trimmed.data(using: .utf8),
              let event = try? JSONDecoder().decode(Event.self, from: lineData) else { return [] }

        switch event.type {
        case "assistant":
            // Only delta-form events mutate visible text (timestamp present, no
            // model_call_id). Skip duplicate buffered + end-of-turn flushes.
            guard event.timestamp_ms != nil, event.model_call_id == nil else {
                return [.rawEvent(sourceId: "cursor_agent", json: trimmed)]
            }
            let text = (event.message?.content ?? [])
                .filter { $0.type == "text" }
                .compactMap(\.text)
                .joined()
            guard !text.isEmpty else { return [] }
            accumulator += text
            sequence += 1
            return [.answerDelta(text: text, sequence: sequence, isMarkdown: true)]
        case "result":
            if let r = event.result { resultText = r }
            return [.rawEvent(sourceId: "cursor_agent", json: trimmed)]
        default:
            // system / user / tool_call / thinking / unknown.
            return [.rawEvent(sourceId: "cursor_agent", json: trimmed)]
        }
    }

    private struct Event: Decodable {
        let type: String
        let timestamp_ms: Int64?
        let model_call_id: String?
        let message: Message?
        let result: String?

        struct Message: Decodable {
            let content: [Content]?
            struct Content: Decodable {
                let type: String
                let text: String?
            }
        }
    }
}
