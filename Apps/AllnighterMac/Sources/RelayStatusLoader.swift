import Foundation
import AllnighterCore
import AllnighterEngine

/// Read-side projection for Mac Delivery Loop thread chrome (ATL-S04). Mirrors
/// `LoopEngineCLI.runStatus` load + `LoopJSON.project` — never a GUI-only DTO and
/// never lifecycle inferred from thread turn prose.
enum RelayStatusLoader {
    static func loadLoopJSON(
        loopId: String,
        stateStore: LoopStateStore = LoopStateStore(),
        threadProjector: LoopThreadProjector? = LoopThreadProjector()
    ) -> LoopJSON? {
        guard let loaded = stateStore.load(id: loopId) else { return nil }
        let state = LoopCoordinator.reconcileOrphan(
            loaded, stateStore: stateStore, threadProjector: threadProjector, now: Date.init
        )
        let pmTurn = PMTurnStatusProjection.load(
            kind: .relay,
            subjectId: state.id,
            atPMBoundary: PMTurnStatusProjection.isRelayPMBoundary(state.status),
            store: PMTurnStore(loopsRootDirectory: stateStore.rootDirectory)
        )
        return LoopJSON.project(
            state,
            contractVersion: ContractRegistry.contractVersion,
            pmTurn: pmTurn.pmTurn,
            notes: pmTurn.notes,
            pmTurnDelivery: pmTurn.pmTurnDelivery
        )
    }

    static func statusCommand(loopId: String) -> String {
        "alln loop status \(loopId) --json"
    }
}
