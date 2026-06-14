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

/// Runs commands as real child processes. Each command runs in **its own process
/// group** so the whole tree can be killed on timeout/cancel. The prompt is
/// passed as argv elements or via stdin — never concatenated into a shell
/// string — so prompt content cannot inject commands.
public struct SubprocessCommandRunner: CommandRunner {
    public init() {}

    public func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult {
        guard let executableURL = Self.resolveExecutable(command, env: env) else {
            return CommandResult(launchError: "command not found: \(command)")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = args

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env { environment[key] = value }
        process.environment = environment

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        // Launch in a new process group so we can kill the whole tree.
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        if stdin != nil { process.standardInput = Pipe() }

        let outBuffer = LockedBuffer()
        let errBuffer = LockedBuffer()
        (process.standardOutput as! Pipe).fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { outBuffer.append(chunk) }
        }
        (process.standardError as! Pipe).fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { errBuffer.append(chunk) }
        }

        process.qualityOfService = .userInitiated

        do {
            try process.run()
            // Put the child in its own process group (best-effort) so a kill of
            // the negative pid reaches any grandchildren the CLI spawns.
            setpgid(process.processIdentifier, process.processIdentifier)
        } catch {
            return CommandResult(launchError: "failed to launch \(command): \(error.localizedDescription)")
        }

        if let stdin, let inputPipe = process.standardInput as? Pipe {
            let handle = inputPipe.fileHandleForWriting
            handle.write(Data(stdin.utf8))
            try? handle.close()
        }

        let endReason = EndReason()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CommandResult, Never>) in
                let resumer = ResumeOnce()

                process.terminationHandler = { proc in
                    (proc.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
                    (proc.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil

                    guard resumer.claim() else { return }
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

                // Timeout watchdog.
                Task {
                    try? await Task.sleep(for: timeout)
                    if process.isRunning {
                        endReason.set(.timeout)
                        Self.killGroup(process)
                    }
                }
            }
        } onCancel: {
            endReason.set(.cancel)
            Self.killGroup(process)
        }
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
