import Foundation
import AllnighterCore

/// Health of one worker's CLI, surfaced in Doctor (Phase 05) so a churned or
/// unauthenticated tool fails loudly instead of silently dropping out.
public enum ModelHealth: Sendable, Equatable {
    case healthy
    case unknown
    case unhealthy(reason: String)

    public var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }
}

/// Runs a driver's `detectCommand` (presence) and `smokeTestCommand` (responds
/// correctly). These manifest strings are author-controlled, so they are
/// tokenized with `ShellWords`; user prompt content never flows through here.
public struct ModelHealthChecker: Sendable {
    private let commandRunner: CommandRunner
    private let detectTimeout: Duration
    private let smokeTimeout: Duration
    /// Neutral CWD for detect/smoke child processes so they never inherit the
    /// repo/Documents working dir (Launch Authority TCC hotfix, slice H3).
    private let workingDirectory: String?

    public init(
        commandRunner: CommandRunner,
        detectTimeout: Duration = .seconds(10),
        smokeTimeout: Duration = .seconds(60),
        workingDirectory: String? = AllnighterPaths.ensuredProbeScratchPath()
    ) {
        self.commandRunner = commandRunner
        self.detectTimeout = detectTimeout
        self.smokeTimeout = smokeTimeout
        self.workingDirectory = workingDirectory
    }

    /// True if the CLI is present (detect command exits 0).
    public func detect(_ manifest: DriverManifest) async -> Bool {
        await detectVersion(manifest).present
    }

    /// Runs the `detectCommand` and reports presence plus the version line it
    /// printed (first non-empty stdout line), for Doctor's at-a-glance display.
    public func detectVersion(_ manifest: DriverManifest) async -> (present: Bool, version: String?, launchError: String?) {
        guard manifest.kind == .headlessCLI, let detectCommand = manifest.detectCommand else {
            return (false, nil, nil)
        }
        let tokens = ShellWords.split(detectCommand)
        guard let command = tokens.first else { return (false, nil, nil) }
        let result = await commandRunner.run(
            command: command,
            args: Array(tokens.dropFirst()),
            stdin: nil,
            env: [:],
            workingDirectory: workingDirectory,
            timeout: detectTimeout
        )
        let present = result.launchError == nil && result.exitCode == 0
        let version = present
            ? result.stdout
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first(where: { !$0.isEmpty })
            : nil
        return (present, version, result.launchError)
    }

    /// Runs the smoke test for `model` and classifies health.
    public func smokeTest(_ manifest: DriverManifest, model: String) async -> ModelHealth {
        guard manifest.kind == .headlessCLI else {
            return .unknown  // manual-paste workers have no automated smoke test.
        }
        guard let raw = manifest.smokeTestCommand,
              let resolved = manifest.resolvedCommandString(raw, model: model) else {
            return .unknown
        }
        let tokens = ShellWords.split(resolved)
        guard let command = tokens.first else { return .unknown }

        if manifest.id == "opencode" {
            do {
                try await OpenCodeServeCoordinator().ensureRunning()
            } catch {
                return .unhealthy(reason: "opencode serve: \(error)")
            }
        }

        let result = await commandRunner.run(
            command: command,
            args: Array(tokens.dropFirst()),
            stdin: nil,
            env: [:],
            workingDirectory: workingDirectory,
            timeout: smokeTimeout
        )

        if let launchError = result.launchError {
            return .unhealthy(reason: launchError)
        }
        if result.timedOut {
            return .unhealthy(reason: "smoke test timed out")
        }
        if let code = result.exitCode, code != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .unhealthy(reason: stderr.isEmpty ? "smoke test exited \(code)" : stderr)
        }
        if let expected = manifest.smokeTestExpect {
            let visible = manifest.id == "opencode"
                ? TextUtil.extractOpenCodeVisibleText(result.stdout) : result.stdout
            if !visible.contains(expected) {
                return .unhealthy(reason: "smoke test did not return expected token")
            }
        }
        return .healthy
    }
}
