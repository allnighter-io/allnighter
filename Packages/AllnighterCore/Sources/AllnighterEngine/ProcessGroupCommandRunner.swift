import Foundation
import Darwin
import AllnighterCore

#if os(macOS) || os(Linux)

/// Process-group-leader command runner for PO-S02 / PO-F1: every worker CLI is
/// spawned via `ProcessOwnership.spawnProcessGroupLeader` (`posix_spawn` +
/// `POSIX_SPAWN_SETPGROUP`), identity recorded for turn kill, and termination
/// always routes through `ProcessOwnership.terminateProcessGroup` /
/// identity-checked helpers — never a second kill implementation and never
/// invents `pgid == pid` after the fact.
///
/// **PO-F1 progress-truth:** the streaming stall watchdog consumes
/// `lastProgressAt` (spawn / stdout·stderr bytes / exit, plus any external
/// `recordProgress` into the turn directory), not output silence. Stall budget
/// is still the `timeout` argument (same configurable knob as before; default
/// still comes from the caller / manifest — this runner does not change it).
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

    /// Stall budget extraction (matches prior idle-timeout math). Whole seconds
    /// from `Duration`, floor of 1s. Configurable only via the `timeout` arg —
    /// default is not owned here.
    public static func stallBudgetSeconds(from timeout: Duration) -> TimeInterval {
        max(Double(timeout.components.seconds), 1)
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
        let progress = ProgressTracker()
        progress.note(phase: "spawned")

        let outSource = makeReadSource(
            fd: spawned.stdoutReadFD, buffer: outBuffer, cap: budget.maxBufferedBytes,
            onBytes: { progress.note(phase: "output", throttleDisk: true) }
        ) {
            endReason.set(.bufferCap)
            _ = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
        }
        let errSource = makeReadSource(
            fd: spawned.stderrReadFD, buffer: errBuffer, cap: budget.maxBufferedBytes,
            onBytes: { progress.note(phase: "output", throttleDisk: true) }
        ) {
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
                    progress.note(phase: "exited")
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

                // Non-streaming: hard total wait for `timeout` (not silence-based).
                // Progress is still recorded for turn observability / relay surfaces.
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
            let progress = ProgressTracker()
            progress.note(phase: "spawned")
            let resumer = ResumeOnceBox()

            continuation.yield(.started(startedAt: Date()))

            let onOverflow: @Sendable () -> Void = {
                endReason.set(.bufferCap)
                _ = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
            }

            let outSource = makeStreamingReadSource(
                fd: spawned.stdoutReadFD, buffer: outBuffer, cap: budget.maxBufferedBytes,
                onChunk: { data in
                    progress.note(phase: "output", throttleDisk: true)
                    continuation.yield(.stdout(data))
                },
                onOverflow: onOverflow
            )
            let errSource = makeStreamingReadSource(
                fd: spawned.stderrReadFD, buffer: errBuffer, cap: budget.maxBufferedBytes,
                onChunk: { data in
                    progress.note(phase: "output", throttleDisk: true)
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
                progress.note(phase: "exited")
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

            // PO-F1: progress-truth stall watchdog (replaces output-silence).
            // Budget is still `timeout` — same configurable knob as the old idle timer.
            let stallBudget = Self.stallBudgetSeconds(from: timeout)
            Task {
                while ProcessOwnership.processAlive(spawned.pid) {
                    let last = progress.effectiveLastProgressAt()
                    let alive = ProcessOwnership.isIdentityAlive(identity)
                    switch ProcessOwnership.classifyProgressStall(
                        identityAlive: alive,
                        lastProgressAt: last,
                        stallBudgetSeconds: stallBudget
                    ) {
                    case .progressing:
                        // Poll frequently enough that durable progress touches (and
                        // sub-second mtime) land before the budget elapses.
                        let age = last.map { Date().timeIntervalSince($0) } ?? stallBudget
                        let remaining = max(stallBudget - age, 0.05)
                        let sleep = min(remaining, 0.2)
                        try? await Task.sleep(for: .seconds(sleep))
                    case .stalled:
                        if ProcessOwnership.processAlive(spawned.pid) {
                            endReason.set(.timeout)
                            _ = ProcessOwnership.terminateOwnerIdentityIfSafe(identity)
                        }
                        return
                    case .identityDead:
                        // S02 reconcile owns dead owners; waitpid finishes the stream.
                        return
                    }
                }
            }

            // Hard total-duration backstop (unchanged).
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

/// In-memory + durable progress tracker for PO-F1. Updates `lastProgressAt` on
/// spawn / output bytes / exit, writes into the active turn directory when set,
/// and merges external disk progress (other code touching `recordProgress`).
private final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var memoryLast: Date = Date()
    private var lastDiskWrite: Date = .distantPast
    /// Throttle durable output writes so chatty workers don't thrash heartbeat.json.
    private static let diskThrottleSeconds: TimeInterval = 0.5

    func note(phase: String, throttleDisk: Bool = false, now: Date = Date()) {
        lock.lock()
        memoryLast = now
        let shouldWrite: Bool
        if throttleDisk {
            shouldWrite = now.timeIntervalSince(lastDiskWrite) >= Self.diskThrottleSeconds
        } else {
            shouldWrite = true
        }
        if shouldWrite { lastDiskWrite = now }
        lock.unlock()
        if shouldWrite {
            ProcessOwnership.recordTurnProgress(phase: phase, now: now)
        }
    }

    /// Max of in-memory progress, durable `lastProgressAt`, and heartbeat file mtime.
    /// Mtime is included because CoreJSON `.iso8601` floors Date to whole seconds —
    /// with short stall budgets that floor can make a just-written heartbeat look stale.
    /// (Status surfaces still use encoded `lastProgressAt` so intentional backdating
    /// for `isProgressStale` tests stays honest.)
    func effectiveLastProgressAt() -> Date? {
        lock.lock()
        let mem = memoryLast
        lock.unlock()
        var best = mem
        guard let dir = ProcessOwnership.TurnOwnerDirectory.shared.get() else { return best }
        if let disk = ProcessOwnership.lastProgressAt(in: dir) {
            best = max(best, disk)
        }
        let url = ProcessOwnership.heartbeatURL(in: dir)
        if let mtime = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date {
            best = max(best, mtime)
        }
        return best
    }
}

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
    onBytes: (@Sendable () -> Void)? = nil,
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
            onBytes?()
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
