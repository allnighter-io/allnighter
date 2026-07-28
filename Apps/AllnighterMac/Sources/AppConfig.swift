import Foundation
import AllnighterCore
import AllnighterEngine

enum ConfigurationSource: Sendable, Equatable {
    case bundleResources
    case embeddedDefaults
}

struct BundledConfiguration: Sendable {
    let models: [Model]
    let registry: DriverRegistry
    let modelsSource: ConfigurationSource
    let registrySource: ConfigurationSource

    var isBroken: Bool {
        models.isEmpty || registry.all.filter { $0.kind == .headlessCLI }.count < 4
    }
}

enum AppConfig {
    private static let minimumHeadlessDrivers = 4

    static func loadConfiguration() -> BundledConfiguration {
        let registry = ModelCatalog.bundledRegistry()
        let models = ModelCatalog.resolvedModels(registry: registry)
        let source: ConfigurationSource =
            headlessDriverCount(in: registry) >= minimumHeadlessDrivers ? .bundleResources : .embeddedDefaults
        return BundledConfiguration(
            models: models,
            registry: registry,
            modelsSource: source,
            registrySource: source
        )
    }

    static func loadDefaultModels() -> [Model] {
        loadConfiguration().models
    }

    static func loadDefaultRegistry() -> DriverRegistry {
        loadConfiguration().registry
    }

    static func builtInPresets(models: [Model]) -> [PanelPreset] {
        DefaultConfig.tieredPresets(models: models)
    }

    private static func headlessDriverCount(in registry: DriverRegistry) -> Int {
        registry.all.filter { $0.kind == .headlessCLI }.count
    }
}

enum LoginShell {
    static func resolvedPath() -> String? {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        // INTERACTIVE login shell (-lic): sources the user's `.zshrc` so PATH
        // entries set only there (bun/asdf/custom prefixes) are captured. Only
        // ever called from the explicit, user-initiated full setup probe
        // (runFullSetupProbe) — the founder accepts the one-time TCC prompt that
        // buys a complete PATH. NEVER call this on a launch/background path; cold
        // launch stays cache-only (Launch Authority TCC hotfix + Track 0.1).
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
