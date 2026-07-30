import Foundation
import AllnighterCore
import AllnighterEngine

/// Read-side projection for Mac relay thread chrome (ATL-S04). Mirrors
/// `RelayCLI.runStatus` load + `RelayJSON.project` — never a GUI-only DTO and
/// never lifecycle inferred from thread turn prose.
enum RelayStatusLoader {
    static func loadRelayJSON(
        relayId: String,
        stateStore: RelayStateStore = RelayStateStore(),
        threadProjector: RelayThreadProjector? = RelayThreadProjector()
    ) -> RelayJSON? {
        guard let loaded = stateStore.load(id: relayId) else { return nil }
        let state = RelayCoordinator.reconcileOrphan(
            loaded, stateStore: stateStore, threadProjector: threadProjector, now: Date.init
        )
        let pmTurn = PMTurnStatusProjection.load(
            kind: .relay,
            subjectId: state.id,
            atPMBoundary: PMTurnStatusProjection.isRelayPMBoundary(state.status),
            store: PMTurnStore(relaysRootDirectory: stateStore.rootDirectory)
        )
        return RelayJSON.project(
            state,
            contractVersion: ContractRegistry.contractVersion,
            pmTurn: pmTurn.pmTurn,
            notes: pmTurn.notes,
            pmTurnDelivery: pmTurn.pmTurnDelivery
        )
    }

    static func statusCommand(relayId: String) -> String {
        "alln pair relay-status --relay \(relayId) --json"
    }
}
