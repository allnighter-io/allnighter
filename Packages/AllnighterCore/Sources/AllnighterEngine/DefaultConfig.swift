import Foundation
import AllnighterCore

/// Built-in workers, driver manifests, and tiered presets as code, so the
/// `allnighter` CLI (RB6) runs standalone without the Mac app bundle, and the app
/// and CLI share one preset definition. User overrides under `Config/` win when
/// present (loaded by callers).
public enum DefaultConfig {
    public static let workers: [Worker] = [
        Worker(id: "worker_chatgpt", displayName: "ChatGPT 5.5", modelLabel: "gpt-5.5", driverId: "codex", role: .member),
        Worker(id: "worker_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code", role: .both),
        Worker(id: "worker_sonnet", displayName: "Sonnet 4.6", modelLabel: "sonnet", driverId: "claude_code", role: .member),
        Worker(id: "worker_composer", displayName: "Composer 2.5", modelLabel: "grok-composer-2.5-fast", driverId: "grok", role: .member),
        Worker(id: "worker_gemini", displayName: "Gemini (Antigravity)", modelLabel: "Gemini 3.5 Flash (Medium)", driverId: "antigravity", role: .member),
        Worker(id: "worker_grok", displayName: "Grok Build", modelLabel: "grok-build", driverId: "grok", role: .member)
    ]

    private static let manifestJSON: [String] = [
        #"{"id":"claude_code","manifestVersion":1,"displayName":"Claude Code","kind":"headless_cli","detectCommand":"claude --version","smokeTestCommand":"claude -p \"Reply with the single token ALLNIGHTER_READY\" --model {{model}}","smokeTestExpect":"ALLNIGHTER_READY","invoke":{"command":"claude","args":["-p","{{prompt}}","--model","{{model}}"],"promptVia":"arg","env":{},"workingDir":null,"timeoutSeconds":300},"output":{"capture":"stdout","stripAnsi":true,"doneSignal":"exit_code","sentinel":null}}"#,
        #"{"id":"codex","manifestVersion":1,"displayName":"Codex / ChatGPT 5.5","kind":"headless_cli","detectCommand":"codex --version","smokeTestCommand":"codex exec --skip-git-repo-check --color never \"Reply with the single token ALLNIGHTER_READY\"","smokeTestExpect":"ALLNIGHTER_READY","invoke":{"command":"codex","args":["exec","--skip-git-repo-check","--sandbox","read-only","--color","never","-o","{{outputFile}}","{{prompt}}"],"promptVia":"arg","env":{},"workingDir":null,"timeoutSeconds":300},"output":{"capture":"file","stripAnsi":true,"doneSignal":"exit_code","sentinel":null}}"#,
        #"{"id":"grok","manifestVersion":1,"displayName":"Grok Build CLI","kind":"headless_cli","detectCommand":"grok --version","smokeTestCommand":"grok -p \"Reply with the single token ALLNIGHTER_READY\" -m {{model}} --output-format plain","smokeTestExpect":"ALLNIGHTER_READY","invoke":{"command":"grok","args":["-p","{{prompt}}","-m","{{model}}","--output-format","plain"],"promptVia":"arg","env":{},"workingDir":null,"timeoutSeconds":300},"output":{"capture":"stdout","stripAnsi":true,"doneSignal":"exit_code","sentinel":null}}"#,
        #"{"id":"antigravity","manifestVersion":1,"displayName":"Gemini (Antigravity CLI)","kind":"headless_cli","detectCommand":"agy --version","smokeTestCommand":"agy --print \"Reply with the single token ALLNIGHTER_READY\" --model \"{{model}}\" --dangerously-skip-permissions","smokeTestExpect":"ALLNIGHTER_READY","invoke":{"command":"agy","args":["--print","{{prompt}}","--model","{{model}}","--dangerously-skip-permissions"],"promptVia":"arg","env":{},"workingDir":null,"timeoutSeconds":300},"output":{"capture":"stdout","stripAnsi":true,"doneSignal":"exit_code","sentinel":null}}"#,
        #"{"id":"manual_paste","manifestVersion":1,"displayName":"Manual paste","kind":"manual_paste"}"#
    ]

    public static var manifests: [DriverManifest] {
        manifestJSON.compactMap { try? CoreJSON.decode(DriverManifest.self, from: Data($0.utf8)) }
    }

    public static var registry: DriverRegistry { DriverRegistry(manifests) }

    /// The tiered built-in presets (Fast / Quality / Diverse Panel / Self-Double / Full +
    /// Founder's Six). Shared by the app and the CLI.
    public static func tieredPresets(panel: [Worker]) -> [PanelPreset] {
        let judge = panel.first(where: \.canSynthesize)?.id ?? panel.first?.id
        let analysisID = SynthesisInstructions.analysisID
        let planID = SynthesisInstructions.planID
        func config(_ depth: AnalysisDepth) -> SynthesisConfig {
            SynthesisConfig(analysisDepth: depth, judgeWorkerId: judge, analysisProfileId: analysisID, planProfileId: planID)
        }
        func specs(_ ws: [Worker]) -> [PanelSeatSpec] { ws.map { PanelSeatSpec(workerId: $0.id) } }

        let six = panel
        let fastThree = Array(panel.prefix(3))
        let diversePanel = panel.filter { $0.id != judge }
        let strongest = panel.first(where: \.canSynthesize) ?? panel.first

        var presets: [PanelPreset] = [
            PanelPreset.builtInDefault(panel: six, analysisProfileId: analysisID, planProfileId: planID),
            PanelPreset(id: "preset_fast", displayName: "Fast Council", seats: specs(fastThree.isEmpty ? six : fastThree), synthesis: config(.combined), builtIn: true),
            PanelPreset(id: "preset_quality", displayName: "Quality Council", seats: specs(six), synthesis: config(.separate), builtIn: true),
            PanelPreset(id: "preset_budget", displayName: "Diverse Panel", seats: specs(diversePanel.isEmpty ? six : diversePanel), synthesis: config(.separate), builtIn: true),
            PanelPreset(id: "preset_full", displayName: "Full Deliberation", seats: specs(six), synthesis: config(.separate), builtIn: true)
        ]
        if let strongest {
            presets.append(PanelPreset(id: "preset_self_double", displayName: "Self-Double", seats: [PanelSeatSpec(workerId: strongest.id, count: 3)], synthesis: config(.combined), builtIn: true))
        }
        return presets
    }
}
