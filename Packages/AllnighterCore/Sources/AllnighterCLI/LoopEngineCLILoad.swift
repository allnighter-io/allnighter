import Foundation
import AllnighterCore
import AllnighterEngine

/// Shared relay load for `RelayCLI` / `PilotCLI` — never maps decode failure to
/// `RELAY_NOT_FOUND`.
enum RelayCLILoad {
    static func requireState(id: String, store: RelayStateStore) -> RelayState {
        switch store.loadResult(id: id) {
        case .success(let state):
            return state
        case .failure(.notFound):
            AllnighterCLI.fail(code: "RELAY_NOT_FOUND", message: "relay not found: \(id)")
        case .failure(.decodeFailed(let detail)):
            AllnighterCLI.fail(
                code: "RELAY_STATE_DECODE_FAILED",
                message: detail.agentMessage,
                supportDir: AllnighterCLI.effectiveSupportDir()
            )
        }
    }

    static func requirePresence(id: String, store: RelayStateStore) {
        _ = requireState(id: id, store: store)
    }
}
