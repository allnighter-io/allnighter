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
    private static let teamFileName = "team_default"
    private static let minimumHeadlessDrivers = 4

    static func loadConfiguration() -> BundledConfiguration {
        let bundleModels = loadModelsFromBundle()
        let bundleRegistry = loadRegistryFromBundle()

        let models: [Model]
        let modelsSource: ConfigurationSource
        if let bundleModels, !bundleModels.isEmpty {
            models = bundleModels
            modelsSource = .bundleResources
        } else if !DefaultConfig.models.isEmpty {
            models = DefaultConfig.models
            modelsSource = .embeddedDefaults
        } else {
            models = []
            modelsSource = .embeddedDefaults
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
            models: models,
            registry: registry,
            modelsSource: modelsSource,
            registrySource: registrySource
        )
    }

    static func loadDefaultModels() -> [Model] {
        loadConfiguration().models
    }

    static func loadDefaultRegistry() -> DriverRegistry {
        loadConfiguration().registry
    }

    static func builtInPresets(models: [Model]) -> [TeamPreset] {
        DefaultConfig.tieredPresets(models: models)
    }

    private static func loadModelsFromBundle() -> [Model]? {
        for subdirectory in bundleLookupSubdirectories {
            guard let url = Bundle.main.url(
                forResource: teamFileName,
                withExtension: "json",
                subdirectory: subdirectory
            ), let data = try? Data(contentsOf: url),
                  let models = try? CoreJSON.decode([Model].self, from: data),
                  !models.isEmpty else { continue }
            return models
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
                .filter { $0.deletingPathExtension().lastPathComponent != teamFileName }
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

    private static let bundleLookupSubdirectories: [String?] = [nil, "Drivers"]

    private static func headlessDriverCount(in registry: DriverRegistry) -> Int {
        registry.all.filter { $0.kind == .headlessCLI }.count
    }
}

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
