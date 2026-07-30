import Foundation
import Observation
import AllnighterCore
import AllnighterEngine

/// ATL-S04 — founder Stop from relay thread chrome. Routes through
/// `RelayCoordinator.stop` (same settlement as `pair relay stop`), never
/// `ProcessOwnershipSurface.kill` or `alln kill`.
@MainActor
@Observable
final class RelayStopController {
    private(set) var stoppingRelayIds: Set<String> = []
    private(set) var lastError: [String: String] = [:]

    private let makeCoordinator: (@escaping @Sendable () -> String) -> RelayCoordinator
    private let stateStore: RelayStateStore
    private let idFactory: @Sendable () -> String

    init(
        makeCoordinator: @escaping (@escaping @Sendable () -> String) -> RelayCoordinator = RelayGUIRuntime.makeCoordinator,
        stateStore: RelayStateStore = RelayStateStore(),
        idFactory: @escaping @Sendable () -> String = { RelayGUIRuntime.newRelayId() }
    ) {
        self.makeCoordinator = makeCoordinator
        self.stateStore = stateStore
        self.idFactory = idFactory
    }

    func isStopping(_ relayId: String) -> Bool { stoppingRelayIds.contains(relayId) }

    /// Stop is meaningful while the relay can still be abandoned — not after
    /// terminal `done`/`stopped` (idempotent CLI stop still exists; hide the button).
    func canStop(relayId: String) -> Bool {
        guard let state = stateStore.load(id: relayId) else { return false }
        switch state.status {
        case .running, .escalated, .awaitingPM:
            return true
        case .done, .stopped:
            return false
        }
    }

    @discardableResult
    func stop(relayId: String) -> Bool {
        guard canStop(relayId: relayId), !isStopping(relayId) else { return false }
        stoppingRelayIds.insert(relayId)
        lastError[relayId] = nil
        defer { stoppingRelayIds.remove(relayId) }
        let coordinator = makeCoordinator(idFactory)
        switch coordinator.stop(relayId: relayId) {
        case .success:
            return true
        case .failure(let refusal):
            lastError[relayId] = Self.stopFailureMessage(refusal)
            return false
        }
    }

    private static func stopFailureMessage(_ refusal: RelayCoordinator.StopRefusal) -> String {
        switch refusal {
        case .relayNotFound:
            return "This relay no longer exists."
        case .stopFailed(let detail):
            return "Could not stop this loop — \(detail)"
        }
    }
}
