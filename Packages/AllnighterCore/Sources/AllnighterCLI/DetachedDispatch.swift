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

    /// Child argv removes detached-only routing flags. The child executes the normal
    /// blocking path; otherwise `--delivery wake` would be rejected for lacking
    /// `--no-wait` after the parent already validated the receiver.
    static func childArguments(from argv: [String] = Array(CommandLine.arguments.dropFirst())) -> [String] {
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
///
/// ORS-S03a: `kind: "run"` carries `nextAction` (canonical `alln show <id> --stream`)
/// and omits `delivery`. Loop/relay keep `delivery` (out of scope for this cutover).
struct DetachedDispatchJSON: Encodable {
    struct Delivery: Encodable, Equatable {
        let path: String
        let command: String?

        init(path: String = "wait", command: String? = nil) {
            self.path = path
            self.command = command
        }

        private enum CodingKeys: String, CodingKey { case path, command }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(command, forKey: .command)
        }
    }

    /// One recommended next step on a detached **run** acknowledgement (ORS-S03a).
    struct NextAction: Encodable, Equatable {
        let kind: String
        let command: String
    }

    let kind: String
    let id: String
    let status: String
    let pid: Int32
    let delivery: Delivery?
    let nextAction: NextAction?

    init(
        kind: String,
        id: String,
        status: String,
        pid: Int32,
        delivery: Delivery? = nil,
        nextAction: NextAction? = nil
    ) {
        self.kind = kind
        self.id = id
        self.status = status
        self.pid = pid
        self.delivery = delivery
        self.nextAction = nextAction
    }

    private enum CodingKeys: String, CodingKey {
        case kind, id, status, pid, delivery, nextAction
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(id, forKey: .id)
        try container.encode(status, forKey: .status)
        try container.encode(pid, forKey: .pid)
        try container.encodeIfPresent(delivery, forKey: .delivery)
        try container.encodeIfPresent(nextAction, forKey: .nextAction)
    }
}

extension DetachedDispatch {
    static let defaultPMTurnWaitTimeoutSeconds = 7_200

    /// The detached child is this executable, so return its absolute path when
    /// resolution can prove one. A bare `alln` remains the portable fallback.
    static func commandPrefix(
        argv0: String? = CommandLine.arguments.first,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        currentExecutablePath: () -> String? = ProcessOwnership.currentExecutablePath
    ) -> String {
        ProcessOwnership.resolveRunningExecutablePath(
            argv0: argv0,
            pathEnvironment: pathEnvironment,
            currentExecutablePath: currentExecutablePath
        ) ?? "alln"
    }

    /// Loop/relay pull waiter (out of ORS-S03a scope). Run dispatch no longer uses
    /// this — see `runNextAction(id:)`.
    static func waitDelivery(kind: String, id: String, commandPrefix: String) -> DetachedDispatchJSON.Delivery {
        let command: String
        switch kind {
        case "pilot":
            command = "\(commandPrefix) loop status \(id) --wait-for parked --timeout \(defaultPMTurnWaitTimeoutSeconds) --json"
        default:
            // relay (and any non-run legacy kind)
            command = "\(commandPrefix) loop status \(id) --wait-for terminal --timeout \(defaultPMTurnWaitTimeoutSeconds) --json"
        }
        return .init(command: command)
    }

    /// Canonical detached **run** next action: observe the middle and deliver the end.
    /// Bare `alln` (no absolute binary path). Real run id only — never `latest`/`--full`.
    static func runNextAction(id: String) -> DetachedDispatchJSON.NextAction {
        .init(kind: "showRun", command: "alln show \(id) --stream")
    }

    static func wakeDelivery() -> DetachedDispatchJSON.Delivery {
        .init(path: "wake")
    }

    /// Validates Path C before any detached process is launched.
    /// Returns true only for the one supported delivery value (`wake`).
    static func validateWakeDelivery(_ opts: Options) -> Bool {
        let raw = opts.value("delivery") ?? (opts.flag("delivery") ? "" : nil)
        guard let raw else { return false }
        guard opts.flag("no-wait") else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--delivery wake requires --no-wait")
        }
        guard raw == "wake" else {
            AllnighterCLI.fail(code: "CLI_USAGE_ERROR", message: "--delivery supports only wake")
        }
        guard PMTurnWakeConfigurationStore().hasConfiguredCommand() else {
            AllnighterCLI.fail(
                code: "PM_TURN_WAKE_UNCONFIGURED",
                message: "--delivery wake requires pmTurnWake.command in machine serve configuration")
        }
        return true
    }
}
