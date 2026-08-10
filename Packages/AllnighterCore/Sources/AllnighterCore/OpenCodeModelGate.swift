import Foundation

/// Honest OpenCode Zen vs Go inventory for the model catalog and setup UI.
///
/// Catalog still lists historical Go seat rows with `opencode-go/…` labels (capacity-
/// source naming, not serve provider IDs). Those seats must not appear on-bench or
/// in the CLI repair roster until a real unlock path exists — absence of Go on the
/// local serve is not an inferred “you have Go.”
public enum OpenCodeModelGate {
    public static let driverId = "opencode"

    /// OpenCode’s marketing page for the Go plan (their offer, not Allnighter’s).
    public static let goPlanURL = URL(string: "https://opencode.ai/go")!

    /// Soft recommend — pricing attributed to OpenCode; never sold as Alln entitlement.
    public static let goRecommendDetail =
        "OpenCode Go adds more seats on this CLI — their plan is about $10/mo after a cheaper first month, with a pooled usage allotment. That’s OpenCode’s offer, not Alln’s."

    public static func isGoCatalogLabel(_ modelLabel: String) -> Bool {
        modelLabel.hasPrefix("opencode-go/")
    }

    public static func isZenCatalogLabel(_ modelLabel: String) -> Bool {
        modelLabel.hasPrefix("opencode/")
    }

    public static func isGoCatalogSeat(_ def: ModelDefinition) -> Bool {
        def.driverId == driverId && isGoCatalogLabel(def.modelLabel)
    }

    /// Repair / CLI model list: show Zen + customs; hide fictional Go inventory.
    public static func visibleInCLIRoster(_ def: ModelDefinition) -> Bool {
        guard def.driverId == driverId else { return true }
        return !isGoCatalogSeat(def)
    }
}
