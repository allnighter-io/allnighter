import Foundation

/// Vendor-specific ACP spawn + handshake differences (Warm_Single_Lane_Chat §4b / Phase 4 cursor).
/// grok: `grok agent --model <m> --always-approve stdio`. cursor: `agent acp` + authenticate + model on session/new.
public enum ACPTransportProfile: Sendable, Equatable {
    case grok(model: String)
    case cursorAgent(model: String)

    /// argv after the executable (or after the `/usr/bin/env` shim).
    var spawnArgs: [String] {
        switch self {
        case let .grok(model):
            return ["agent", "--model", model, "--always-approve", "stdio"]
        case .cursorAgent:
            return ["acp"]
        }
    }

    var requiresAuthenticate: Bool {
        switch self {
        case .grok: return false
        case .cursorAgent: return true
        }
    }

    func sessionNewParams(cwd: String) -> [String: Any] {
        switch self {
        case .grok:
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
        default: return nil
        }
    }
}
