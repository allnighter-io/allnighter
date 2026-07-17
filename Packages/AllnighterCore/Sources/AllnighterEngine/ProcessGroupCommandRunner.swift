import Foundation
import Darwin
import AllnighterCore

#if os(macOS) || os(Linux)

/// Process-group-leader command runner for PO-S02: every worker CLI is spawned via
/// `ProcessOwnership.spawnProcessGroupLeader` (`posix_spawn` + `POSIX_SPAWN_SETPGROUP`),
/// identity recorded for turn kill, and termination always routes through
/// `ProcessOwnership.terminateProcessGroup` / identity-checked helpers — never a
/// second kill implementation and never invents `pgid == pid` after the fact.
///
/// Mirrors `SubprocessCommandRunner`'s contracts (timeouts, buffer caps, streaming)
/// so `RunService` / `WorkerInvokerFactory` can use it as a drop-in.
public struct ProcessGroupCommandRunner: CommandRunner, StreamingCommandRunner {
    public let environmentPolicy: any SpawnEnvironmentPolicy
    public let budget: SubprocessBudget
    /// Owner kind stamped on each spawn. Relay/pilot dev turns set the active
    /// `TurnOwnerDirectory` and use `.devTurn`; other call sites still get a
    /// killable group (kind `.devTurn` only writes the turn-owner file when the
    /// directory is set — see `recordSpawnedTurnOwner`).
    public let spawnKind: ProcessOwnership.OwnerKind

    public init(
        environmentPolicy: any SpawnEnvironmentPolicy = AllnighterSpawnEnvironmentPolicy(),
        budget: SubprocessBudget = .default,
        spawnKind: ProcessOwnership.OwnerKind = .devTurn
    ) {
        self.environmentPolicy = environmentPolicy
        self.budget = budget
        self.spawnKind = spawnKind
    }

    // MARK: - Non-streaming

