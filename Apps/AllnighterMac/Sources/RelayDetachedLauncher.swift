import Foundation
import AllnighterCore
import AllnighterEngine

/// ATL-S03 — Mac Loop detached start. Spawns the same registered `alln loop start
/// --no-wait` argv the CLI uses (LVC v7, `docs/phases/Loop_Verb_Cutover.md`), waits
/// for `DetachedHandoff` acceptance, and returns the durable loop id. Mirrors
/// `DetachedDispatch.launchAndAwaitAcceptance` without linking `AllnighterCLI`
/// (executable target only).
enum RelayDetachedLauncher {
    enum Outcome: Equatable {
        case accepted(id: String, pid: Int32)
        case refused(code: String, message: String)
        case timedOut
        case unresolvedExecutable
        case spawnFailed(String)
    }

    /// Spawn `loop start … --no-wait --json` in a detached child whose argv omits
    /// detached-only routing flags — same strip law as `DetachedDispatch.childArguments`.
    static func launchAndAwaitAcceptance(
        cwd: String,
        arguments: [String],
        timeout: TimeInterval = 60,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        currentExecutablePath: () -> String? = ProcessOwnership.currentExecutablePath
    ) -> Outcome {
        guard let executablePath = ProcessOwnership.resolveRunningExecutablePath(
            pathEnvironment: pathEnvironment,
            currentExecutablePath: currentExecutablePath
        ) else {
            return .unresolvedExecutable
        }

        let handoff = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-detached-handoff-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: handoff, withIntermediateDirectories: true)
        } catch {
            return .spawnFailed("\(error)")
        }
        defer { try? FileManager.default.removeItem(at: handoff) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = AllnighterSpawnEnvironmentPolicy.processEnvironment(
            extra: [DetachedHandoff.envKey: handoff.path]
        )
        process.arguments = childArguments(from: arguments)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .spawnFailed("\(error)")
        }

        let pid = process.processIdentifier
        guard let handshake = ProcessOwnership.waitForRunnerReady(in: handoff, timeout: timeout) else {
            return .timedOut
        }
        switch handshake.outcome {
        case .accepted:
            return .accepted(id: handshake.runId, pid: pid)
        case .refused:
            return .refused(
                code: handshake.refusalCode ?? "INTERNAL_ERROR",
                message: handshake.refusalMessage ?? "detached child refused"
            )
        }
    }

    static func childArguments(from argv: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < argv.count {
            switch argv[index] {
            case "--no-wait":
                index += 1
            case "--delivery":
                index += min(2, argv.count - index)
            default:
                result.append(argv[index])
                index += 1
            }
        }
        return result
    }

    /// Builds the parent argv passed to `launchAndAwaitAcceptance` (includes `--no-wait`).
    /// `kickoffMessage` is the loop's brief — `alln loop start`'s one required
    /// positional (LVC v7 §2); `docPath` is the optional `--spec` shortcut, always
    /// supplied here because the launch sheet still requires a spec doc (§8, deferred).
    /// PM is always an explicit agent id — the sheet has no `--pm caller` option
    /// (LVC-S06: there is no live agent session behind a modal).
    static func relayStartArguments(
        docPath: String,
        projectId: String,
        pmModelId: String,
        devModelId: String,
        kickoffMessage: String,
        maxRounds: Int,
        until: Date?
    ) -> [String] {
        var args = [
            "loop", "start", kickoffMessage,
            "--spec", docPath,
            "--project", projectId,
            "--pm", pmModelId,
            "--dev", devModelId,
            "--max-rounds", String(maxRounds),
            "--no-wait", "--json",
        ]
        if let until {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: until)
            let minute = calendar.component(.minute, from: until)
            args.append(contentsOf: ["--until", String(format: "%02d:%02d", hour, minute)])
        }
        return args
    }
}
