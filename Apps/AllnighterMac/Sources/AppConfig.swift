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

    /// The built-in six-worker preset, derived from the live panel so its worker
    /// ids always match. The synthesizer defaults to Opus *by configuration*
    /// (first worker that can synthesize), not a hardcoded code path.
    static func builtInPanelPreset(panel: [Worker]) -> PanelPreset {
        PanelPreset.builtInDefault(
            panel: panel,
            instructionPresetId: SynthesisInstructions.defaultID
        )
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
