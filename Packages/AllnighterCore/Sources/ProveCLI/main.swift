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

        // Live design-image proof (the Activation Gate board item): generate ONE
        // real image via an image engine and confirm a valid local file lands.
        // Gated behind --design so the normal text proof never burns image quota.
        if CommandLine.arguments.contains("--design") {
            await proveDesign(driversDir: driversDir)
            return
        }

        let prompt = "Reply with exactly the two words: hello world"
        let runner = WorkerRunner(commandRunner: SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()))
        let cases: [(name: String, worker: Model)] = [
            ("claude", Model(id: "prove_claude", displayName: "Claude", modelLabel: "sonnet", driverId: "claude_code")),
            ("grok", Model(id: "prove_grok", displayName: "Grok", modelLabel: "grok-build", driverId: "grok")),
            ("agy", Model(id: "prove_agy", displayName: "Gemini/Antigravity", modelLabel: "Gemini 3.5 Flash (Medium)", driverId: "antigravity")),
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

    /// Generate one real design image per image-capable engine and confirm a valid
    /// local PNG/JPEG lands. The end-to-end Activation Gate "board" check at $0.
    private static func proveDesign(driversDir: URL) async {
        let which = CommandLine.arguments.first { ["grok", "codex", "antigravity"].contains($0) }
        let names = which.map { ["\($0).json"] } ?? ["grok.json", "antigravity.json", "codex.json"]
        let runner = DesignImageRunner(commandRunner: SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()))
        var anyFailed = false
        for name in names {
            let driverId = (name as NSString).deletingPathExtension
            guard let manifest = try? CoreJSON.decode(DriverManifest.self, from: Data(contentsOf: driversDir.appendingPathComponent(name))),
                  manifest.canGenerateImages else {
                fputs("[\(driverId)] SKIP — no imageGen manifest\n", stderr); continue
            }
            let modelLabel = driverId == "antigravity" ? "Gemini 3.5 Flash (Medium)" : (driverId == "grok" ? "grok-build" : "gpt-5.5")
            let worker = Model(id: "prove_\(driverId)", displayName: driverId, modelLabel: modelLabel, driverId: driverId)
            let seat = Worker(id: "prove_\(driverId)#0", modelId: worker.id, instanceIndex: 0, skillId: "minimal")
            let runDir = FileManager.default.temporaryDirectory.appendingPathComponent("alln-design-prove-\(driverId)")
            try? FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
            let request = DesignSeatRequest(
                userPrompt: "a clean mobile login screen for a coffee app",
                personaId: "minimal", personaDirection: SkillCatalog.designDirection(for: "minimal"),
                targetShape: .mobile)
            fputs("[\(driverId)] generating image (\(manifest.imageGen!.arrival.rawValue)) — this hits the real engine…\n", stderr)
            let option = await runner.run(seat: seat, worker: worker, manifest: manifest, request: request, runDir: runDir)
            if option.status == .done, let rel = option.imagePath {
                let path = runDir.appendingPathComponent(rel).path
                let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
                print("[\(driverId)] OK — \(path) (\(size ?? 0) bytes), session=\(option.sessionId ?? "-")")
            } else {
                anyFailed = true
                fputs("[\(driverId)] FAIL — status=\(option.status) reason=\(option.failureReason ?? "-")\n", stderr)
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
