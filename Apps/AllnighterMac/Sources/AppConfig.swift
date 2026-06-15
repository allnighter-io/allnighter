import Foundation
import AllnighterCore
import AllnighterEngine

/// Loads bundled default configuration: the worker panel and the driver
/// manifests. These live in the app bundle's `Drivers/` resource folder and are
/// user-overridable later (Phase 05).
enum AppConfig {
    private static let panelFileName = "panel_default"

    static func loadDefaultPanel() -> [Worker] {
        guard let url = Bundle.main.url(
            forResource: panelFileName,
            withExtension: "json",
            subdirectory: "Drivers"
        ), let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? CoreJSON.decode([Worker].self, from: data)) ?? []
    }

    static func loadDefaultRegistry() -> DriverRegistry {
        guard let urls = Bundle.main.urls(
            forResourcesWithExtension: "json",
            subdirectory: "Drivers"
        ) else {
            return DriverRegistry()
        }
        let manifests = urls
            .filter { $0.deletingPathExtension().lastPathComponent != panelFileName }
            .compactMap { url -> DriverManifest? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? CoreJSON.decode(DriverManifest.self, from: data)
            }
        return DriverRegistry(manifests)
    }

    /// The tiered built-in presets (Phase 06), derived from the live panel so
    /// worker ids always match. Each names a real tradeoff; the judge defaults to
    /// the first worker that can synthesize (Opus) *by configuration*.
    static func builtInPresets(panel: [Worker]) -> [PanelPreset] {
        let judge = panel.first(where: \.canSynthesize)?.id ?? panel.first?.id
        let analysisID = SynthesisInstructions.analysisID
        let planID = SynthesisInstructions.planID

        func config(_ depth: AnalysisDepth) -> SynthesisConfig {
            SynthesisConfig(analysisDepth: depth, judgeWorkerId: judge, analysisProfileId: analysisID, planProfileId: planID)
        }
        func specs(_ workers: [Worker]) -> [PanelSeatSpec] { workers.map { PanelSeatSpec(workerId: $0.id) } }

        let six = panel
        let fastThree = Array(panel.prefix(3))
        // Budget/diverse: workers that are not the judge (cheaper bench + strong judge).
        let budget = panel.filter { $0.id != judge }
        let strongest = panel.first(where: \.canSynthesize) ?? panel.first

        var presets: [PanelPreset] = [
            PanelPreset.builtInDefault(panel: six, analysisProfileId: analysisID, planProfileId: planID),
            PanelPreset(id: "preset_fast", displayName: "Fast Council", seats: specs(fastThree.isEmpty ? six : fastThree), synthesis: config(.combined), builtIn: true),
            PanelPreset(id: "preset_quality", displayName: "Quality Council", seats: specs(six), synthesis: config(.separate), builtIn: true),
            PanelPreset(id: "preset_budget", displayName: "Budget / Diverse", seats: specs(budget.isEmpty ? six : budget), synthesis: config(.separate), builtIn: true),
            PanelPreset(id: "preset_full", displayName: "Full Deliberation", seats: specs(six), synthesis: config(.separate), builtIn: true)
        ]
        if let strongest {
            presets.append(PanelPreset(
                id: "preset_self_double", displayName: "Self-Double",
                seats: [PanelSeatSpec(workerId: strongest.id, count: 3)],
                synthesis: config(.combined), builtIn: true
            ))
        }
        return presets
    }
}

/// Bridges the user's login-shell `PATH` into this process so spawned CLIs
/// (`claude`, `grok`, …) resolve and authenticate exactly as they do in a
/// terminal. A GUI app otherwise launches with a minimal `PATH`.
enum LoginShell {
    static func resolvedPath() -> String? {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-lic", "printf %s \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    static func applyToProcessEnvironment() {
        if let path = resolvedPath() {
            setenv("PATH", path, 1)
        }
    }
}