    public func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult {
        guard let executable = SubprocessCommandRunner.resolveExecutable(command, env: env) else {
            return CommandResult(launchError: "command not found: \(command)")
        }
        let childEnv = environmentPolicy.environment(for: mergeEnv(env))
        let spawned: ProcessOwnership.SpawnedProcessGroup
        do {
            spawned = try ProcessOwnership.spawnProcessGroupLeader(
                executablePath: executable.path,
                arguments: args,
                workingDirectory: workingDirectory,
                stdinMode: stdin != nil ? .pipe : .devNull,
                stdoutMode: .pipe,
                stderrMode: .pipe,
                environment: childEnv,
                kind: spawnKind
            )
        } catch {
            return CommandResult(launchError: "failed to launch \(command): \(error)")
        }

        if let stdin, let fd = spawned.stdinWriteFD {
            let data = Data(stdin.utf8)
            data.withUnsafeBytes { raw in
                if let base = raw.bindMemory(to: UInt8.self).baseAddress {
                    _ = write(fd, base, data.count)
                }
            }
            close(fd)
        } else if let fd = spawned.stdinWriteFD {
            close(fd)
        }

        let outBuffer = LockedDataBuffer()
        let errBuffer = LockedDataBuffer()
        let endReason = EndReasonBox()
        let identity = spawned.identity

        let outSource = makeReadSource(fd: spawned.stdoutReadFD, buffer: outBuffer, cap: budget.maxBufferedBytes) {
            endReason.set(.bufferCap)
            _ = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
        }
        let errSource = makeReadSource(fd: spawned.stderrReadFD, buffer: errBuffer, cap: budget.maxBufferedBytes) {
            endReason.set(.bufferCap)
            _ = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CommandResult, Never>) in
                let resumer = ResumeOnceBox()
                let watchdog = WatchdogBox()

                DispatchQueue.global(qos: .userInitiated).async {
                    var status: Int32 = 0
                    _ = waitpid(spawned.pid, &status, 0)
                    outSource?.cancel(); errSource?.cancel()
                    closePipe(spawned.stdoutReadFD)
                    closePipe(spawned.stderrReadFD)
                    guard resumer.claim() else { return }
                    watchdog.cancel()
                    let reason = endReason.get()
                    let exitCode: Int32? = reason == .normal ? Self.waitStatusExitCode(status) : nil
                    continuation.resume(returning: CommandResult(
                        stdout: String(decoding: outBuffer.snapshot(), as: UTF8.self),
                        stderr: String(decoding: errBuffer.snapshot(), as: UTF8.self),
                        exitCode: exitCode,
                        timedOut: reason == .timeout,
                        cancelled: reason == .cancel,
                        bufferOverflowed: reason == .bufferCap
                    ))
                }

                watchdog.set(Task {
                    try? await Task.sleep(for: timeout)
                    if ProcessOwnership.processAlive(spawned.pid) {
                        endReason.set(.timeout)
                        _ = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
                    }
                })
            }
        } onCancel: {
            endReason.set(.cancel)
            _ = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
        }
    }

    // MARK: - Streaming

    public func runStreaming(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) -> AsyncThrowingStream<CommandEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let executable = SubprocessCommandRunner.resolveExecutable(command, env: env) else {
                continuation.yield(.failed(launchError: "command not found: \(command)"))
                continuation.finish()
                return
            }
            let childEnv = environmentPolicy.environment(for: mergeEnv(env))
            let spawned: ProcessOwnership.SpawnedProcessGroup
            do {
                spawned = try ProcessOwnership.spawnProcessGroupLeader(
                    executablePath: executable.path,
                    arguments: args,
                    workingDirectory: workingDirectory,
                    stdinMode: stdin != nil ? .pipe : .devNull,
                    stdoutMode: .pipe,
                    stderrMode: .pipe,
                    environment: childEnv,
                    kind: spawnKind
                )
            } catch {
                continuation.yield(.failed(launchError: "failed to launch \(command): \(error)"))
                continuation.finish()
                return
            }

            if let stdin, let fd = spawned.stdinWriteFD {
                let data = Data(stdin.utf8)
                data.withUnsafeBytes { raw in
                    if let base = raw.bindMemory(to: UInt8.self).baseAddress {
                        _ = write(fd, base, data.count)
                    }
                }
                close(fd)
            } else if let fd = spawned.stdinWriteFD {
                close(fd)
            }

            let outBuffer = LockedDataBuffer()
            let errBuffer = LockedDataBuffer()
            let endReason = EndReasonBox()
            let identity = spawned.identity
            let lastActivity = LockedDateBox(Date())
            let resumer = ResumeOnceBox()

            continuation.yield(.started(startedAt: Date()))

            let onOverflow: @Sendable () -> Void = {
                endReason.set(.bufferCap)
                _ = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
            }

            let outSource = makeStreamingReadSource(
                fd: spawned.stdoutReadFD, buffer: outBuffer, cap: budget.maxBufferedBytes,
                onChunk: { data in
                    lastActivity.set(Date())
                    continuation.yield(.stdout(data))
                },
                onOverflow: onOverflow
            )
            let errSource = makeStreamingReadSource(
                fd: spawned.stderrReadFD, buffer: errBuffer, cap: budget.maxBufferedBytes,
                onChunk: { data in
                    lastActivity.set(Date())
                    continuation.yield(.stderr(data))
                },
                onOverflow: onOverflow
            )

            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination, ProcessOwnership.processAlive(spawned.pid) {
                    endReason.set(.cancel)
                    _ = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
                }
            }

            DispatchQueue.global(qos: .userInitiated).async {
                var status: Int32 = 0
                _ = waitpid(spawned.pid, &status, 0)
                outSource?.cancel(); errSource?.cancel()
                closePipe(spawned.stdoutReadFD)
                closePipe(spawned.stderrReadFD)
                guard resumer.claim() else { return }
                switch endReason.get() {
                case .normal:
                    continuation.yield(.completed(CommandResult(
                        stdout: String(decoding: outBuffer.snapshot(), as: UTF8.self),
                        stderr: String(decoding: errBuffer.snapshot(), as: UTF8.self),
                        exitCode: Self.waitStatusExitCode(status)
                    )))
                case .timeout:
                    continuation.yield(.timedOut(
                        partialStdout: outBuffer.snapshot(),
                        partialStderr: errBuffer.snapshot()
                    ))
                case .cancel:
                    continuation.yield(.cancelled(
                        partialStdout: outBuffer.snapshot(),
                        partialStderr: errBuffer.snapshot()
                    ))
                case .bufferCap:
                    continuation.yield(.bufferOverflow(
                        partialStdout: outBuffer.snapshot(),
                        partialStderr: errBuffer.snapshot()
                    ))
                }
                continuation.finish()
            }

            // Idle timeout (streaming silence).
            let idleSeconds = max(Double(timeout.components.seconds), 1)
            Task {
                while ProcessOwnership.processAlive(spawned.pid) {
                    let idle = Date().timeIntervalSince(lastActivity.get())
                    if idle >= idleSeconds {
                        if ProcessOwnership.processAlive(spawned.pid) {
                            endReason.set(.timeout)
                            _ = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
                        }
                        break
                    }
                    try? await Task.sleep(for: .seconds(min(idleSeconds - idle, 5)))
                }
            }

            // Hard total-duration backstop.
            Task {
                try? await Task.sleep(for: budget.totalDuration)
                if ProcessOwnership.processAlive(spawned.pid) {
                    endReason.set(.timeout)
                    _ = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
                }
            }
        }
    }

    // MARK: - Helpers

    private func mergeEnv(_ overrides: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for (k, v) in overrides { env[k] = v }
        return env
    }

    /// Decode `waitpid` status without relying on C macro availability in Swift.
    private static func waitStatusExitCode(_ status: Int32) -> Int32 {
        // WIFEXITED: low 7 bits zero; WEXITSTATUS: bits 8–15.
        if (status & 0o177) == 0 {
            return (status >> 8) & 0xff
        }
        return status
    }
}

