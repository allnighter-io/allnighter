import Foundation

/// Vendor-specific ACP spawn + handshake differences (Warm_Single_Lane_Chat §4b / Phase 4 cursor).
/// grok: `grok agent --model <m> --always-approve stdio`. cursor: `agent acp` + authenticate + model on session/new.
public enum ACPTransportProfile: Sendable, Equatable {
    case grok(model: String)
    case cursorAgent(model: String)
    case codex(model: String)   // codex app-server dialect (not ACP — see CodexSession)

    /// argv after the executable (or after the `/usr/bin/env` shim).
    var spawnArgs: [String] {
        switch self {
        case let .grok(model):
            return ["agent", "--model", model, "--always-approve", "stdio"]
        case .cursorAgent:
            return ["acp"]
        case .codex:
            return ["app-server"]   // model goes in thread/start, not the spawn line
        }
    }

    /// ACP-only (grok/cursor). Codex never reaches this — it uses `CodexSession`.
    var requiresAuthenticate: Bool {
        switch self {
        case .cursorAgent: return true
        case .grok, .codex: return false
        }
    }

    func sessionNewParams(cwd: String) -> [String: Any] {
        switch self {
        case .grok, .codex:
            return ["cwd": cwd, "mcpServers": []]
        case let .cursorAgent(model):
            return ["cwd": cwd, "mcpServers": [], "model": model]
        }
    }

    /// Map a warm-capable driver manifest id + resolved model label to a profile.
    public static func make(sourceId: String, model: String) -> ACPTransportProfile? {
        switch sourceId {
        case "grok": return .grok(model: model)
        case "cursor_agent": return .cursorAgent(model: model)
        case "codex": return .codex(model: model)
        default: return nil
        }
    }

    /// Build the dialect-specific session driver over a (already-spawned) transport.
    public func makeDriver(transport: ACPTransport) -> any WarmSessionDriver {
        switch self {
        case .grok, .cursorAgent:
            return ACPSession(transport: transport, profile: self)
        case let .codex(model):
            return CodexSession(transport: transport, model: model)
        }
    }
}
