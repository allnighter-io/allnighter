import Foundation

/// Thread-safe byte accumulator for pipe readability handlers.
private final class LockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

/// Thread-safe timestamp — the streaming idle watchdog reads it while readability
/// handlers (on a dispatch queue) write it on each output chunk.
private final class LockedDate: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func set(_ value: Date) { lock.lock(); self.value = value; lock.unlock() }
    func get() -> Date { lock.lock(); defer { lock.unlock() }; return value }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    /// Returns true exactly once.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}

/// Why a process ended. The first writer wins (normal exit unless a watchdog
/// or cancellation forced termination first).
private final class EndReason: @unchecked Sendable {
    enum Reason { case normal, timeout, cancel }
    private let lock = NSLock()
    private var reason: Reason = .normal

    func set(_ value: Reason) {
        lock.lock()
        if reason == .normal { reason = value }
        lock.unlock()
    }

    func get() -> Reason {
        lock.lock()
        defer { lock.unlock() }
        return reason
    }
}

/// Holds a `Process` so it can cross a `@Sendable` boundary (kill closures). The
/// process is only ever touched for `isRunning`/kill, guarded by the OS.
private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

/// Holds the timeout watchdog so the termination handler can cancel it without
/// capturing a mutable `var` in concurrent code.
private final class WatchdogRef: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func set(_ task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let current = task
        lock.unlock()
        current?.cancel()
    }
}

/// Runs commands as real child processes. Each command runs in **its own process
/// group** so the whole tree can be killed on timeout/cancel. The prompt is
/// passed as argv elements or via stdin — never concatenated into a shell
/// string — so prompt content cannot inject commands.
///
/// Implements both the request/response `CommandRunner` and the streaming
/// `StreamingCommandRunner`; both paths share the SAME executable resolution, env
/// scrubbing, stdin policy, working-directory, process-group kill, and timeout
/// rules via `configureProcess` / `launch`.
public struct SubprocessCommandRunner: CommandRunner, StreamingCommandRunner {
    public init() {}

    // MARK: - Non-streaming (unchanged contract)

    public func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult {
        let outBuffer = LockedBuffer()
        let errBuffer = LockedBuffer()
        let configured = Self.configureProcess(command: command, args: args, env: env,
                                               workingDirectory: workingDirectory, hasStdin: stdin != nil,
                                               outBuffer: outBuffer, errBuffer: errBuffer)
        guard let process = configured.process else {
            return CommandResult(launchError: configured.launchError ?? "command not found: \(command)")
        }

        if let launchError = Self.launch(process, command: command, stdin: stdin) {
            return CommandResult(launchError: launchError)
        }

        let endReason = EndReason()
        let box = ProcessBox(process)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CommandResult, Never>) in
                let resumer = ResumeOnce()
                let watchdogRef = WatchdogRef()

