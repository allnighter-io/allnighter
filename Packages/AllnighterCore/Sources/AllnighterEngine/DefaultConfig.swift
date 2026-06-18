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

    private static let manifestJSON: [String] = [
        #"{"id":"claude_code","manifestVersion":1,"displayName":"Claude Code","kind":"headless_cli","detectCommand":"claude --version","smokeTestCommand":"claude -p \"Reply with the single token ALLNIGHTER_READY\" --model {{model}}","smokeTestExpect":"ALLNIGHTER_READY","invoke":{"command":"claude","args":["-p","{{prompt}}","--model","{{model}}"],"promptVia":"arg","env":{},"workingDir":null,"timeoutSeconds":300},"output":{"capture":"stdout","stripAnsi":true,"doneSignal":"exit_code","sentinel":null}}"#,
        #"{"id":"codex","manifestVersion":1,"displayName":"Codex / ChatGPT 5.5","kind":"headless_cli","detectCommand":"codex --version","smokeTestCommand":"codex exec --skip-git-repo-check --color never \"Reply with the single token ALLNIGHTER_READY\"","smokeTestExpect":"ALLNIGHTER_READY","invoke":{"command":"codex","args":["exec","--skip-git-repo-check","--color","never","-o","{{outputFile}}","{{prompt}}"],"promptVia":"arg","env":{},"workingDir":null,"timeoutSeconds":300},"output":{"capture":"file","stripAnsi":true,"doneSignal":"exit_code","sentinel":null}}"#,
        #"{"id":"grok","manifestVersion":1,"displayName":"Grok Build CLI","kind":"headless_cli","detectCommand":"grok --version","smokeTestCommand":"grok -p \"Reply with the single token ALLNIGHTER_READY\" -m {{model}} --output-format plain","smokeTestExpect":"ALLNIGHTER_READY","invoke":{"command":"grok","args":["-p","{{prompt}}","-m","{{model}}","--output-format","plain"],"promptVia":"arg","env":{},"workingDir":null,"timeoutSeconds":300},"output":{"capture":"stdout","stripAnsi":true,"doneSignal":"exit_code","sentinel":null}}"#,
        #"{"id":"antigravity","manifestVersion":1,"displayName":"Gemini (Antigravity CLI)","kind":"headless_cli","detectCommand":"agy --version","smokeTestCommand":"agy --print \"Reply with the single token ALLNIGHTER_READY\" --model \"{{model}}\" --dangerously-skip-permissions","smokeTestExpect":"ALLNIGHTER_READY","invoke":{"command":"agy","args":["--print","{{prompt}}","--model","{{model}}","--dangerously-skip-permissions"],"promptVia":"arg","env":{},"workingDir":null,"timeoutSeconds":300},"output":{"capture":"stdout","stripAnsi":true,"doneSignal":"exit_code","sentinel":null}}"#,
        #"{"id":"manual_paste","manifestVersion":1,"displayName":"Manual paste","kind":"manual_paste"}"#
    ]

    public static var manifests: [DriverManifest] {
        manifestJSON.compactMap { try? CoreJSON.decode(DriverManifest.self, from: Data($0.utf8)) }
    }

    public static var registry: DriverRegistry { DriverRegistry(manifests) }

    /// The tiered built-in panel presets (Fast / Quality / Diverse Team /
    /// Self-Double / Full + Founder's Six). Used by the legacy workflow engine.
    public static func tieredPresets(models: [Model]) -> [PanelPreset] {
        let planWriter = models.first(where: \.canWritePlan)?.id ?? models.first?.id
        let analysisID = SynthesisInstructions.analysisID
        let planID = SynthesisInstructions.planID
        func config(_ depth: AnalysisDepth) -> SynthesisConfig {
            SynthesisConfig(analysisDepth: depth, planWriterModelId: planWriter, analysisProfileId: analysisID, planProfileId: planID)
        }
        func specs(_ ws: [Model]) -> [WorkerSpec] { ws.map { WorkerSpec(modelId: $0.id) } }

        let six = models
        let fastThree = Array(models.prefix(3))
        let diverseTeam = models.filter { $0.id != planWriter }
        let strongest = models.first(where: \.canWritePlan) ?? models.first

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
