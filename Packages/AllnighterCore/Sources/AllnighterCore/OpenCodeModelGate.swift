import Foundation

/// Honest OpenCode Zen vs Go inventory for the model catalog and setup UI.
///
/// Catalog Go seats use `opencode-go/…` labels (OpenCode’s Go provider ids). They stay
/// off the bench until this Mac has an `opencode-go` API key in OpenCode’s auth store
/// — the same signal OpenCode’s TUI uses after `/connect`.
public enum OpenCodeModelGate {
    public static let driverId = "opencode"
    public static let goProviderID = "opencode-go"

    /// Subscribe / pricing front door.
    public static let goPlanURL = URL(string: "https://opencode.ai/go")!

    /// Usage math + model list (SSOT for the punchline numbers).
    public static let goDocsURL = URL(string: "https://opencode.ai/docs/go/")!

    /// Growth recommend — OpenCode’s published Go economics, sold hard.
    /// Numbers from https://opencode.ai/docs/go/ (monthly $60 allotment;
    /// DeepSeek V4 Pro ≈ 17,150 requests/mo at their typical-usage estimate).
    public static let goRecommendDetail =
        "$10/mo → $60 of coding-model usage (6×). OpenCode’s own math: ~17,000 DeepSeek V4 Pro calls a month — plus Qwen, GLM, MiniMax, and the rest of the Go lineup. First month is $5. Subscribe, connect the key, then tap Re-check."

    public static let goRecommendPrimaryTitle = "Get Go — $10/mo"

    public static let goConnectedDetail =
        "Go is connected on this Mac. Turn on the seats you want on the bench — Re-check reloads OpenCode’s local serve if it started before you subscribed."

    public static let goConnectedPrimaryTitle = "See Go plans"

    /// Test override — nil means read the live OpenCode auth file.
    nonisolated(unsafe) private static var goConnectedOverride: Bool?

    public static func overrideGoConnectedForTesting(_ value: Bool?) {
        goConnectedOverride = value
    }

    /// True when OpenCode’s auth store has an `opencode-go` API key entry.
    /// Does not read or log the secret — only the provider id key.
    public static func isGoConnected(authFileURL: URL? = nil) -> Bool {
        if let goConnectedOverride { return goConnectedOverride }
        let url = authFileURL ?? defaultAuthFileURL
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return root[goProviderID] != nil
    }

    public static var defaultAuthFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/auth.json")
    }

    public static func isGoCatalogLabel(_ modelLabel: String) -> Bool {
        modelLabel.hasPrefix("\(goProviderID)/")
    }

    public static func isZenCatalogLabel(_ modelLabel: String) -> Bool {
        modelLabel.hasPrefix("opencode/")
    }

    public static func isGoCatalogSeat(_ def: ModelDefinition) -> Bool {
        def.driverId == driverId && isGoCatalogLabel(def.modelLabel)
    }

    /// Repair / CLI model list: Zen + customs always; Go inventory only when connected.
    public static func visibleInCLIRoster(_ def: ModelDefinition) -> Bool {
        guard def.driverId == driverId else { return true }
        if isGoCatalogSeat(def) { return isGoConnected() }
        return true
    }
}
