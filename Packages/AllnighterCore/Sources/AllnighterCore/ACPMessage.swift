import Foundation

/// Agent Client Protocol (ACP) — JSON-RPC 2.0 message framing for driving a warm `grok agent stdio`
/// worker (see docs/phases/Warm_Single_Lane_Chat.md §4b). ACP is the cross-vendor standard
/// (agentclientprotocol.com; used by Zed/Neovim/Emacs) a CLI speaks over stdin/stdout to stay warm:
/// one process indexes the repo ONCE, then every turn is model-time only (~1.5–3.4s vs ~22s cold).
///
/// This type is PURE: it encodes outgoing client requests and classifies ONE inbound JSON line.
/// The stdio transport + session lifecycle live in the Engine (`ACPWorker`).
public enum ACP {
    /// ACP protocol version we negotiate (the integer form `grok agent stdio` expects).
    public static let protocolVersion = 1

    // MARK: - Outgoing (client → agent): newline-framed JSON-RPC requests

    /// Handshake. Must be the first message; the agent replies with its capabilities.
    public static func initialize(id: Int) -> String {
        line(["jsonrpc": "2.0", "id": id, "method": "initialize",
              "params": ["protocolVersion": protocolVersion,
                         "clientCapabilities": [String: String]()] as [String: Any]])
    }

    /// Open a conversation bound to `cwd` (the real repo root). The agent's one-time working-tree
    /// index happens here (async — it does not block the response). Reply carries `sessionId`.
    public static func sessionNew(id: Int, cwd: String) -> String {
        line(["jsonrpc": "2.0", "id": id, "method": "session/new",
              "params": ["cwd": cwd, "mcpServers": [String]()] as [String: Any]])
    }

    /// Submit one user turn. The agent streams `session/update` notifications, then replies to
    /// THIS request's `id` with a `result` when the turn is complete.
    public static func sessionPrompt(id: Int, sessionId: String, text: String) -> String {
        line(["jsonrpc": "2.0", "id": id, "method": "session/prompt",
              "params": ["sessionId": sessionId,
                         "prompt": [["type": "text", "text": text]]] as [String: Any]])
    }

    /// Minimal ack for a server→client request, so the agent never deadlocks waiting on the client.
    public static func emptyResult(id: Int) -> String {
        line(["jsonrpc": "2.0", "id": id, "result": [String: String]()] as [String: Any])
    }

    private static func line(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return "\n" }
        return s + "\n"
    }

    // MARK: - Inbound (agent → client): classify one parsed line

    public enum Inbound: Equatable {
        /// Response to one of OUR requests. `sessionId` is set only for a `session/new` reply.
        case result(id: Int, sessionId: String?)
        case failure(id: Int, code: Int, message: String)
        /// A `session/update` notification (streamed turn content).
        case update(SessionUpdate)
        /// The agent is asking US something (has `id` + `method`); we must ack it.
        case serverRequest(id: Int, method: String)
        /// A notification we don't act on (announcements, fs index, etc.).
        case other
    }

    /// One streamed `session/update`. We care about visible text (answer/reasoning) and tool titles.
    public struct SessionUpdate: Equatable {
        public enum Kind: String {
            case message = "agent_message_chunk"
            case thought = "agent_thought_chunk"
            case toolCall = "tool_call"
            case toolCallUpdate = "tool_call_update"
            case plan
        }
        public let kind: Kind?
        public let text: String?
        public let title: String?
        public init(kind: Kind?, text: String?, title: String?) {
            self.kind = kind; self.text = text; self.title = title
        }
    }

    /// Classify one inbound JSON line. Returns nil for blank/unparseable lines.
    public static func parse(_ line: String) -> Inbound? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        let id: Int? = (obj["id"] as? Int) ?? (obj["id"] as? NSNumber)?.intValue

        if let id {
            if let err = obj["error"] as? [String: Any] {
                let code = (err["code"] as? Int) ?? (err["code"] as? NSNumber)?.intValue ?? 0
                return .failure(id: id, code: code, message: (err["message"] as? String) ?? "")
            }
            if obj.keys.contains("result") {
                let sid = (obj["result"] as? [String: Any])?["sessionId"] as? String
                return .result(id: id, sessionId: sid)
            }
            // id + method, no result/error ⇒ the agent is making a request of us.
            if let method = obj["method"] as? String {
                return .serverRequest(id: id, method: method)
            }
        }

        // Notification (method, no id).
        if let method = obj["method"] as? String {
            guard method == "session/update" || method == "x.ai/session/update" else { return .other }
            let update = (obj["params"] as? [String: Any])?["update"] as? [String: Any]
            let content = update?["content"] as? [String: Any]
            return .update(SessionUpdate(
                kind: (update?["sessionUpdate"] as? String).flatMap(SessionUpdate.Kind.init(rawValue:)),
                text: content?["text"] as? String,
                title: update?["title"] as? String))
        }
        return nil
    }
}
