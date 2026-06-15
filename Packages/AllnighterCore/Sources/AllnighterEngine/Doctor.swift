import Foundation
import AllnighterCore

/// One model's full health picture for Doctor: CLI presence, version, smoke test,
/// and an actionable fix hint when something is wrong.
public struct ModelDiagnosis: Sendable, Equatable, Identifiable {
    public var modelId: String
    public var modelName: String
    public var driverId: String
    public var driverName: String
    public var kind: DriverKind
    public var present: Bool
    public var version: String?
    public var health: ModelHealth
    public var fixHint: String?

    public var id: String { modelId }
    public var isHealthy: Bool { health.isHealthy }

    public init(
        modelId: String,
        modelName: String,
        driverId: String,
        driverName: String,
        kind: DriverKind,
        present: Bool,
        version: String? = nil,
        health: ModelHealth,
        fixHint: String? = nil
    ) {
        self.modelId = modelId
        self.modelName = modelName
        self.driverId = driverId
        self.driverName = driverName
        self.kind = kind
        self.present = present
        self.version = version
        self.health = health
        self.fixHint = fixHint
    }
}

public struct Doctor: Sendable {
    private let checker: ModelHealthChecker

    public init(commandRunner: CommandRunner) {
        self.checker = ModelHealthChecker(commandRunner: commandRunner)
    }

    public func diagnoseAll(models: [Model], registry: DriverRegistry) async -> [ModelDiagnosis] {
        await withTaskGroup(of: ModelDiagnosis.self) { group in
            for model in models {
                let manifest = registry.manifest(for: model)
                group.addTask { await self.diagnose(model, manifest: manifest) }
            }
            var collected: [ModelDiagnosis] = []
            for await diagnosis in group { collected.append(diagnosis) }
            let order = Dictionary(uniqueKeysWithValues: models.enumerated().map { ($1.id, $0) })
            return collected.sorted { (order[$0.modelId] ?? 0) < (order[$1.modelId] ?? 0) }
        }
    }

    public func diagnose(_ model: Model, manifest: DriverManifest?) async -> ModelDiagnosis {
        guard let manifest else {
            return ModelDiagnosis(
                modelId: model.id,
                modelName: model.displayName,
                driverId: model.driverId,
                driverName: model.driverId,
                kind: .headlessCLI,
                present: false,
                health: .unhealthy(reason: "no driver manifest '\(model.driverId)'"),
                fixHint: "No driver manifest '\(model.driverId)' is installed. Add it in Settings or restore the bundled driver."
            )
        }

        if manifest.kind == .manualPaste {
            return ModelDiagnosis(
                modelId: model.id,
                modelName: model.displayName,
                driverId: manifest.id,
                driverName: manifest.displayName,
                kind: .manualPaste,
                present: true,
                health: .unknown,
                fixHint: "Manual model — paste its answer by hand. Graduate it to a headless CLI by adding an `invoke` block to its driver manifest."
            )
        }

        let detect = await checker.detectVersion(manifest)
        if !detect.present {
            let command = manifest.invoke?.command ?? manifest.detectCommand ?? manifest.id
            let reason = detect.launchError ?? "`\(manifest.detectCommand ?? command)` did not succeed"
            return ModelDiagnosis(
                modelId: model.id,
                modelName: model.displayName,
                driverId: manifest.id,
                driverName: manifest.displayName,
                kind: .headlessCLI,
                present: false,
                health: .unhealthy(reason: reason),
                fixHint: "Install `\(command)` or add it to your PATH, then re-run Doctor."
            )
        }

        let health = await checker.smokeTest(manifest, model: model.modelLabel)
        let hint = Self.fixHint(for: health, model: model, manifest: manifest)
        return ModelDiagnosis(
            modelId: model.id,
            modelName: model.displayName,
            driverId: manifest.id,
            driverName: manifest.displayName,
            kind: .headlessCLI,
            present: true,
            version: detect.version,
            health: health,
            fixHint: hint
        )
    }

    static func fixHint(for health: ModelHealth, model: Model, manifest: DriverManifest) -> String? {
        guard case .unhealthy(let reason) = health else { return nil }
        let command = manifest.invoke?.command ?? manifest.id
        let lower = reason.lowercased()

        if lower.contains("log in") || lower.contains("login") || lower.contains("auth")
            || lower.contains("credential") || lower.contains("sign in") {
            return "`\(command)` is installed but not authenticated. Log in from Terminal, then re-run Doctor."
        }
        if lower.contains("timed out") || lower.contains("timeout") {
            return "`\(command)` launched but didn't respond in time. Check network/quota and try once in Terminal."
        }
        if lower.contains("did not return expected token") {
            return "`\(command)` responded but not with the expected token. Verify model label `\(model.modelLabel)` in the driver manifest."
        }
        return "`\(command)` smoke test failed: \(reason). Try the command once in Terminal, then update the driver manifest if flags changed."
    }
}