// MARK: - Private plumbing (mirrors AgentOS SubprocessCommandRunner helpers)

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) {
        lock.lock(); data.append(chunk); lock.unlock()
    }
    func snapshot() -> Data {
        lock.lock(); defer { lock.unlock() }; return data
    }
    func byteCount() -> Int {
        lock.lock(); defer { lock.unlock() }; return data.count
    }
}

private final class LockedDateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func set(_ value: Date) { lock.lock(); self.value = value; lock.unlock() }
    func get() -> Date { lock.lock(); defer { lock.unlock() }; return value }
}

private final class ResumeOnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}

private final class EndReasonBox: @unchecked Sendable {
    enum Reason { case normal, timeout, cancel, bufferCap }
    private let lock = NSLock()
    private var reason: Reason = .normal
    func set(_ value: Reason) {
        lock.lock()
        if reason == .normal { reason = value }
        lock.unlock()
    }
    func get() -> Reason {
        lock.lock(); defer { lock.unlock() }; return reason
    }
}

private final class WatchdogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    func set(_ task: Task<Void, Never>) {
        lock.lock(); self.task = task; lock.unlock()
    }
    func cancel() {
        lock.lock(); let t = task; lock.unlock()
        t?.cancel()
    }
}

private func closePipe(_ fd: Int32?) {
    guard let fd, fd >= 0 else { return }
    close(fd)
}

private func makeReadSource(
    fd: Int32?,
    buffer: LockedDataBuffer,
    cap: Int,
    onOverflow: @escaping @Sendable () -> Void
) -> DispatchSourceRead? {
    guard let fd, fd >= 0 else { return nil }
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
    let overflowOnce = ResumeOnceBox()
    source.setEventHandler {
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        let n = read(fd, &chunk, chunk.count)
        if n > 0 {
            buffer.append(Data(chunk[0..<n]))
            if buffer.byteCount() > cap, overflowOnce.claim() { onOverflow() }
        }
    }
    source.resume()
    return source
}

private func makeStreamingReadSource(
    fd: Int32?,
    buffer: LockedDataBuffer,
    cap: Int,
    onChunk: @escaping @Sendable (Data) -> Void,
    onOverflow: @escaping @Sendable () -> Void
) -> DispatchSourceRead? {
    guard let fd, fd >= 0 else { return nil }
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
    let overflowOnce = ResumeOnceBox()
    source.setEventHandler {
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        let n = read(fd, &chunk, chunk.count)
        if n > 0 {
            let data = Data(chunk[0..<n])
            buffer.append(data)
            onChunk(data)
            if buffer.byteCount() > cap, overflowOnce.claim() { onOverflow() }
        }
    }
    source.resume()
    return source
}

#endif
