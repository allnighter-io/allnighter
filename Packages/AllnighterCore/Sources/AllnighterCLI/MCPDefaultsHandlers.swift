import Foundation
import AllnighterCore
import AllnighterEngine

/// MCP projection of `alln defaults show`. Agents are readers of the Default model —
/// setting the Auto tier, rosters, and the substitution toggle is the owner's config
/// call (mirrors project approve/edit being human-only), so only the read is
/// projected. Same Core SSOT + `DefaultSettingsJSON` envelope as the CLI.
enum MCPDefaultsHandlers {
    enum Outcome: Error, Sendable {
        case success(String, summary: String)
        case toolError(ErrorEnvelope)
    }

    static func get(runtime: ToolRuntime) -> Outcome {
        let settings = DefaultModelSettingsPersistence().load()
        let proj = DefaultSettingsProjector.build(
            settings: settings,
            models: ModelsCLI.modelListJSON(runtime: runtime).models,
            contractVersion: ContractRegistry.contractVersion)
        let summary: String
        if let name = proj.auto.resolvedModelName {
            summary = "Auto → \(name)\(proj.auto.substituted ? " (substituted)" : "") · tier \(proj.defaultTier)"
        } else {
            summary = proj.auto.waitsMessage ?? "Auto waits · tier \(proj.defaultTier)"
        }
        return .success(AllnighterCLI.jsonString(proj), summary: summary)
    }
}
