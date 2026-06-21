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
        #"{"id":"claude_code","manifestVersion":1,"displayName":"Claude Code","kind":"headless_cli","detectCommand":"claude --version","smokeTestCommand":"claude -p \"Reply with the single token ALLNIGHTER_READY\" --model {{model}}","smokeTestExpect":"ALLNIGHTER_READY","invoke":{"command":"claude","args":["-p","{{prompt}}","--model","{{model}}","{{effortArgs}}"],"promptVia":"arg","env":{},"workingDir":null,"timeoutSeconds":300,"effortFlag":{"flag":"--effort","levels":{"low":"low","med":"medium","high":"high"}}},"output":{"capture":"stdout","stripAnsi":true,"doneSignal":"exit_code","sentinel":null},"streaming":{"supported":true,"mode":"jsonl_stdout","args":["-p","{{prompt}}","--model","{{model}}","{{effortArgs}}","--output-format","stream-json","--include-partial-messages","--verbose","--permission-mode","bypassPermissions"],"partialOutput":true,"answerDeltaPaths":["$.event.delta.text"],"finalAnswerSource":"event","stripAnsi":true,"visibleReasoning":true},"session":{"continuity":"vendor_session","acquire":"set","firstTurnArgs":["-p","{{prompt}}","--model","{{model}}","{{effortArgs}}","--output-format","stream-json","--include-partial-messages","--verbose","--permission-mode","bypassPermissions","--session-id","{{sessionId}}"],"resumeArgs":["-p","{{prompt}}","--model","{{model}}","{{effortArgs}}","--output-format","stream-json","--include-partial-messages","--verbose","--permission-mode","bypassPermissions","--resume","{{sessionId}}"]}}"#,
        #"{"id":"codex","manifestVersion":1,"displayName":"Codex / ChatGPT","kind":"headless_cli","detectCommand":"codex --version","smokeTestCommand":"codex exec --skip-git-repo-check --color never \"Reply with the single token ALLNIGHTER_READY\"","smokeTestExpect":"ALLNIGHTER_READY","invoke":{"command":"codex","args":["exec","--skip-git-repo-check","--color","never","-m","{{model}}","{{effortArgs}}","-o","{{outputFile}}","{{prompt}}"],"promptVia":"arg","env":{},"workingDir":null,"timeoutSeconds":300,"effortFlag":{"flag":"-c","levels":{"low":"model_reasoning_effort=\"low\"","med":"model_reasoning_effort=\"medium\"","high":"model_reasoning_effort=\"high\""}}},"output":{"capture":"file","stripAnsi":true,"doneSignal":"exit_code","sentinel":null},"streaming":{"supported":true,"mode":"jsonl_stdout","args":["exec","--json","--skip-git-repo-check","--color","never","-m","{{model}}","{{effortArgs}}","-o","{{outputFile}}","{{prompt}}"],"partialOutput":false,"answerDeltaPaths":["$.item.text"],"finalAnswerSource":"output_file","stripAnsi":true,"visibleReasoning":false},"session":{"continuity":"vendor_session","acquire":"capture","resumeArgs":["exec","resume","{{sessionId}}","--json","--skip-git-repo-check","-m","{{model}}","-o","{{outputFile}}","{{prompt}}"],"capture":{"from":"stream_json","field":"thread_id"}}}"#,
        #"{"id":"grok","manifestVersion":1,"displayName":"Grok Build CLI","kind":"headless_cli","detectCommand":"grok --version","smokeTestCommand":"grok -p \"Reply with the single token ALLNIGHTER_READY\" -m {{model}} --output-format plain","smokeTestExpect":"ALLNIGHTER_READY","invoke":{"command":"grok","args":["-p","{{prompt}}","-m","{{model}}","--output-format","streaming-json","--always-approve","--no-wait-for-background","--no-subagents","--disable-web-search","--cwd","{{workingDir}}"],"promptVia":"arg","env":{},"workingDir":null,"timeoutSeconds":300},"output":{"capture":"stdout","stripAnsi":true,"doneSignal":"exit_code","sentinel":null},"streaming":{"supported":true,"mode":"jsonl_stdout","args":[],"partialOutput":true,"answerDeltaPaths":["$.data"],"finalAnswerSource":"parser_accumulator","stripAnsi":true,"visibleReasoning":false},"session":{"continuity":"vendor_session","acquire":"capture","resumeArgs":["-p","{{prompt}}","-m","{{model}}","--output-format","streaming-json","--always-approve","--no-wait-for-background","--no-subagents","--disable-web-search","--cwd","{{workingDir}}","--resume","{{sessionId}}"],"capture":{"from":"stream_json","field":"sessionId"}}}"#,
        #"{"id":"antigravity","manifestVersion":1,"displayName":"Antigravity","kind":"headless_cli","detectCommand":"agy --version","smokeTestCommand":"agy --print \"Reply with the single token ALLNIGHTER_READY\" --model \"{{model}}\" --dangerously-skip-permissions","smokeTestExpect":"ALLNIGHTER_READY","invoke":{"command":"agy","args":["--print","{{prompt}}","--model","{{model}}","--dangerously-skip-permissions"],"promptVia":"arg","env":{},"workingDir":null,"timeoutSeconds":300},"output":{"capture":"stdout","stripAnsi":true,"doneSignal":"exit_code","sentinel":null},"session":{"continuity":"prompt_context_only"}}"#,
        #"{"id":"cursor_agent","manifestVersion":1,"displayName":"Cursor Agent","kind":"headless_cli","detectCommand":"agent --version","smokeTestCommand":"agent -p --output-format text --model composer-2.5 --trust \"Reply with the single token ALLNIGHTER_READY\"","smokeTestExpect":"ALLNIGHTER_READY","invoke":{"command":"agent","args":["-p","--output-format","text","--model","{{model}}","--trust","--workspace","{{workingDir}}","{{prompt}}"],"promptVia":"arg","env":{},"workingDir":null,"timeoutSeconds":300},"output":{"capture":"stdout","stripAnsi":true,"doneSignal":"exit_code","sentinel":null},"streaming":{"supported":true,"mode":"jsonl_stdout","args":["-p","--output-format","stream-json","--stream-partial-output","--model","{{model}}","--trust","--workspace","{{workingDir}}","{{prompt}}"],"partialOutput":true,"answerDeltaPaths":["$.message.content[*].text"],"finalAnswerSource":"event","stripAnsi":true,"visibleReasoning":false},"setup":{"bins":["agent","cursor-agent"],"knownPaths":["~/.local/bin","/opt/homebrew/bin","/usr/local/bin"],"installHint":"Install Cursor CLI with `curl https://cursor.com/install -fsS | bash`, then run `agent` or `agent login` if needed.","docsURL":"https://cursor.com/docs/cli/installation","loginFlow":{"interactiveCommand":"agent login","instructions":"Run `agent login` and complete Cursor sign-in. If account-backed commands fail with Keychain errors, open Cursor once and retry setup.","authErrorPatterns":["SecItemCopyMatching failed","not authenticated","not signed in","login","unauthorized","401"],"docsURL":"https://cursor.com/docs/cli/using"},"headlessTrust":{"required":true,"cliFlag":"--trust","disclosure":"Cursor Agent workers run with --trust: the agent may edit files, run shell commands, and use tools in the project workspace without per-run approval. This is required for headless Code workers and is separate from Bench or model enablement."}},"session":{"continuity":"vendor_session","acquire":"capture","resumeArgs":["-p","--output-format","stream-json","--stream-partial-output","--model","{{model}}","--trust","--workspace","{{workingDir}}","--resume","{{sessionId}}","{{prompt}}"],"capture":{"from":"stream_json","field":"session_id"}}}"#,
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
