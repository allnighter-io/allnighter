import AgentOSCLI
import Foundation

/// Known next step for a capacity unknown. Same shape as `benchTally.nextAction`
/// (`kind` + `label` + `command`) — not a second vocabulary for the same idea.
///
/// Absence of a remedy is honest: spawn-failed / timeout / genuinely-never-checked
/// have no shell fix we can name without inventing one.
public enum CapacityUnknownRemedy {

    public static let configureOpenCodeGoCommand = "alln opencode-go configure --from-chrome"
    public static let configureBailianCommand = "alln bailian-token-plan configure --from-chrome"

    public static func nextAction(
        source: String,
        reason: CapacityUnknownReason,
        manifests: [DriverManifest] = ModelCatalog.bundledRegistry().all
    ) -> AgentSurfaceNextAction? {
        switch reason {
        case .notConfigured:
            return configureAction(for: source)
        case .notInstalled:
            return installAction(for: source, manifests: manifests)
        default:
            return nil
        }
    }

    public static func configureAction(for source: String) -> AgentSurfaceNextAction? {
        switch source {
        case CapacityAcquisition.dogfoodSourceId:
            return AgentSurfaceNextAction(
                kind: "configureCapacity",
                label: "Set up OpenCode Go",
                command: configureOpenCodeGoCommand
            )
        case CapacityAcquisition.bailianTokenPlanSourceId:
            return AgentSurfaceNextAction(
                kind: "configureCapacity",
                label: "Set up Qwen Token Plan",
                command: configureBailianCommand
            )
        default:
            return nil
        }
    }

    public static func installAction(
        for source: String,
        manifests: [DriverManifest]
    ) -> AgentSurfaceNextAction? {
        let driverId = driverId(forCapacitySource: source)
        let manifest = manifests.first { $0.id == driverId }
            ?? manifests.first { $0.id == source }
        let record = ToolProbeRecord(
            driverId: driverId,
            status: .notInstalled,
            lastProbeAt: .distantPast
        )
        return SetupRecoveryCopy.recovery(for: record, manifest: manifest).nextAction
    }

    /// Capacity source ids that do not match the driver catalog id 1:1.
    public static func driverId(forCapacitySource source: String) -> String {
        switch source {
        case "agy": return "antigravity"
        case CapacityAcquisition.dogfoodSourceId: return "opencode"
        case CapacityAcquisition.bailianTokenPlanSourceId: return "qwen"
        default: return source
        }
    }
}
