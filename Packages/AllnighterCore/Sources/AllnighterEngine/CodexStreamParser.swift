import Foundation
import AllnighterCore

/// Parses Codex's `codex exec --json` NDJSON (03_Mac_Streaming §Codex Parser).
/// Visible answer text is a COMPLETED message snapshot at `item.completed` /
/// `item.type == "agent_message"` / `item.text` — NOT a token delta (Codex's JSONL
/// does not expose visible text deltas), deduped by `item.id`. Reasoning items are
/// streamed to the thinking surface. Everything else (command_execution,
/// mcp_tool_call, web_search, file_change, todo_list, errors) is non-answer. The
/// canonical final answer remains the `{{outputFile}}` capture, with the streamed
/// snapshot as a fallback.
public final class CodexStreamParser: WorkerStreamParser, @unchecked Sendable {
    private let lines = LineAssembler()
    private var answer = ""
    private var seenItems = Set<String>()
    private var sequence = 0
    private var reasoningSeq = 0

    public init() {}

    public func receiveStdout(_ data: Data) -> [WorkerStreamEvent] {
        lines.feed(data).flatMap(handle)
    }

    public func finalAnswer(result: CommandResult, outputFileText: String?) -> String? {
        if let tail = lines.flush() { _ = handle(tail) }
        // Prefer the canonical output-file capture; fall back to the streamed snapshot.
        if let file = outputFileText, !file.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return file
        }
        return answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : answer
    }

    private func handle(_ line: String) -> [WorkerStreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let lineData = trimmed.data(using: .utf8),
              let event = try? JSONDecoder().decode(Event.self, from: lineData),
              event.type == "item.completed", let item = event.item else { return [] }

        if let id = item.id {
            guard !seenItems.contains(id) else { return [] }
            seenItems.insert(id)
        }

        switch item.type {
        case "agent_message":
            guard let text = item.text, !text.isEmpty else { return [] }
            answer += text
            sequence += 1
            return [.answerDelta(text: text, sequence: sequence, isMarkdown: true)]
        case "reasoning":
            guard let text = item.text, !text.isEmpty else { return [] }
            reasoningSeq += 1
            return [.reasoningDelta(text: text, sequence: reasoningSeq)]
        default:
            return []
        }
    }

    private struct Event: Decodable {
        let type: String
        let item: Item?
        struct Item: Decodable {
            let id: String?
            let type: String
            let text: String?
        }
    }
}
