import Foundation
import AllnighterCore
import AllnighterEngine

/// RSC-S03 (`docs/phases/Round_Survives_The_Caller.md`): the shared "re-launch this
/// same running binary as a detached background process" primitive. Extracted from
/// `PilotCLI.dispatchHandoffInBackground` (`pilot handoff --no-wait`, already shipped)
/// so `pair relay` / `pair relay-resume` / `pair relay adopt`'s own `--no-wait` do not
/// grow a second, drifting implementation of "resolve the binary, build a `Process`,
/// set env/stdio". `PilotCLI` itself switches to this helper for that step — its
/// SR-12 submission-staging logic (a Pilot-specific concern, `PilotCLI.swift` around
/// `dispatchHandoffInBackground`) is untouched.
enum DetachedDispatch {
    enum LaunchError: Error, Equatable {
        case unresolvedExecutable
        case spawnFailed(String)
    }

    /// Resolves the running binary (`ProcessOwnership.resolveRunningExecutablePath` —
    /// the same argv0/PATH/`_NSGetExecutablePath` resolution order `pilot handoff
    /// --no-wait` and `alln serve` auto-launch already use), builds a `Process` with
    /// `cwd`/`arguments`/the shared spawn-environment policy/null stdio, runs it, and
    /// returns the launched `Process` so the caller can read `processIdentifier` for
    /// its dispatch ack. Does not touch stdout/stdin/stderr of the caller — the child
    /// is fully detached (its own output goes to `/dev/null`, matching Pilot's
    /// `--no-wait`: agents poll status, they don't tail a detached child's stdout).
    @discardableResult
    static func launch(
        cwd: String,
        arguments: [String],
        executableURL: URL? = nil,
        argv0: String? = CommandLine.arguments.first,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        currentExecutablePath: () -> String? = ProcessOwnership.currentExecutablePath
    ) throws -> Process {
        let resolvedURL: URL
        if let executableURL {
            resolvedURL = executableURL
        } else {
            guard let path = ProcessOwnership.resolveRunningExecutablePath(
                argv0: argv0, pathEnvironment: pathEnvironment, currentExecutablePath: currentExecutablePath
            ) else {
                throw LaunchError.unresolvedExecutable
            }
            resolvedURL = URL(fileURLWithPath: path)
        }

        let process = Process()
        process.executableURL = resolvedURL
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = AllnighterSpawnEnvironmentPolicy.processEnvironment()
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

    /// Child argv = the parent's argv (from `CommandLine.arguments`, dropping the
    /// executable at index 0) with `--no-wait` removed — the child runs the normal
    /// blocking path. `--no-wait` is a boolean flag (no value), so removal is a plain
    /// filter, never a value-aware parse. This is intentionally simpler than Pilot's
    /// SR-12 handoff-file staging: that staging exists because a handover *file* could
    /// be mutated between the foreground ack and the child opening it. Every relay
    /// verb's other flag values are already immutable argv strings (never a live file
    /// path re-read later), and `--doc` is re-read fresh every round by design — so
    /// there is no live-mutation window here to guard against. A future reader should
    /// not "fix" this by reintroducing staging.
    static func childArguments(from argv: [String] = Array(CommandLine.arguments.dropFirst())) -> [String] {
        argv.filter { $0 != "--no-wait" }
    }
}

/// RSC-S03: one dispatch ack shape for every detached verb (`pair relay` /
/// `relay-resume` / `relay adopt`; `kind` leaves room for `alln run --no-wait`,
/// RSC-S04, without a second envelope type). CLI-local, not an `OutputSchema` case —
/// mirrors `PilotHandoffDispatchJSON` (`PilotCLI.swift`), which is likewise not
/// registered in `ContractRegistry.OutputSchema`.
struct DetachedDispatchJSON: Encodable {
    let kind: String     // "relay" | "run"
    let id: String       // relayId or runId
    let status: String   // "dispatched"
    let pid: Int32
}
