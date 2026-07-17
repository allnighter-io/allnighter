import Foundation
import Darwin
import AllnighterCore

/// Process-group ownership + heartbeat helpers for self-owning async team runs
/// (`docs/phases/Process_Ownership.md` PO-S01).
///
/// Law: every Allnighter-spawned process has a durable owner, a process group
/// (`setsid` / SETPGROUP), and a heartbeat file. Reconcile marks work dead ONLY
/// when the heartbeat is stale AND the owner pid is dead.
public enum ProcessOwnership {
    public static let heartbeatFileName = "heartbeat"
    public static let ownerFileName = "owner.pid"
    public static let runnerStdoutFileName = "runner.stdout"
    public static let runnerStderrFileName = "runner.stderr"
    public static let runnerRequestFileName = "runner_request.json"

    /// How often the owner touches `heartbeat` (mtime).
    public static let heartbeatIntervalSeconds: TimeInterval = 10
    /// Heartbeat older than this (or missing) counts as stale for reconcile.
    public static let heartbeatStaleAfterSeconds: TimeInterval = 60

    public static func heartbeatURL(in directory: URL) -> URL {
        directory.appendingPathComponent(heartbeatFileName)
    }

    public static func ownerURL(in directory: URL) -> URL {
        directory.appendingPathComponent(ownerFileName)
    }

    /// Create/update the heartbeat file so its mtime is "now".
    public static func touchHeartbeat(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = heartbeatURL(in: directory)
        let now = Date()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: url.path
            )
        } else {
            try Data().write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: url.path
            )
        }
    }

    public static func heartbeatModificationDate(in directory: URL) -> Date? {
        let url = heartbeatURL(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    /// Missing heartbeat is stale. Present heartbeat is stale when older than `threshold`.
    public static func isHeartbeatStale(
        in directory: URL,
        now: Date = Date(),
        threshold: TimeInterval = heartbeatStaleAfterSeconds
    ) -> Bool {
        guard let mtime = heartbeatModificationDate(in: directory) else { return true }
        return now.timeIntervalSince(mtime) > threshold
    }

    public static func writeOwnerPID(_ pid: Int32, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("\(pid)".utf8).write(to: ownerURL(in: directory), options: .atomic)
    }

    public static func readOwnerPID(in directory: URL) -> Int32? {
        guard let raw = try? String(contentsOf: ownerURL(in: directory), encoding: .utf8) else {
            return nil
        }
        return Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// True when `pid` names a live process. `kill(pid, 0)` returns 0 when we can
    /// signal it, or fails with `EPERM` when it exists but we may not — both mean
    /// alive; `ESRCH` means gone.
    public static func processAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Become a session leader so this process is its own process-group owner
    /// (`pgid == pid`). Safe to call when already a session leader (EPERM ignored).
    @discardableResult
    public static func becomeSessionLeader() -> Bool {
        if setsid() >= 0 { return true }
        return errno == EPERM
    }

    /// Terminate an entire process group. Spec: `kill(-pgid)` then SIGKILL after a
    /// short grace. Best-effort; ignores ESRCH.
    public static func terminateProcessGroup(of pid: Int32) {
        guard pid > 0 else { return }
        // Prefer the process group (runner is session/group leader). Fall back to
        // the pid alone if the group signal fails.
        _ = kill(-pid, SIGTERM)
        _ = kill(pid, SIGTERM)
        // Brief grace so cooperative shutdown can land before SIGKILL.
        usleep(200_000)
        _ = kill(-pid, SIGKILL)
        _ = kill(pid, SIGKILL)
    }

    /// Spawn a detached runner in its own process group with stdio redirected to
    /// files and optional working directory. Child must call `becomeSessionLeader()`
    /// at entry (macOS has no portable `setsid` binary).
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

        // argv: executable + arguments
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
