import Foundation
import AllnighterCore
import AllnighterEngine

/// Smallest live proof: AllnighterEngine -> real claude/grok subprocess.
/// Run: swift run prove-cli --package-path Packages/AllnighterCore
@main
enum ProveCLI {
    static func main() async {
        let driversDir = driversDirectory()
        guard let driversDir else {
            fputs("error: could not find Apps/AllnighterMac/Resources/Drivers\n", stderr)
            exit(1)
        }

        let registry: DriverRegistry
        do {
            let manifestFiles = ["claude_code.json", "grok.json", "antigravity.json"]
            let manifests = try manifestFiles.map { name in
                let url = driversDir.appendingPathComponent(name)
                return try CoreJSON.decode(DriverManifest.self, from: Data(contentsOf: url))
            }
            registry = DriverRegistry(manifests)
        } catch {
            fputs("error: load drivers: \(error)\n", stderr)
            exit(1)
        }

        let prompt = "Reply with exactly the two words: hello world"
        let runner = WorkerRunner(commandRunner: SubprocessCommandRunner())
        let cases: [(name: String, worker: Worker)] = [
            ("claude", Worker(id: "prove_claude", displayName: "Claude", modelLabel: "sonnet", driverId: "claude_code")),
            ("grok", Worker(id: "prove_grok", displayName: "Grok", modelLabel: "grok-build", driverId: "grok")),
            ("agy", Worker(id: "prove_agy", displayName: "Gemini/Antigravity", modelLabel: "gemini-flash", driverId: "antigravity")),
        ]

        var anyFailed = false
        for (name, worker) in cases {
            guard let manifest = registry.manifest(id: worker.driverId) else {
                fputs("[\(name)] FAIL — no manifest for \(worker.driverId)\n", stderr)
                anyFailed = true
                continue
            }

            fputs("[\(name)] invoking \(manifest.invoke?.command ?? "?") ...\n", stderr)
            let outcome = await runner.invoke(worker: worker, manifest: manifest, prompt: prompt)
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

    private static func driversDirectory() -> URL? {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent("Apps/AllnighterMac/Resources/Drivers"),
            cwd.appendingPathComponent("../../Apps/AllnighterMac/Resources/Drivers").standardized,
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
