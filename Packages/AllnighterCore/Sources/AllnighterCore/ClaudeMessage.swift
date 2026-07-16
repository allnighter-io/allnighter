import Foundation

/// Claude Code `--input-format stream-json` protocol (Warm_Single_Lane_Chat Phase 2). A THIRD wire
/// dialect, distinct from ACP (grok/cursor) and codex app-server: there is NO handshake and NO
/// session id — the warm process IS the session. The client sends `{"type":"user",…}` messages on
/// stdin and reads streamed `stream_event` deltas + a terminal `{"type":"result"}` per turn.
///
/// PURE: encodes the user message + classifies one inbound line. Transport/lifecycle = `ClaudeSession`.
public enum ClaudeMsg {
    /// One user turn, as a Claude Code stream-json input message.
    public static func userMessage(_ text: String) -> String {
        let obj: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": [["type": "text", "text": text]]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return "\n" }
        return s + "\n"
    }

    public enum Inbound: Equatable, Sendable {
        case answerDelta(String)      // stream_event content_block_delta text_delta
        case reasoningDelta(String)   // stream_event content_block_delta thinking_delta
        case turnCompleted(usage: ReportedTokenUsage?) // {"type":"result"} — turn-end + optional usage
        case failure(message: String) // result with is_error, or an error message
        case other                    // system/init, assistant snapshot, tool events, …
    }

    public static func parse(_ line: String) -> Inbound? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        switch obj["type"] as? String {
        case "stream_event":
            guard let event = obj["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any] else { return .other }
            switch delta["type"] as? String {
            case "text_delta":
                if let t = delta["text"] as? String, !t.isEmpty { return .answerDelta(t) }
            case "thinking_delta":
                if let t = delta["thinking"] as? String, !t.isEmpty { return .reasoningDelta(t) }
            default: break
            }
            return .other

        case "result":
            if (obj["is_error"] as? Bool) == true {
                return .failure(message: (obj["result"] as? String) ?? (obj["subtype"] as? String) ?? "error")
            }
            return .turnCompleted(usage: usage(from: obj["usage"] as? [String: Any]))

        default:
            return .other
        }
    }

    private static func usage(from dict: [String: Any]?) -> ReportedTokenUsage? {
        guard let dict else { return nil }
        let input = intValue(dict["input_tokens"])
        let output = intValue(dict["output_tokens"])
        let usage = ReportedTokenUsage(inputTokens: input, outputTokens: output)
        return usage.isEmpty ? nil : usage
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }
}
