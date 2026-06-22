import Foundation

/// Agent Client Protocol (ACP) — JSON-RPC 2.0 message framing for driving warm ACP workers
/// (`grok agent stdio`, `agent acp`; see docs/phases/Warm_Single_Lane_Chat.md §4b).
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

    /// Cursor ACP: authenticate after initialize (uses existing `agent login` / CURSOR_API_KEY).
    public static func authenticate(id: Int, methodId: String = "cursor_login") -> String {
        line(["jsonrpc": "2.0", "id": id, "method": "authenticate",
              "params": ["methodId": methodId]])
    }

    /// Open a conversation bound to `cwd` (the real repo root). The agent's one-time working-tree
    /// index happens here (async — it does not block the response). Reply carries `sessionId`.
    public static func sessionNew(id: Int, cwd: String) -> String {
        sessionNew(id: id, params: ["cwd": cwd, "mcpServers": []])
    }

    public static func sessionNew(id: Int, params: [String: Any]) -> String {
        line(["jsonrpc": "2.0", "id": id, "method": "session/new", "params": params])
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

    /// Reply to `session/request_permission` by SELECTING one of the options the agent actually
    /// offered (matches headless `--force`/`--trust`). Sending an `optionId` the agent didn't offer
    /// can leave the turn hung, so callers pass an id from the request's own `options`.
    public static func permissionResult(id: Int, optionId: String) -> String {
        line(["jsonrpc": "2.0", "id": id,
              "result": ["outcome": ["outcome": "selected", "optionId": optionId]] as [String: Any]])
    }

    /// Fallback when the request carried no parseable options (older/edge cases).
    public static func permissionAllowOnce(id: Int) -> String {
        permissionResult(id: id, optionId: "allow-once")
    }

    /// Pick the best auto-approve option from what the agent OFFERED. Prefer allow-once, then
    /// allow-always, then any "allow"-ish option, then the first offered (anything beats hanging).
    public static func chooseAllowOption(_ options: [PermissionOption]) -> String? {
        func first(_ pred: (PermissionOption) -> Bool) -> String? { options.first(where: pred)?.optionId }
        func k(_ o: PermissionOption) -> String { (o.kind ?? "").lowercased() }
        return first { k($0) == "allow_once" }
            ?? first { k($0) == "allow_always" }
            ?? first { k($0).contains("allow") || $0.optionId.lowercased().contains("allow") }
            ?? options.first?.optionId
    }

    private static func line(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return "\n" }
        // JSONSerialization escapes `/` in method names; Grok ACP dispatches `session/new` only.
        return s.replacingOccurrences(of: "\\/", with: "/") + "\n"
    }

    // MARK: - Inbound (agent → client): classify one parsed line

    public enum Inbound: Equatable, Sendable {
        /// Response to one of OUR requests. `sessionId` is set only for a `session/new` reply.
        case result(id: Int, sessionId: String?)
        case failure(id: Int, code: Int, message: String)
        /// A `session/update` notification (streamed turn content).
        case update(SessionUpdate)
        /// The agent is asking US something (has `id` + `method`); we must ack it.
        case serverRequest(id: Int, method: String)
        /// `session/request_permission` — carries the options the agent offered so we reply with a
        /// valid `optionId` (a blind/wrong id can hang the turn).
        case permissionRequest(id: Int, options: [PermissionOption])
        /// A notification we don't act on (announcements, fs index, etc.).
        case other
    }

    /// One option offered by `session/request_permission`. `kind` (allow_once/allow_always/…) is the
    /// reliable signal; `optionId` is what we echo back in the selection.
    public struct PermissionOption: Equatable, Sendable {
        public let optionId: String
        public let kind: String?
        public init(optionId: String, kind: String?) { self.optionId = optionId; self.kind = kind }
    }

    /// One streamed `session/update`. We care about visible text (answer/reasoning) and tool titles.
    public struct SessionUpdate: Equatable, Sendable {
        public enum Kind: String, Sendable {
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
                if method == "session/request_permission" {
                    let raw = (obj["params"] as? [String: Any])?["options"] as? [[String: Any]] ?? []
                    let options = raw.compactMap { o -> PermissionOption? in
                        guard let oid = o["optionId"] as? String else { return nil }
                        return PermissionOption(optionId: oid, kind: o["kind"] as? String)
                    }
                    return .permissionRequest(id: id, options: options)
                }
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
