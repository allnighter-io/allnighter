import Foundation
import AllnighterCore

/// One worker's full health picture for the Doctor UI: is the CLI present, what
/// version it reports, whether its smoke test passed, and — when something is
/// wrong — an exact, copy-able fix hint. This is where CLI churn is diagnosed:
/// a missing binary, a not-logged-in tool, or a bad flag fails *loudly* with a
/// remedy instead of silently dropping the worker.
public struct WorkerDiagnosis: Sendable, Equatable, Identifiable {
    public var workerId: String
    public var workerName: String
    public var driverId: String
    public var driverName: String
    public var kind: DriverKind
    /// `detectCommand` exited 0.
    public var present: Bool
    /// First line of `detectCommand` stdout (e.g. `claude 1.2.3`).
    public var version: String?
    public var health: WorkerHealth
    /// Copy-able remediation, nil when healthy.
    public var fixHint: String?

    public var id: String { workerId }

    public var isHealthy: Bool { health.isHealthy }

    public init(
        workerId: String,
        workerName: String,
        driverId: String,
        driverName: String,
        kind: DriverKind,
        present: Bool,
        version: String? = nil,
        health: WorkerHealth,
        fixHint: String? = nil
    ) {
        self.workerId = workerId
        self.workerName = workerName
        self.driverId = driverId
        self.driverName = driverName
        self.kind = kind
        self.present = present
        self.version = version
        self.health = health
        self.fixHint = fixHint
    }
}

/// Runs the full Doctor pass per worker: detect (presence + version) then smoke
/// test, and classifies the result into an actionable diagnosis. Pure over an
/// injected `CommandRunner`, so it is fully testable with `MockCommandRunner`.
public struct Doctor: Sendable {
    private let checker: WorkerHealthChecker

    public init(commandRunner: CommandRunner) {
        self.checker = WorkerHealthChecker(commandRunner: commandRunner)
    }

    /// Diagnoses every worker against its manifest in `registry`, concurrently.
    public func diagnoseAll(workers: [Worker], registry: DriverRegistry) async -> [WorkerDiagnosis] {
        await withTaskGroup(of: WorkerDiagnosis.self) { group in
            for worker in workers {
                let manifest = registry.manifest(for: worker)
                group.addTask { await self.diagnose(worker, manifest: manifest) }
            }
            var collected: [WorkerDiagnosis] = []
            for await diagnosis in group { collected.append(diagnosis) }
            // Restore panel order (TaskGroup completion order is nondeterministic).
            let order = Dictionary(uniqueKeysWithValues: workers.enumerated().map { ($1.id, $0) })
            return collected.sorted { (order[$0.workerId] ?? 0) < (order[$1.workerId] ?? 0) }
        }
    }

    public func diagnose(_ worker: Worker, manifest: DriverManifest?) async -> WorkerDiagnosis {
        guard let manifest else {
            return WorkerDiagnosis(
                workerId: worker.id,
                workerName: worker.displayName,
                driverId: worker.driverId,
                driverName: worker.driverId,
                kind: .headlessCLI,
                present: false,
                health: .unhealthy(reason: "no driver manifest '\(worker.driverId)'"),
                fixHint: "No driver manifest '\(worker.driverId)' is installed. Add it in Settings or restore the bundled driver."
            )
        }

        // Manual-paste workers have no CLI to detect or smoke-test.
        if manifest.kind == .manualPaste {
            return WorkerDiagnosis(
                workerId: worker.id,
                workerName: worker.displayName,
                driverId: manifest.id,
                driverName: manifest.displayName,
                kind: .manualPaste,
                present: true,
                health: .unknown,
                fixHint: "Manual worker — you paste its answer by hand. Nothing to install. Graduate it to a headless CLI by adding an `invoke` block to its driver manifest."
            )
        }

        let detect = await checker.detectVersion(manifest)
        if !detect.present {
            let command = manifest.invoke?.command ?? manifest.detectCommand ?? manifest.id
            let reason = detect.launchError ?? "`\(manifest.detectCommand ?? command)` did not succeed"
            return WorkerDiagnosis(
                workerId: worker.id,
                workerName: worker.displayName,
                driverId: manifest.id,
                driverName: manifest.displayName,
                kind: .headlessCLI,
                present: false,
                health: .unhealthy(reason: reason),
                fixHint: "Install `\(command)` or add it to your PATH, then re-run Doctor. Allnighter inherits your login shell's PATH. Tried: `\(manifest.detectCommand ?? command)`."
            )
        }

        let health = await checker.smokeTest(manifest, model: worker.modelLabel)
        let hint = Self.fixHint(for: health, worker: worker, manifest: manifest)
        return WorkerDiagnosis(
            workerId: worker.id,
            workerName: worker.displayName,
            driverId: manifest.id,
            driverName: manifest.displayName,
            kind: .headlessCLI,
            present: true,
            version: detect.version,
            health: health,
            fixHint: hint
        )
    }

    /// Maps a smoke-test outcome to a concrete remedy. Heuristic on the reason
    /// string, since CLIs report auth/quota failures in their own words.
    static func fixHint(for health: WorkerHealth, worker: Worker, manifest: DriverManifest) -> String? {
        guard case .unhealthy(let reason) = health else { return nil }
        let command = manifest.invoke?.command ?? manifest.id
        let lower = reason.lowercased()

        if lower.contains("log in") || lower.contains("login") || lower.contains("logged in")
            || lower.contains("auth") || lower.contains("unauthor") || lower.contains("api key")
            || lower.contains("credential") || lower.contains("sign in") {
            return "`\(command)` is installed but not authenticated. Log in from Terminal (e.g. `\(command) login`) using the subscription you already pay for, then re-run Doctor."
        }
        if lower.contains("timed out") || lower.contains("timeout") {
            return "`\(command)` launched but didn't respond in time. Check your network/quota and try once in Terminal: `\(command) -p \"hi\"`. Then re-run Doctor."
        }
        if lower.contains("did not return expected token") {
            return "`\(command)` responded but not with the expected token. The model label `\(worker.modelLabel)` or the smoke-test flags may be wrong — verify them in the driver manifest."
        }
        if lower.contains("model") || lower.contains("unknown flag") || lower.contains("usage")
            || lower.contains("unrecognized") || lower.contains("invalid") {
            return "`\(command)` rejected the request — likely the model label `\(worker.modelLabel)` or a CLI flag changed. Update this worker's driver manifest (`invoke.args` / `model`)."
        }
        return "`\(command)` smoke test failed: \(reason). Try the command once in Terminal, then update the driver manifest if its flags changed."
    }
}
