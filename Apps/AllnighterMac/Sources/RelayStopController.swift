import Foundation
import Observation
import AllnighterCore
import AllnighterEngine

/// ATL-S04 — founder Stop from Delivery Loop thread chrome. Routes through
/// `LoopCoordinator.stop` (same settlement as `alln loop stop`), never
/// `ProcessOwnershipSurface.kill` or `alln kill`.
@MainActor
@Observable
final class RelayStopController {
    private(set) var stoppingRelayIds: Set<String> = []
    private(set) var lastError: [String: String] = [:]

    private let makeCoordinator: (@escaping @Sendable () -> String) -> LoopCoordinator
    private let stateStore: LoopStateStore
    private let idFactory: @Sendable () -> String

    init(
        makeCoordinator: @escaping (@escaping @Sendable () -> String) -> LoopCoordinator = RelayGUIRuntime.makeCoordinator,
        stateStore: LoopStateStore = LoopStateStore(),
        idFactory: @escaping @Sendable () -> String = { RelayGUIRuntime.newRelayId() }
    ) {
        self.makeCoordinator = makeCoordinator
        self.stateStore = stateStore
        self.idFactory = idFactory
    }

    func isStopping(_ loopId: String) -> Bool { stoppingRelayIds.contains(loopId) }

    /// Stop is meaningful while the relay can still be abandoned — not after
    /// terminal `done`/`stopped` (idempotent CLI stop still exists; hide the button).
    func canStop(loopId: String) -> Bool {
        guard let state = stateStore.load(id: loopId) else { return false }
        switch state.status {
        case .running, .escalated, .awaitingPM:
            return true
        case .done, .stopped:
            return false
        }
    }

    @discardableResult
    func stop(loopId: String) -> Bool {
        guard canStop(loopId: loopId), !isStopping(loopId) else { return false }
        stoppingRelayIds.insert(loopId)
        lastError[loopId] = nil
        defer { stoppingRelayIds.remove(loopId) }
        let coordinator = makeCoordinator(idFactory)
        switch coordinator.stop(loopId: loopId) {
        case .success:
            return true
        case .failure(let refusal):
            lastError[loopId] = Self.stopFailureMessage(refusal)
            return false
        }
    }

    private static func stopFailureMessage(_ refusal: LoopCoordinator.StopRefusal) -> String {
        switch refusal {
        case .relayNotFound:
            return "This relay no longer exists."
        case .stopFailed(let detail):
            return "Could not stop this loop — \(detail)"
        }
    }
}
