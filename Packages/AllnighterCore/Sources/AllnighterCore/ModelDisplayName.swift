import Foundation

/// Owner-facing model labels. Append a source CLI in parentheses only when the
/// seat runs on a non-default driver for its reasoning family — e.g.
/// `ChatGPT 5.6 Sol` on Codex (default) vs `ChatGPT 5.6 Sol (Cursor)` on Cursor.
public enum ModelDisplayName {
    private static let knownCLILabels = ["Claude", "Codex", "Cursor", "Grok", "Antigravity", "Kimi"]

    /// Strip a legacy ` (CLI)` suffix so catalog migrations stay idempotent.
    public static func canonicalBaseName(_ name: String) -> String {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for label in knownCLILabels where trimmed.hasSuffix(" (\(label))") {
            trimmed = String(trimmed.dropLast(label.count + 3))
            break
        }
        return trimmed
    }

    /// Short parenthetical label for a source CLI.
    public static func driverLabel(driverId: String) -> String {
        switch driverId {
        case "claude_code": return "Claude"
        case "codex": return "Codex"
        case "cursor_agent", "cursor": return "Cursor"
        case "grok": return "Grok"
        case "antigravity": return "Antigravity"
        case "kimi": return "Kimi"
        default:
            return driverId.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// The home driver for a built-in seat's reasoning family. Customs use their
    /// sole driver as home (never suffixed). Intentionally does not call
    /// `ModelCatalog` — this runs while the catalog is still materializing.
    public static func defaultDriverId(for modelId: ModelID, driverId: String) -> String {
        switch modelId {
        case "model_fable", "model_opus", "model_sonnet",
             "model_agy_opus", "model_agy_sonnet",
             "model_cursor_fable", "model_cursor_opus", "model_cursor_sonnet":
            return "claude_code"
        case "model_chatgpt", "model_chatgpt_sol", "model_chatgpt_terra",
             "model_chatgpt_54", "model_chatgpt_54_mini", "model_codex_spark":
            return "codex"
        case "model_grok", "model_composer":
            return "grok"
        case "model_cursor_grok_45":
            return "cursor_agent"
        case "model_gemini", "model_gemini_pro", "model_agy_gptoss":
            return "antigravity"
        case "model_kimi_k3", "model_kimi_k27", "model_kimi_k27_hs":
            return "kimi"
        case "model_cursor_auto", "model_cursor_composer_25", "model_cursor_composer_25_fast":
            return "cursor_agent"
        default:
            return driverId
        }
    }

    public static func isDefaultDriver(modelId: ModelID, driverId: String) -> Bool {
        driverId == defaultDriverId(for: modelId, driverId: driverId)
    }

    public static func format(baseName: String, modelId: ModelID, driverId: String) -> String {
        let base = canonicalBaseName(baseName)
        guard !isDefaultDriver(modelId: modelId, driverId: driverId) else { return base }
        return "\(base) (\(driverLabel(driverId: driverId)))"
    }

    /// Second-line source label under the model name: friendly home CLI when default
    /// (`Codex`), raw `driverId` when the seat is on an alternate source (`cursor_agent`).
    public static func driverSubtitle(modelId: ModelID, driverId: String) -> String {
        isDefaultDriver(modelId: modelId, driverId: driverId)
            ? driverLabel(driverId: driverId) : driverId
    }
}
