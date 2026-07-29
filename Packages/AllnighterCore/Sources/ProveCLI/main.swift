import Foundation
import AllnighterCore
import AllnighterEngine

/// Smallest live proof: AllnighterEngine -> real claude/grok subprocess.
/// Run: swift run prove-cli --package-path Packages/AllnighterCore
@main
enum ProveCLI {
    static func main() async {
        let registry = ModelCatalog.bundledRegistry()

        let prompt = "Reply with exactly the two words: hello world"
        let runner = WorkerInvokerFactory.makeWorkerInvoker()
        let cases: [(name: String, model: Model)] = [
            ("claude", Model(id: "prove_claude", displayName: "Claude", modelLabel: "sonnet", driverId: "claude_code")),
            ("grok", Model(id: "prove_grok", displayName: "Grok", modelLabel: "grok-build", driverId: "grok")),
            ("agy", Model(id: "prove_agy", displayName: "Gemini/Antigravity", modelLabel: "Gemini 3.6 Flash (Medium)", driverId: "antigravity")),
        ]

        var anyFailed = false
        for (name, model) in cases {
            guard let manifest = registry.manifest(id: model.driverId) else {
                fputs("[\(name)] FAIL — no manifest for \(model.driverId)\n", stderr)
                anyFailed = true
                continue
            }

            fputs("[\(name)] invoking \(manifest.invoke?.command ?? "?") ...\n", stderr)
            let outcome = await runner.collect(WorkerInvocation(model: model, manifest: manifest, prompt: prompt))
            let output = outcome.output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if outcome.status == .done, output.lowercased().contains("hello world") {
                print("[\(name)] OK — \(output)")
            } else {
                anyFailed = true
                fputs("[\(name)] FAIL — status=\(outcome.status) output=\(output) error=\(outcome.errorReason ?? "-")\n", stderr)
            }
        }

        exit(anyFailed ? 1 : 0)
    }
}
