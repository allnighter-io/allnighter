import Foundation

/// Codex `app-server` protocol — JSON-RPC 2.0-SHAPED but with the `"jsonrpc"` field OMITTED
/// (verified against codex-cli 0.140.0; see docs/phases/Warm_Single_Lane_Chat.md Phase 3). This is a
/// DIFFERENT dialect from ACP (grok/cursor): `thread/start` not `session/new`, `turn/start` not
/// `session/prompt`, `item/agentMessage/delta` not `agent_message_chunk`, and turn completion is a
/// `turn/completed` NOTIFICATION rather than the request's result.
///
/// PURE: encodes outgoing client messages and classifies ONE inbound line. Transport + lifecycle
/// live in the Engine (`CodexSession`).
public enum Codex {
    // MARK: - Outgoing (client → app-server): newline-framed, no `jsonrpc` field

    public static func initialize(id: Int) -> String {
        line(["method": "initialize", "id": id,
              "params": ["clientInfo": ["name": "allnighter", "title": "Allnighter", "version": "0.1.0"]]])
    }

    /// Notification (no id) the client sends right after `initialize` resolves.
    public static func initialized() -> String { line(["method": "initialized"]) }

    /// Open a thread bound to `cwd`. `approvalPolicy:"never"` = no per-turn approval prompts.
    public static func threadStart(id: Int, cwd: String, model: String) -> String {
        line(["method": "thread/start", "id": id,
              "params": ["cwd": cwd, "model": model,
                         "approvalPolicy": "never", "sandbox": "workspace-write"]])
    }

    /// Submit one user turn. The server streams `item/*` deltas, then a `turn/completed` notification.
    public static func turnStart(id: Int, threadId: String, text: String) -> String {
        line(["method": "turn/start", "id": id,
              "params": ["threadId": threadId,
                         "input": [["type": "text", "text": text, "text_elements": [String]()]]] as [String: Any]])
    }

    /// Minimal ack for a server→client request (rare under `approvalPolicy:"never"`).
    public static func emptyResult(id: Int) -> String { line(["id": id, "result": [String: String]()]) }

    private static func line(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return "\n" }
        return s + "\n"
    }

    // MARK: - Inbound (app-server → client)

    public enum Inbound: Equatable, Sendable {
        /// Response to one of OUR requests. `threadId` set only for a `thread/start` reply.
        case result(id: Int, threadId: String?)
        case failure(id: Int?, message: String)
        case answerDelta(String)      // item/agentMessage/delta
        case reasoningDelta(String)   // item/reasoning/textDelta | summaryTextDelta
        case turnCompleted            // the turn-end signal (a NOTIFICATION, not a result)
        case serverRequest(id: Int)   // app-server asks us something; ack so it doesn't block
        case other
    }

    public static func parse(_ line: String) -> Inbound? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        let id: Int? = (obj["id"] as? Int) ?? (obj["id"] as? NSNumber)?.intValue

        if let id {
            if let err = obj["error"] as? [String: Any] {
                return .failure(id: id, message: (err["message"] as? String) ?? "")
            }
            if obj.keys.contains("result") {
                // thread/start → result.thread.id
                let result = obj["result"] as? [String: Any]
                let threadId = (result?["thread"] as? [String: Any])?["id"] as? String
                    ?? result?["threadId"] as? String
                return .result(id: id, threadId: threadId)
            }
            if obj["method"] != nil { return .serverRequest(id: id) }
        }

        guard let method = obj["method"] as? String else { return nil }
        let params = obj["params"] as? [String: Any]
        switch method {
        case "item/agentMessage/delta":
            return .answerDelta(deltaText(params) ?? "")
        case "item/reasoning/textDelta", "item/reasoning/summaryTextDelta":
            return .reasoningDelta(deltaText(params) ?? "")
        case "turn/completed":
            return .turnCompleted
        case "error":
            return .failure(id: nil, message: (params?["message"] as? String) ?? "error")
        default:
            return .other
        }
    }

    /// The streamed text lives under one of these keys depending on item type (proven in the spike).
    private static func deltaText(_ params: [String: Any]?) -> String? {
        for key in ["delta", "text", "content"] {
            if let s = params?[key] as? String, !s.isEmpty { return s }
        }
        return nil
    }
}
