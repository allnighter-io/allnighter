import Foundation
import AllnighterCore
import AllnighterEngine

/// Shared "re-launch this same running binary as a detached background process"
/// primitive for `pilot handoff --no-wait`, `pair relay`/`relay-resume`/`relay adopt
/// --no-wait`, and `alln run --no-wait`.
///
/// RSC-HF: `launchAndAwaitAcceptance` creates a handoff directory, passes
/// `ALLNIGHTER_DETACHED_HANDOFF` to the child, and waits for
/// `ProcessOwnership.RunnerReadyHandshake` before acknowledging. Ack means the child
/// durably accepted (or refused) — not merely that `Process.run` returned.
enum DetachedDispatch {
    enum LaunchError: Error, Equatable {
        case unresolvedExecutable
        case spawnFailed(String)
    }

    enum Acceptance: Equatable {
        case accepted(id: String, pid: Int32)
        case refused(id: String, code: String, message: String, pid: Int32)
        case timedOut(pid: Int32)
    }

    /// Fire-and-forget spawn (used by tests and any caller that does not need an
    /// acceptance handshake). Prefer `launchAndAwaitAcceptance` for product `--no-wait`.
    @discardableResult
    static func launch(
        cwd: String,
        arguments: [String],
        executableURL: URL? = nil,
        argv0: String? = CommandLine.arguments.first,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        currentExecutablePath: () -> String? = ProcessOwnership.currentExecutablePath,
        extraEnvironment: [String: String] = [:]
    ) throws -> Process {
        let resolvedURL = try resolveExecutable(
            executableURL: executableURL,
            argv0: argv0,
            pathEnvironment: pathEnvironment,
            currentExecutablePath: currentExecutablePath
        )

        let process = Process()
        process.executableURL = resolvedURL
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = AllnighterSpawnEnvironmentPolicy.processEnvironment(extra: extraEnvironment)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw LaunchError.spawnFailed("\(error)")
        }
        return process
    }

    /// Spawn the child with a handoff directory, then block until it writes
    /// accepted/refused (or the wait times out). Cleans up the handoff directory after.
    static func launchAndAwaitAcceptance(
        cwd: String,
        arguments: [String],
        timeout: TimeInterval = 60,
        executableURL: URL? = nil,
        argv0: String? = CommandLine.arguments.first,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        currentExecutablePath: () -> String? = ProcessOwnership.currentExecutablePath
    ) throws -> Acceptance {
        let handoff = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-detached-handoff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: handoff, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: handoff) }

        let process = try launch(
            cwd: cwd,
            arguments: arguments,
            executableURL: executableURL,
            argv0: argv0,
            pathEnvironment: pathEnvironment,
            currentExecutablePath: currentExecutablePath,
            extraEnvironment: [DetachedHandoff.envKey: handoff.path]
        )
        let pid = process.processIdentifier

        guard let handshake = ProcessOwnership.waitForRunnerReady(in: handoff, timeout: timeout) else {
            return .timedOut(pid: pid)
        }
        switch handshake.outcome {
        case .accepted:
            return .accepted(id: handshake.runId, pid: pid)
        case .refused:
            return .refused(
                id: handshake.runId,
                code: handshake.refusalCode ?? "INTERNAL_ERROR",
                message: handshake.refusalMessage ?? "detached child refused",
                pid: pid
            )
        }
    }

    /// Child argv = parent argv with `--no-wait` removed. Preserves every other flag
    /// (including `--no-auto-serve`).
    static func childArguments(from argv: [String] = Array(CommandLine.arguments.dropFirst())) -> [String] {
        argv.filter { $0 != "--no-wait" }
    }

    private static func resolveExecutable(
        executableURL: URL?,
        argv0: String?,
        pathEnvironment: String?,
        currentExecutablePath: () -> String?
    ) throws -> URL {
        if let executableURL { return executableURL }
        guard let path = ProcessOwnership.resolveRunningExecutablePath(
            argv0: argv0, pathEnvironment: pathEnvironment, currentExecutablePath: currentExecutablePath
        ) else {
            throw LaunchError.unresolvedExecutable
        }
        return URL(fileURLWithPath: path)
    }
}

/// One dispatch ack shape for every detached verb (`kind`: `"relay"` | `"run"`).
struct DetachedDispatchJSON: Encodable {
    let kind: String
    let id: String
    let status: String
    let pid: Int32
}
