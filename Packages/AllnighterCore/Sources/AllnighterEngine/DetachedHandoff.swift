import Foundation
import AllnighterCore

/// RSC-HF: child → parent acceptance for `--no-wait`.
///
/// Parent creates a handoff directory, sets `ALLNIGHTER_DETACHED_HANDOFF`, spawns the
/// same registered verb with `--no-wait` stripped, and waits for
/// `ProcessOwnership.runner_ready.json`. Child writes accepted/refused after a durable
/// claim (or an early refusal). No-op when the env var is unset (normal foreground).
///
/// Reuses existing `RunnerReadyHandshake` I/O — does **not** restore deleted
/// `team __runner` / `AsyncTeamRunnerRequest`.
public enum DetachedHandoff {
    public static let envKey = "ALLNIGHTER_DETACHED_HANDOFF"

    /// Directory the parent created for this dispatch, if this process is a detached child.
    public static func directory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let raw = environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: raw, isDirectory: true)
    }

    public static func reportAccepted(
        id: String,
        at: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let dir = directory(environment: environment) else { return }
        try? ProcessOwnership.writeRunnerReady(.accepted(runId: id, at: at), in: dir)
    }

    public static func reportRefused(
        id: String = "",
        code: String,
        message: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let dir = directory(environment: environment) else { return }
        try? ProcessOwnership.writeRunnerReady(
            .refused(runId: id, code: code, message: message),
            in: dir
        )
    }
}
