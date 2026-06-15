import Foundation
import AllnighterCore
import AllnighterEngine

/// Where the live panel/registry came from — bundle JSON or embedded `DefaultConfig`.
enum ConfigurationSource: Sendable, Equatable {
    case bundleResources
    case embeddedDefaults
}

/// Result of loading the default panel and driver registry.
struct BundledConfiguration: Sendable {
    let panel: [Worker]
    let registry: DriverRegistry
    let panelSource: ConfigurationSource
    let registrySource: ConfigurationSource

    /// True when neither bundle nor embedded defaults could supply a usable config.
    var isBroken: Bool {
        panel.isEmpty || registry.all.filter { $0.kind == .headlessCLI }.count < 4
    }
}

/// Loads bundled default configuration: the worker panel and the driver
/// manifests. XcodeGen ships `Resources/Drivers` as a flattened group (no
/// `Drivers/` subfolder in the `.app`), so lookups try the bundle root first,
/// then `Drivers/`. When the bundle is empty, `DefaultConfig` is the safety net
/// (real manifests — not a one-worker fake).
enum AppConfig {
    private static let panelFileName = "panel_default"
    private static let minimumHeadlessDrivers = 4

    static func loadConfiguration() -> BundledConfiguration {
        let bundlePanel = loadPanelFromBundle()
        let bundleRegistry = loadRegistryFromBundle()

        let panel: [Worker]
        let panelSource: ConfigurationSource
        if let bundlePanel, !bundlePanel.isEmpty {
            panel = bundlePanel
            panelSource = .bundleResources
        } else if !DefaultConfig.workers.isEmpty {
            panel = DefaultConfig.workers
            panelSource = .embeddedDefaults
        } else {
            panel = []
            panelSource = .embeddedDefaults
        }

        let registry: DriverRegistry
        let registrySource: ConfigurationSource
        if headlessDriverCount(in: bundleRegistry) >= minimumHeadlessDrivers {
            registry = bundleRegistry
            registrySource = .bundleResources
        } else if headlessDriverCount(in: DefaultConfig.registry) >= minimumHeadlessDrivers {
            registry = DefaultConfig.registry
            registrySource = .embeddedDefaults
        } else {
            registry = DriverRegistry()
            registrySource = .embeddedDefaults
        }

        return BundledConfiguration(
            panel: panel,
            registry: registry,
            panelSource: panelSource,
            registrySource: registrySource
        )
    }

    static func loadDefaultPanel() -> [Worker] {
        loadConfiguration().panel
    }

    static func loadDefaultRegistry() -> DriverRegistry {
        loadConfiguration().registry
    }

    /// The tiered built-in presets (Phase 06), derived from the live panel so
    /// worker ids always match. Each names a real tradeoff; the judge defaults to
    /// the first worker that can synthesize (Opus) *by configuration*.
    static func builtInPresets(panel: [Worker]) -> [PanelPreset] {
        DefaultConfig.tieredPresets(panel: panel)
    }

    // MARK: - Bundle loading (subdir-free first)

    private static func loadPanelFromBundle() -> [Worker]? {
        for subdirectory in bundleLookupSubdirectories {
            guard let url = Bundle.main.url(
                forResource: panelFileName,
                withExtension: "json",
                subdirectory: subdirectory
            ), let data = try? Data(contentsOf: url),
                  let panel = try? CoreJSON.decode([Worker].self, from: data),
                  !panel.isEmpty else { continue }
            return panel
        }
        return nil
    }

    private static func loadRegistryFromBundle() -> DriverRegistry {
        for subdirectory in bundleLookupSubdirectories {
            guard let urls = Bundle.main.urls(
                forResourcesWithExtension: "json",
                subdirectory: subdirectory
            ) else { continue }
            let manifests = urls
                .filter { $0.deletingPathExtension().lastPathComponent != panelFileName }
                .compactMap { url -> DriverManifest? in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? CoreJSON.decode(DriverManifest.self, from: data)
                }
            if !manifests.isEmpty {
                return DriverRegistry(manifests)
            }
        }
        return DriverRegistry()
    }

    /// Flattened XcodeGen resources land at the bundle root; a folder reference
    /// would use `Drivers/`. Try root first so Cause 0 cannot recur silently.
    private static let bundleLookupSubdirectories: [String?] = [nil, "Drivers"]

    private static func headlessDriverCount(in registry: DriverRegistry) -> Int {
        registry.all.filter { $0.kind == .headlessCLI }.count
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
