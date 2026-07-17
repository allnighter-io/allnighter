import Foundation
import Darwin
import AllnighterCore

/// Process-group ownership + progress-heartbeat helpers for self-owning async
/// team runs (`docs/phases/Process_Ownership.md` PO-S01 v2).
///
/// Law:
/// - Owner identity is `{pid, pgid?, startTimeTicks, kind}` — never a raw pid.
/// - Alive = pid alive AND start time matches (recycled pids read as dead).
/// - Death is identity-truth (immediate). Heartbeat is progress-truth only.
/// - PG-kill uses the **recorded** pgid, only on identity match; in-process
///   owners (no pgid) are never signalled by reconcile.
public enum ProcessOwnership {
    public static let heartbeatFileName = "heartbeat.json"
    /// Legacy empty-mtime heartbeat from PO-S01 v1 (still read for age).
    public static let legacyHeartbeatFileName = "heartbeat"
    public static let ownerFileName = "owner.json"
    /// Legacy raw-pid marker — never treated as a full identity (pid reuse = dead).
    public static let legacyOwnerFileName = "owner.pid"
    public static let runnerStdoutFileName = "runner.stdout"
    public static let runnerStderrFileName = "runner.stderr"
    public static let runnerRequestFileName = "runner_request.json"
    public static let runnerReadyFileName = "runner_ready.json"
    public static let runLockFileName = "run.lock"

    /// Timer floor for progress heartbeat touches (owner still alive + moving floor).
    public static let heartbeatIntervalSeconds: TimeInterval = 10
    /// Age of `lastProgressAt` above which status flags "alive but not moving".
    /// Never used to auto-reap.
    public static let progressStaleAfterSeconds: TimeInterval = 60
    /// How long the parent waits for the runner's accept handshake.
    public static let runnerReadyTimeoutSeconds: TimeInterval = 8
    public static let runnerReadyPollIntervalSeconds: TimeInterval = 0.05

    // MARK: - Owner identity

    public enum OwnerKind: String, Codable, Sendable, Equatable {
        /// Detached `team __runner` (process-group leader; may be PG-killed).
        case detachedRunner
        /// In-process save (Mac app, sync paths, unit tests). Never PG-killed.
        case inProcess
    }

    /// Durable owner-of-record. A raw pid alone is never an identity.
    public struct OwnerIdentity: Codable, Sendable, Equatable {
        public var pid: Int32
        /// Recorded process-group id. Nil for in-process owners — reconcile must
        /// never invent `pgid == pid` and signal.
        public var pgid: Int32?
        /// `kinfo_proc.kp_proc.p_starttime` as microseconds since epoch.
        public var startTimeTicks: Int64
        public var kind: OwnerKind

        public init(pid: Int32, pgid: Int32?, startTimeTicks: Int64, kind: OwnerKind) {
            self.pid = pid
            self.pgid = pgid
            self.startTimeTicks = startTimeTicks
            self.kind = kind
        }

        /// Build identity for the current process.
        public static func current(kind: OwnerKind, pgid: Int32? = nil) -> OwnerIdentity? {
            let pid = ProcessInfo.processInfo.processIdentifier
            guard let ticks = processStartTimeTicks(pid) else { return nil }
            let recordedPgid: Int32?
            switch kind {
            case .detachedRunner:
                recordedPgid = pgid ?? getpgrp()
            case .inProcess:
                recordedPgid = nil
            }
            return OwnerIdentity(pid: pid, pgid: recordedPgid, startTimeTicks: ticks, kind: kind)
        }
    }

    // MARK: - Progress heartbeat

    public struct ProgressHeartbeat: Codable, Sendable, Equatable {
        public var sequence: UInt64
        public var phase: String
        public var lastProgressAt: Date
        /// Last touch including the timer floor (may equal lastProgressAt).
        public var touchedAt: Date

        public init(sequence: UInt64, phase: String, lastProgressAt: Date, touchedAt: Date) {
            self.sequence = sequence
            self.phase = phase
            self.lastProgressAt = lastProgressAt
            self.touchedAt = touchedAt
        }
    }

    // MARK: - Runner handshake (truthful accept)

    public enum RunnerReadyOutcome: String, Codable, Sendable, Equatable {
        case accepted
        case refused
    }

    public struct RunnerReadyHandshake: Codable, Sendable, Equatable {
        public var outcome: RunnerReadyOutcome
        public var runId: String
        public var acceptedAt: Date?
        public var refusalCode: String?
        public var refusalMessage: String?
        public var refusalPreset: String?

