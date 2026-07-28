import Foundation
import AllnighterCore

/// Built-in workers, driver manifests, and tiered presets as code, so the
/// `alln` CLI (RB6) runs standalone without the Mac app bundle, and the app
/// and CLI share one preset definition. User overrides under `Config/` win when
/// present (loaded by callers).
public enum DefaultConfig {
    /// Compatibility facade — derives from `ModelCatalog` (not a separate truth owner).
    public static var models: [Model] {
        ModelCatalog.resolvedModels(registry: registry)
    }

    public static var registry: DriverRegistry { ModelCatalog.bundledRegistry() }

    /// Compatibility facade for tests and manifest-focused call sites.
    public static var manifests: [DriverManifest] { registry.all }

    /// The tiered built-in panel presets (Fast / Quality / Diverse Team /
    /// Self-Double / Full + Founder's Six). Used by the legacy workflow engine.
    public static func tieredPresets(models: [Model]) -> [PanelPreset] {
        // Prefer strongest plan-writer (Claude Opus 5 over Antigravity Opus 4.6).
        let strongest = TeamAssembler.strongestPlanWriter(in: models) ?? models.first
        let planWriter = strongest?.id
        let analysisID = SynthesisInstructions.analysisID
        let planID = SynthesisInstructions.planID
        func config(_ depth: AnalysisDepth) -> SynthesisConfig {
            SynthesisConfig(analysisDepth: depth, planWriterModelId: planWriter, analysisProfileId: analysisID, planProfileId: planID)
        }
        func specs(_ ws: [Model]) -> [WorkerSpec] { ws.map { WorkerSpec(modelId: $0.id) } }

        let six = models
        let fastThree = Array(models.prefix(3))
        let diverseTeam = models.filter { $0.id != planWriter }

        var presets: [PanelPreset] = [
            PanelPreset.builtInDefault(models: six, analysisProfileId: analysisID, planProfileId: planID),
            PanelPreset(id: "preset_fast", displayName: "Fast Team", workerSpecs: specs(fastThree.isEmpty ? six : fastThree), synthesis: config(.combined), builtIn: true),
            PanelPreset(id: "preset_quality", displayName: "Quality Team", workerSpecs: specs(six), synthesis: config(.separate), builtIn: true),
            PanelPreset(id: "preset_budget", displayName: "Diverse Team", workerSpecs: specs(diverseTeam.isEmpty ? six : diverseTeam), synthesis: config(.separate), builtIn: true),
            PanelPreset(id: "preset_full", displayName: "Full Deliberation", workerSpecs: specs(six), synthesis: config(.separate), builtIn: true)
        ]
        if let strongest {
            presets.append(PanelPreset(id: "preset_self_double", displayName: "Self-Double", workerSpecs: [WorkerSpec(modelId: strongest.id, count: 3)], synthesis: config(.combined), builtIn: true))
        }
        return presets
    }
}
