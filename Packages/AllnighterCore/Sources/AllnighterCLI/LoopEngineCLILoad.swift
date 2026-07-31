import Foundation
import AllnighterCore
import AllnighterEngine

/// Shared relay load for `LoopEngineCLI` / `PilotCLI` — never maps decode failure to
/// `RELAY_NOT_FOUND`.
enum LoopEngineCLILoad {
    static func requireState(id: String, store: LoopStateStore) -> LoopState {
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

    static func requirePresence(id: String, store: LoopStateStore) {
        _ = requireState(id: id, store: store)
    }
}