        public init(
            outcome: RunnerReadyOutcome,
            runId: String,
            acceptedAt: Date? = nil,
            refusalCode: String? = nil,
            refusalMessage: String? = nil,
            refusalPreset: String? = nil
        ) {
            self.outcome = outcome
            self.runId = runId
            self.acceptedAt = acceptedAt
            self.refusalCode = refusalCode
            self.refusalMessage = refusalMessage
            self.refusalPreset = refusalPreset
        }

        public static func accepted(runId: String, at: Date) -> RunnerReadyHandshake {
            RunnerReadyHandshake(outcome: .accepted, runId: runId, acceptedAt: at)
        }

        public static func refused(runId: String, code: String, message: String, preset: String = "") -> RunnerReadyHandshake {
            RunnerReadyHandshake(
                outcome: .refused, runId: runId,
                refusalCode: code, refusalMessage: message, refusalPreset: preset
            )
        }
    }

    // MARK: - Paths

    public static func heartbeatURL(in directory: URL) -> URL {
        directory.appendingPathComponent(heartbeatFileName)
    }

    public static func legacyHeartbeatURL(in directory: URL) -> URL {
        directory.appendingPathComponent(legacyHeartbeatFileName)
    }

    public static func ownerURL(in directory: URL) -> URL {
        directory.appendingPathComponent(ownerFileName)
    }

    public static func legacyOwnerURL(in directory: URL) -> URL {
        directory.appendingPathComponent(legacyOwnerFileName)
    }

    public static func runnerReadyURL(in directory: URL) -> URL {
        directory.appendingPathComponent(runnerReadyFileName)
    }

    public static func runLockURL(in directory: URL) -> URL {
        directory.appendingPathComponent(runLockFileName)
    }

    // MARK: - Owner identity I/O

    public static func writeOwnerIdentity(_ identity: OwnerIdentity, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try CoreJSON.encode(identity).write(to: ownerURL(in: directory), options: .atomic)
        // Drop legacy raw-pid marker so readers never treat it as identity.
        try? FileManager.default.removeItem(at: legacyOwnerURL(in: directory))
    }

    public static func readOwnerIdentity(in directory: URL) -> OwnerIdentity? {
        let url = ownerURL(in: directory)
        if let data = try? Data(contentsOf: url),
           let identity = try? CoreJSON.decode(OwnerIdentity.self, from: data) {
            return identity
        }
        // Legacy owner.pid: raw pid is never a full identity. Treat as dead for
        // reconcile (cannot verify start time → recycled-pid hazard).
        return nil
    }

    /// True when the recorded identity still names the same live process.
    public static func isIdentityAlive(_ identity: OwnerIdentity) -> Bool {
        guard processAlive(identity.pid) else { return false }
        guard let liveTicks = processStartTimeTicks(identity.pid) else { return false }
        return liveTicks == identity.startTimeTicks
    }

    /// Owner of a non-terminal run is dead when missing, unreadable, or
    /// identity-verified dead. Legacy raw-pid markers count as dead.
    public static func isOwnerIdentityDead(in directory: URL) -> Bool {
        guard let identity = readOwnerIdentity(in: directory) else { return true }
        return !isIdentityAlive(identity)
    }

    // MARK: - Progress heartbeat I/O

    /// Record real progress (worker transition / output bytes). Bumps sequence.
    public static func recordProgress(in directory: URL, phase: String, now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = readProgressHeartbeat(in: directory)
        let next = ProgressHeartbeat(
            sequence: (previous?.sequence ?? 0) &+ 1,
            phase: phase,
            lastProgressAt: now,
            touchedAt: now
        )
        try CoreJSON.encode(next).write(to: heartbeatURL(in: directory), options: .atomic)
    }

    /// Timer-floor touch: refreshes `touchedAt` only; does not bump sequence or
    /// `lastProgressAt` (progress-truth stays honest).
    public static func touchHeartbeatFloor(in directory: URL, now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if var previous = readProgressHeartbeat(in: directory) {
            previous.touchedAt = now
            try CoreJSON.encode(previous).write(to: heartbeatURL(in: directory), options: .atomic)
        } else {
            let seed = ProgressHeartbeat(sequence: 0, phase: "accepted", lastProgressAt: now, touchedAt: now)
            try CoreJSON.encode(seed).write(to: heartbeatURL(in: directory), options: .atomic)
        }
    }

