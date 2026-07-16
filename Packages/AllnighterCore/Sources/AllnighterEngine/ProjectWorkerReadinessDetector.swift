import Foundation
import AllnighterCore

/// PRJ-S05: detects whether a worker can safely run inside a specific Project
/// root right now. Global setup is not Project readiness — a CLI installed and
/// signed in globally may still be untrusted, unauthorized, or unusable in a
/// given folder.
///
/// This detector runs ONLY a driver-declared, bounded, non-mutating safe probe
/// (`DriverManifest.projectProbe`). It never accepts trust prompts, logs in,
/// writes vendor authorization, approves terms, changes permissions, or
/// configures a Project for a CLI. When a driver does not declare a safe probe
/// the result is `unsafeToProbe` — never a guessed `ready`. Probe output is
/// classified only into the canonical `WorkerReadinessStatus` list.
public struct ProjectWorkerReadinessDetector: Sendable {
    private let runner: CommandRunner

    public init(runner: CommandRunner) {
        self.runner = runner
    }

    /// Probe one driver in one Project root. `probeKind` records how the check was
    /// triggered — `.silent` (background, only ever runs a declared safe probe),
    /// `.explicitRecheck`, or `.userInitiatedRun`.
    public func detect(
        projectId: ProjectID,
        rootPath: String,
        manifest: DriverManifest,
        workerId: String? = nil,
        probeKind: ProbeKind = .silent,
        now: Date
    ) async -> ProjectWorkerReadiness {
        let label = manifest.projectProbe?.commandLabel

        // No declared safe probe → unsafeToProbe. Readiness can still change later
        // from an explicit user-initiated run; we never silently guess `ready`.
        guard let probe = manifest.projectProbe, probe.isSilentlyProbable, let command = probe.command else {
            return ProjectWorkerReadiness(
                projectId: projectId,
                sourceId: manifest.id,
                workerId: workerId,
                status: .unsafeToProbe,
                checkedAt: now,
                probeKind: probeKind,
                probeCommandLabel: label,
                lastError: nil,
                setupHint: nil
            )
        }

        let result = await runner.run(
            command: command,
            args: probe.args,
            stdin: nil,
            env: [:],
            workingDirectory: rootPath,
            timeout: .seconds(probe.timeoutSeconds)
        )

        let (status, lastError) = Self.classify(result, probe: probe)
        return ProjectWorkerReadiness(
            projectId: projectId,
            sourceId: manifest.id,
            workerId: workerId,
            status: status,
            checkedAt: now,
            probeKind: probeKind,
            probeCommandLabel: label,
            lastError: lastError,
            setupHint: Self.setupHint(for: status, manifest: manifest)
        )
    }

    /// Maps one probe result onto the canonical readiness status. Safety-first:
    /// authorization / auth / blocked signals win over an apparent success, and a
    /// probe that never proves success is `unknown`, never `ready`.
    static func classify(_ result: CommandResult, probe: ProjectProbe) -> (WorkerReadinessStatus, String?) {
        // The CLI binary could not be launched at all.
        if let launchError = result.launchError {
            return (.notInstalled, launchError)
        }
        // A bounded non-mutating probe that hangs to its timeout is almost always
        // sitting on an interactive trust/login prompt — never treat as ready.
        if result.timedOut {
            return (.interactiveRequired, "probe timed out after \(probe.timeoutSeconds)s (likely waiting on an interactive prompt)")
        }
        if result.cancelled {
            return (.unknown, "probe cancelled")
        }

        let haystack = (result.stdout + "\n" + result.stderr).lowercased()
        func matches(_ patterns: [String]) -> Bool {
            patterns.contains { !$0.isEmpty && haystack.contains($0.lowercased()) }
        }

        // Most specific / most cautious signals first.
        if matches(probe.projectAuthorizationPatterns) {
            return (.needsProjectAuthorization, firstLine(result.stderr) ?? firstLine(result.stdout))
        }
        if matches(probe.authErrorPatterns) {
            return (.authRequired, firstLine(result.stderr) ?? firstLine(result.stdout))
        }
        if matches(probe.blockedPatterns) {
            return (.blocked, firstLine(result.stderr) ?? firstLine(result.stdout))
        }

        if result.exitCode == 0 {
            if let expectation = probe.readyExpectation, !expectation.isEmpty,
               !result.stdout.lowercased().contains(expectation.lowercased()) {
                // Ran cleanly but did not confirm the expected signal — do not claim ready.
                return (.unknown, "probe exited 0 but expected output was not found")
            }
            return (.ready, nil)
        }

        // Non-zero exit with no recognized pattern.
        return (.unknown, firstLine(result.stderr) ?? "probe exited with code \(result.exitCode.map(String.init) ?? "nil")")
    }

    private static func firstLine(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init)
    }

    private static func setupHint(for status: WorkerReadinessStatus, manifest: DriverManifest) -> String? {
        switch status {
        case .ready, .unknown:
            return nil
        case .notInstalled:
            return manifest.setup?.installHint
        case .authRequired:
            return manifest.setup?.loginFlow?.instructions
        case .needsProjectAuthorization, .interactiveRequired:
            return "Open this CLI in the project folder and complete any trust or login prompts, then recheck workers."
        case .blocked, .unsafeToProbe:
            return nil
        }
    }
}
