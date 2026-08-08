import Foundation
import AllnighterCore

/// Assembles Boost eligibility from durable capacity history (+ optional live windows).
/// Closed history cycles still count — they prove the CLI has a short rolling window.
public enum BoostEligibilityProbe {
    public static func eligibleSeedDriverIds(
        historyStore: CapacityHistoryStore = CapacityHistoryStore(),
        liveWindows: [CapacityWindow] = [],
        now: Date = Date()
    ) -> Set<String> {
        _ = now
        var scopes: [String: Set<CapacityWindowScope>] = [:]
        for sourceId in BoostSeatCatalog.capacitySourceIds {
            for record in historyStore.load(sourceId: sourceId) {
                scopes[sourceId, default: []].insert(record.scope)
            }
        }
        for window in liveWindows where window.unknownReason == nil {
            scopes[window.source, default: []].insert(window.scope)
        }
        return BoostSeatEligibility.eligibleSeedDriverIds(
            evidencedScopesByCapacitySource: scopes
        )
    }
}