    public static func readProgressHeartbeat(in directory: URL) -> ProgressHeartbeat? {
        let url = heartbeatURL(in: directory)
        if let data = try? Data(contentsOf: url),
           let hb = try? CoreJSON.decode(ProgressHeartbeat.self, from: data) {
            return hb
        }
        return nil
    }

    public static func lastProgressAt(in directory: URL) -> Date? {
        if let hb = readProgressHeartbeat(in: directory) {
            return hb.lastProgressAt
        }
        // Legacy empty heartbeat: mtime is the only signal.
        let legacy = legacyHeartbeatURL(in: directory)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: legacy.path)
        return attrs?[.modificationDate] as? Date
    }

    /// Progress-stale flag for status surfaces — never auto-reaps.
    public static func isProgressStale(
        in directory: URL,
        now: Date = Date(),
        threshold: TimeInterval = progressStaleAfterSeconds
    ) -> Bool {
        guard let last = lastProgressAt(in: directory) else { return true }
        return now.timeIntervalSince(last) > threshold
    }

    // MARK: - Handshake I/O

    public static func writeRunnerReady(_ handshake: RunnerReadyHandshake, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try CoreJSON.encode(handshake).write(to: runnerReadyURL(in: directory), options: .atomic)
    }

    public static func readRunnerReady(in directory: URL) -> RunnerReadyHandshake? {
        guard let data = try? Data(contentsOf: runnerReadyURL(in: directory)),
              let handshake = try? CoreJSON.decode(RunnerReadyHandshake.self, from: data) else {
            return nil
        }
        return handshake
    }

    /// Block until the runner writes `runner_ready`, or timeout.
    public static func waitForRunnerReady(
        in directory: URL,
        timeout: TimeInterval = runnerReadyTimeoutSeconds,
        pollInterval: TimeInterval = runnerReadyPollIntervalSeconds
    ) -> RunnerReadyHandshake? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let handshake = readRunnerReady(in: directory) {
                return handshake
            }
            usleep(useconds_t(pollInterval * 1_000_000))
        }
        return readRunnerReady(in: directory)
    }

    // MARK: - Process helpers

    /// True when `pid` names a live process. `kill(pid, 0)` returns 0 when we can
    /// signal it, or fails with `EPERM` when it exists but we may not — both mean
    /// alive; `ESRCH` means gone.
    public static func processAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// `kinfo_proc.kp_proc.p_starttime` as microseconds since the Unix epoch.
    public static func processStartTimeTicks(_ pid: Int32) -> Int64? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let rc = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard rc == 0, size >= MemoryLayout<kinfo_proc>.stride else { return nil }
        let tv = info.kp_proc.p_starttime
        return Int64(tv.tv_sec) * 1_000_000 + Int64(tv.tv_usec)
    }

    /// Absolute path of the running executable via `_NSGetExecutablePath`.
    /// Never use argv[0]: `posix_spawn` does no PATH search, and chdir-before-exec
    /// makes relative argv[0] resolve against the new cwd.
    public static func currentExecutablePath() -> String? {
        var size: UInt32 = 4096
        var buffer = [CChar](repeating: 0, count: Int(size))
        while true {
            let rc = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
                guard let base = ptr.baseAddress else { return -1 }
                return _NSGetExecutablePath(base, &size)
            }
            if rc == 0 {
                let path = String(cString: buffer)
                return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            }
            // Buffer too small — size now holds the required length.
            guard size > 0, Int(size) > buffer.count else { return nil }
            buffer = [CChar](repeating: 0, count: Int(size))
        }
    }

    /// Become a session leader so this process is its own process-group owner
    /// (`pgid == pid`). Safe to call when already a session leader (EPERM ignored).
    @discardableResult
    public static func becomeSessionLeader() -> Bool {
        if setsid() >= 0 { return true }
        return errno == EPERM
    }

    /// Test hook: when set, `terminateProcessGroup(pgid:)` calls this instead of
    /// sending real signals. Used to prove recycled-pid / in-process paths never signal.
    nonisolated(unsafe) public static var terminateSignalHook: ((Int32) -> Void)?

    /// Terminate a recorded process group. Requires an explicit positive pgid —
    /// never invents `pgid == pid`. Best-effort; ignores ESRCH.
    public static func terminateProcessGroup(pgid: Int32) {
        guard pgid > 1 else { return } // refuse pid 0/-1 and init-adjacent
        if let hook = terminateSignalHook {
            hook(pgid)
            return
        }
        _ = kill(-pgid, SIGTERM)
        usleep(200_000)
        _ = kill(-pgid, SIGKILL)
    }

    /// Reconcile-safe kill: only when identity matches AND a pgid was recorded
    /// (detached runner). In-process / missing pgid → never signal.
    @discardableResult
    public static func terminateRecordedOwnerIfSafe(in directory: URL) -> Bool {
        guard let identity = readOwnerIdentity(in: directory) else { return false }
        // Only kill when identity still matches (or is already dead but we have
        // a recorded pgid from a just-died detached runner). Spec: PG-kill only
        // the recorded pgid, only on identity match. If already dead (pid gone
        // or recycled), still best-effort group kill for the recorded pgid when
        // kind is detachedRunner — the group may hold strays. Never for inProcess.
        guard identity.kind == .detachedRunner, let pgid = identity.pgid, pgid > 1 else {
            return false
        }
        // Identity match required when the pid is still alive (wrong start time =
        // recycled: do NOT signal that process's group).
        if processAlive(identity.pid) {
            guard isIdentityAlive(identity) else { return false }
        }
        terminateProcessGroup(pgid: pgid)
        return true
    }

    /// Per-run flock for explicit reconcile / cancel terminal writes.
    public static func withRunLock<T>(in directory: URL, _ body: () throws -> T) rethrows -> T {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = runLockURL(in: directory).path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return try body() }
        defer { close(fd) }
        _ = flock(fd, LOCK_EX)
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }

    /// Spawn a detached runner in its own process group with stdio redirected to
    /// files and optional working directory. Child must call `becomeSessionLeader()`
    /// at entry.
    ///
    /// Returns the child pid (also the intended process-group id after SETPGROUP).
    public static func spawnDetachedRunner(
        executablePath: String,
        arguments: [String],
        workingDirectory: String?,
        stdoutPath: String,
        stderrPath: String,
        extraEnvironment: [String: String] = [:]
    ) throws -> Int32 {
        var attr: posix_spawnattr_t?
        var fileActions: posix_spawn_file_actions_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        // Child becomes its own process group leader (pgid == pid).
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)

        // stdin <- /dev/null
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)

        // stdout/stderr -> files under the run directory
        for (fd, path) in [(STDOUT_FILENO, stdoutPath), (STDERR_FILENO, stderrPath)] {
            let flags = O_WRONLY | O_CREAT | O_TRUNC
            let mode: mode_t = 0o644
            let rc = posix_spawn_file_actions_addopen(&fileActions, fd, path, flags, mode)
            if rc != 0 {
                throw SpawnError.posix(rc, "open \(path)")
            }
        }

        if let workingDirectory, !workingDirectory.isEmpty {
            let rc = posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory)
            if rc != 0 {
                throw SpawnError.posix(rc, "chdir \(workingDirectory)")
            }
        }

        // argv: executable + arguments — executable must be absolute (_NSGetExecutablePath).
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(executablePath)]
        for arg in arguments {
            argv.append(strdup(arg))
        }
        argv.append(nil)
        defer {
            for ptr in argv where ptr != nil {
                free(ptr)
            }
        }

        // Environment: inherit + extras
        var env = ProcessInfo.processInfo.environment
        for (k, v) in extraEnvironment { env[k] = v }
        var envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer {
            for ptr in envp where ptr != nil {
                free(ptr)
            }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(
            &pid,
            executablePath,
            &fileActions,
            &attr,
            &argv,
            &envp
        )
        guard rc == 0 else {
            throw SpawnError.posix(rc, "posix_spawn \(executablePath)")
        }
        return pid
    }

    public enum SpawnError: Error, CustomStringConvertible {
        case posix(Int32, String)
        public var description: String {
            switch self {
            case .posix(let code, let context):
                return "\(context): \(String(cString: strerror(code))) (\(code))"
            }
        }
    }
}

/// Durable payload the detached runner reloads so parent and child share one
/// accepted run id without re-minting.
public struct AsyncTeamRunnerRequest: Codable, Sendable, Equatable {
    public var request: AsyncTeamStartRequest
    public var origin: RunOrigin
    public var acceptedAt: Date

    public init(request: AsyncTeamStartRequest, origin: RunOrigin, acceptedAt: Date) {
        self.request = request
        self.origin = origin
        self.acceptedAt = acceptedAt
    }
}