                process.terminationHandler = { proc in
                    (proc.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
                    (proc.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil

                    guard resumer.claim() else { return }
                    watchdogRef.cancel()
                    let reason = endReason.get()
                    let result = CommandResult(
                        stdout: String(decoding: outBuffer.snapshot(), as: UTF8.self),
                        stderr: String(decoding: errBuffer.snapshot(), as: UTF8.self),
                        exitCode: reason == .normal ? proc.terminationStatus : nil,
                        timedOut: reason == .timeout,
                        cancelled: reason == .cancel,
                        launchError: nil
                    )
                    continuation.resume(returning: result)
                }

                // Timeout watchdog — cancelled when the child exits normally.
                watchdogRef.set(Task {
                    try? await Task.sleep(for: timeout)
                    if box.process.isRunning {
                        endReason.set(.timeout)
                        Self.killGroup(box.process)
                    }
                })
            }
        } onCancel: {
            endReason.set(.cancel)
            Self.killGroup(box.process)
        }
    }

    // MARK: - Streaming (STR-S03)

    public func runStreaming(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) -> AsyncThrowingStream<CommandEvent, Error> {
        AsyncThrowingStream { continuation in
            let outBuffer = LockedBuffer()
            let errBuffer = LockedBuffer()
            // Readability handlers append to the full buffers (so the terminal
            // CommandResult carries everything) AND forward each raw chunk live.
            // The timeout is IDLE, not total: every output chunk pushes the deadline
            // forward, so a healthy agent that's actively streaming reasoning/output is
            // never killed mid-work — only a genuinely silent (hung) worker is.
            let lastActivity = LockedDate(Date())
            let configured = Self.configureProcess(
                command: command, args: args, env: env,
                workingDirectory: workingDirectory, hasStdin: stdin != nil,
                outBuffer: outBuffer, errBuffer: errBuffer,
                onStdout: { lastActivity.set(Date()); continuation.yield(.stdout($0)) },
                onStderr: { lastActivity.set(Date()); continuation.yield(.stderr($0)) }
            )
            guard let process = configured.process else {
                continuation.yield(.failed(launchError: configured.launchError ?? "command not found: \(command)"))
                continuation.finish()
                return
            }

            let endReason = EndReason()
            let resumer = ResumeOnce()
            let box = ProcessBox(process)

            // Terminal event — set BEFORE launch so a fast-exiting process can't
            // slip past us. Emits exactly one of completed/timedOut/cancelled.
            process.terminationHandler = { proc in
                (proc.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
                (proc.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
                guard resumer.claim() else { return }
                switch endReason.get() {
                case .normal:
                    continuation.yield(.completed(CommandResult(
                        stdout: String(decoding: outBuffer.snapshot(), as: UTF8.self),
                        stderr: String(decoding: errBuffer.snapshot(), as: UTF8.self),
                        exitCode: proc.terminationStatus)))
                case .timeout:
                    continuation.yield(.timedOut(partialStdout: outBuffer.snapshot(),
                                                 partialStderr: errBuffer.snapshot()))
                case .cancel:
                    continuation.yield(.cancelled(partialStdout: outBuffer.snapshot(),
                                                  partialStderr: errBuffer.snapshot()))
                }
                continuation.finish()
            }

            // Consumer cancelled/broke the stream → kill the process group; the
            // termination handler then emits `.cancelled` with partial buffers.
            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination, box.process.isRunning {
                    endReason.set(.cancel)
                    Self.killGroup(box.process)
                }
            }

            if let launchError = Self.launch(process, command: command, stdin: stdin) {
                continuation.yield(.failed(launchError: launchError))
                continuation.finish()
                return
            }
            continuation.yield(.started(startedAt: Date()))

            // Idle-timeout watchdog: kill only when SILENT for `timeout` (no output),
            // re-checking every few seconds and resetting whenever a chunk arrives.
            let idleSeconds = max(Double(timeout.components.seconds), 1)
            Task {
                while box.process.isRunning {
                    let idle = Date().timeIntervalSince(lastActivity.get())
                    if idle >= idleSeconds {
                        if box.process.isRunning { endReason.set(.timeout); Self.killGroup(box.process) }
                        break
                    }
                    try? await Task.sleep(for: .seconds(min(idleSeconds - idle, 5)))
                }
            }
        }
    }

    // MARK: - Shared plumbing

    /// Builds and configures (but does NOT launch) the child: executable
    /// resolution, env (depth guard + token scrub), cwd, stdin policy, and
    /// stdout/stderr pipes whose readability handlers append to `outBuffer`/
    /// `errBuffer` AND forward each chunk to the optional callbacks. Returns the
    /// launch-error string on resolve failure.
    private static func configureProcess(
        command: String, args: [String], env: [String: String],
        workingDirectory: String?, hasStdin: Bool,
        outBuffer: LockedBuffer, errBuffer: LockedBuffer,
        onStdout: (@Sendable (Data) -> Void)? = nil,
        onStderr: (@Sendable (Data) -> Void)? = nil
    ) -> (process: Process?, launchError: String?) {
        guard let executableURL = resolveExecutable(command, env: env) else {
            return (nil, "command not found: \(command)")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = args

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env { environment[key] = value }
        // Recursion guard (RB6): every spawned worker carries depth+1, so a worker
        // that invokes the team tool sees it is already inside one and refuses.
        let currentDepth = Int(environment["ALLNIGHTER_TEAM_DEPTH"] ?? "0") ?? 0
        environment["ALLNIGHTER_TEAM_DEPTH"] = String(currentDepth + 1)
        // Scrub the loopback tool token so a deep worker can't authenticate to the
        // running HTTP server.
        environment["ALLNIGHTER_TOOL_TOKEN"] = nil
        process.environment = environment

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        process.standardOutput = Pipe()
        process.standardError = Pipe()
        // Always give the child a defined stdin: a pipe when we have input, else
        // /dev/null so CLIs (e.g. `claude -p`) don't block waiting on a TTY.
        process.standardInput = hasStdin ? Pipe() : FileHandle.nullDevice

        (process.standardOutput as! Pipe).fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { outBuffer.append(chunk); onStdout?(chunk) }
        }
        (process.standardError as! Pipe).fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { errBuffer.append(chunk); onStderr?(chunk) }
        }

        process.qualityOfService = .userInitiated
        return (process, nil)
    }

    /// Launches the configured process in its own group and writes stdin. Returns a
    /// launch-error string on spawn failure, else nil.
    private static func launch(_ process: Process, command: String, stdin: String?) -> String? {
        do {
            try process.run()
            // Put the child in its own process group (best-effort) so a kill of
            // the negative pid reaches any grandchildren the CLI spawns.
            setpgid(process.processIdentifier, process.processIdentifier)
        } catch {
            return "failed to launch \(command): \(error.localizedDescription)"
        }
        if let stdin, let inputPipe = process.standardInput as? Pipe {
            let handle = inputPipe.fileHandleForWriting
            try? handle.write(contentsOf: Data(stdin.utf8))
            try? handle.close()
        }
        return nil
    }

    /// Resolves a command to an executable URL: absolute/relative paths are used
    /// directly; bare names are searched on PATH.
    static func resolveExecutable(_ command: String, env: [String: String]) -> URL? {
        if command.contains("/") {
            let url = URL(fileURLWithPath: command)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        let pathValue = env["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
        for dir in pathValue.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func killGroup(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        // Try the process group first (negative pid), then the process.
        if kill(-pid, SIGTERM) != 0 {
            process.terminate()
        }
    }
}
