import Foundation

#if canImport(Darwin)
import Darwin
#endif

// MARK: - Probe executor seam

/// One tier-3 PTY capture request. Callers pass every clock value — no `Date()` inside.
public struct CapacityProbeRequest: Sendable, Equatable {
    public let source: String
    public let now: Date
    public let timeout: TimeInterval

    public init(source: String, now: Date, timeout: TimeInterval = CapacityProbe.defaultTimeout) {
        self.source = source
        self.now = now
        self.timeout = timeout
    }
}

/// Injectable seam so tests can prove bare `alln capacity` never spawns,
/// and can feed fail-closed / fixture outcomes without a real vendor CLI.
public protocol CapacityProbeExecuting: Sendable {
    /// Capture + parse one source. Always returns at least one window.
    /// Never throws. Always terminates any child it started.
    func execute(_ request: CapacityProbeRequest) -> [CapacityWindow]
}

/// Live PTY probes against vendor CLIs on PATH / known install locations.
public struct LiveCapacityProbeExecutor: CapacityProbeExecuting, Sendable {
    public init() {}

    public func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
        CapacityProbe.windows(
            source: request.source,
            now: request.now,
            timeout: request.timeout
        )
    }
}

// MARK: - CapacityProbe

/// Tier-3 PTY one-shot into a vendor usage TUI.
///
/// Per driver: spawn CLI in a PTY, send `/usage`, capture rendered text, hand
/// to the existing pure parser, always terminate the child (including timeout).
///
/// Fail closed: spawn / timeout / empty / parse → `unknown` with a reason.
/// **Never** invents a percentage. **Never** returns `vendorExposesNothing` for
/// a seat we ship a parser for.
///
/// Lives at the acquisition boundary only — pure types (`CapacityWindow`,
/// projection, strip) take no IO.
public enum CapacityProbe {

    /// Per-probe wall-clock budget. One slow CLI must not hang the strip.
    public static let defaultTimeout: TimeInterval = 20

    /// Tier-3 seats this probe knows how to drive today.
    /// Claude is intentionally absent: `/status` → Usage tab needs tab
    /// navigation that is not reliable enough to ship yet.
    public static let probeableSources: [String] = [
        "agy",
        "kimi",
        "cursor_agent",
    ]

    /// Candidate executable names per source (PATH order).
    public static let commandCandidates: [String: [String]] = [
        "agy": ["agy"],
        "kimi": ["kimi"],
        "cursor_agent": ["agent", "cursor-agent"],
    ]

    /// Home-relative known install paths (checked when PATH misses).
    public static let knownHomeRelativePaths: [String: [String]] = [
        "agy": [".local/bin/agy"],
        "kimi": [".kimi-code/bin/kimi", ".local/bin/kimi"],
        "cursor_agent": [".local/bin/agent", ".local/bin/cursor-agent"],
    ]

    /// Slash command bytes sent after the TUI is ready.
    public static let usageCommand = "/usage"

    // MARK: Public entry

    /// Probe one source and return normalized windows (or a single unknown).
    ///
    /// - Parameters:
    ///   - source: Bench source id (`agy`, `kimi`, `cursor_agent`).
    ///   - now: Observation stamp for parse + unknown reasons.
    ///   - timeout: Hard wall-clock budget for the whole probe.
    ///   - workingDirectory: Child cwd (default: process cwd). Trusted workspaces
    ///     avoid agy "trust this folder" dialogs.
    ///   - pathEnvironment: PATH string for binary resolution (default: real PATH).
    ///   - homeDirectory: Home for known-path fallbacks (default: real home).
    ///   - executableOverride: Force a specific binary (tests: `/bin/sleep`).
    public static func windows(
        source: String,
        now: Date,
        timeout: TimeInterval = defaultTimeout,
        workingDirectory: String? = nil,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        executableOverride: String? = nil
    ) -> [CapacityWindow] {
        #if os(macOS)
        guard probeableSources.contains(source) else {
            // Unknown or deferred seat (claude) — honest never-sampled.
            return [unknown(source: source, reason: .neverSampled, now: now)]
        }

        let executable: String
        if let executableOverride {
            executable = executableOverride
        } else if let resolved = resolveExecutable(
            source: source,
            pathEnvironment: pathEnvironment,
            homeDirectory: homeDirectory
        ) {
            executable = resolved
        } else {
            return [unknown(source: source, reason: .parserFailed(observedAt: now), now: now)]
        }

        let cwd = workingDirectory
            ?? FileManager.default.currentDirectoryPath
        let capture = captureUsageRender(
            executable: executable,
            workingDirectory: cwd,
            timeout: timeout
        )

        switch capture {
        case .spawnFailed, .timeout, .empty:
            return [unknown(source: source, reason: .parserFailed(observedAt: now), now: now)]
        case .captured(let text):
            let parsed = parse(source: source, renderText: text, now: now)
            if parsed.isEmpty {
                return [unknown(source: source, reason: .parserFailed(observedAt: now), now: now)]
            }
            return parsed
        }
        #else
        // iOS / non-macOS: no PTY vendor CLIs. Fail closed, never invent.
        return [unknown(source: source, reason: .neverSampled, now: now)]
        #endif
    }

    /// Parse already-captured render text through the driver's pure extractor.
    /// Public for the Works Test seam (fixture → parser without a live spawn).
    public static func parse(
        source: String,
        renderText: String,
        now: Date
    ) -> [CapacityWindow] {
        switch source {
        case "agy":
            return AgyCapacityLog.capacityWindows(fromRender: renderText, observedAt: now)
        case "kimi":
            return KimiCapacityLog.capacityWindows(fromRender: renderText, observedAt: now)
        case "cursor_agent":
            return CursorCapacityLog.capacityWindows(fromRender: renderText, observedAt: now)
        default:
            return []
        }
    }

    /// Resolve the vendor binary for a source. Nil → spawn cannot start.
    public static func resolveExecutable(
        source: String,
        pathEnvironment: String?,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        fileManager: FileManager = .default
    ) -> String? {
        let names = commandCandidates[source] ?? [source]
        if let pathEnvironment {
            for name in names {
                if let hit = InstallCLI.resolveOnPath(
                    command: name,
                    pathEnvironment: pathEnvironment,
                    fileManager: fileManager
                ) {
                    return hit
                }
            }
        }
        let relatives = knownHomeRelativePaths[source] ?? []
        for rel in relatives {
            let url = homeDirectory.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir),
                  !isDir.boolValue,
                  fileManager.isExecutableFile(atPath: url.path)
            else { continue }
            return url.resolvingSymlinksInPath().standardizedFileURL.path
        }
        return nil
    }

    // MARK: - Capture result

    enum CaptureResult: Sendable, Equatable {
        case captured(String)
        case spawnFailed
        case timeout
        case empty
    }

    // MARK: - PTY capture (macOS)

    #if os(macOS)
    /// Spawn `executable` in a PTY, send `/usage`, capture screen text, always kill.
    static func captureUsageRender(
        executable: String,
        workingDirectory: String,
        timeout: TimeInterval
    ) -> CaptureResult {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            return .spawnFailed
        }

        // Readable TUI geometry — narrow/short PTYs truncate bars and labels.
        var ws = winsize(ws_row: 45, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &ws)

        // Non-blocking master so select-based drain cannot hang a read.
        let masterFlags = fcntl(master, F_GETFL)
        if masterFlags >= 0 {
            _ = fcntl(master, F_SETFL, masterFlags | O_NONBLOCK)
        }

        let pid: pid_t
        do {
            pid = try spawnPTYChild(
                executable: executable,
                workingDirectory: workingDirectory,
                slave: slave
            )
        } catch {
            close(master)
            close(slave)
            return .spawnFailed
        }

        // Parent keeps master only; child owns slave via dup2.
        close(slave)

        defer {
            terminateProcessGroup(pid)
            close(master)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        var usageSent = false
        var sawReady = false
        var sawUsagePane = false

        // 1) Wait for the interactive prompt / boot chrome.
        let readyMarkers = ["shortcuts", "session:", "cursor agent", "│ >", "\n> ", "tip:"]
        while Date() < deadline {
            appendAvailable(from: master, into: &buffer)
            let text = decodeAndStrip(buffer)
            let lower = text.lowercased()
            if readyMarkers.contains(where: { lower.contains($0) }) {
                sawReady = true
                break
            }
            if childExited(pid) {
                appendAvailable(from: master, into: &buffer)
                break
            }
            _ = waitBrief(0.05)
        }

        guard sawReady || !buffer.isEmpty else {
            return buffer.isEmpty ? .timeout : .empty
        }

        // Brief settle so autocomplete / chrome finishes painting.
        _ = waitBrief(0.5)
        appendAvailable(from: master, into: &buffer)

        // 2) Send /usage (all-at-once). Autocomplete menus accept Enter next.
        if Date() < deadline, !childExited(pid) {
            let cmd = Array("\(usageCommand)".utf8)
            _ = cmd.withUnsafeBufferPointer { ptr in
                write(master, ptr.baseAddress!, ptr.count)
            }
            usageSent = true
            _ = waitBrief(0.45)
            appendAvailable(from: master, into: &buffer)
            // Confirm selection / submit.
            let cr: [UInt8] = [0x0D]
            _ = cr.withUnsafeBufferPointer { ptr in
                write(master, ptr.baseAddress!, ptr.count)
            }
        }

        // 3) Drain until usage markers appear or budget expires.
        let usageMarkers = [
            "weekly limit", "five hour", "5h limit", "plan usage",
            "models & quota", "% used", "% remaining", "on-demand",
            "monthly plan", "included", "resets ",
        ]
        while Date() < deadline {
            appendAvailable(from: master, into: &buffer)
            let lower = decodeAndStrip(buffer).lowercased()
            if usageMarkers.contains(where: { lower.contains($0) }) {
                sawUsagePane = true
                // Extra drain so multi-pool / multi-line panes finish.
                _ = waitBrief(0.9)
                appendAvailable(from: master, into: &buffer)
                break
            }
            if childExited(pid) {
                appendAvailable(from: master, into: &buffer)
                break
            }
            _ = waitBrief(0.08)
        }

        let finalText = decodeAndStrip(buffer)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if finalText.isEmpty {
            return usageSent ? .empty : .timeout
        }
        // Even without marker match, hand text to the parser — fail closed there.
        _ = sawUsagePane
        return .captured(finalText)
    }

    private static func spawnPTYChild(
        executable: String,
        workingDirectory: String,
        slave: Int32
    ) throws -> pid_t {
        var attr: posix_spawnattr_t?
        var fileActions: posix_spawn_file_actions_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        // Own process group so terminate can killpg without orphans.
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        posix_spawnattr_setsigdefault(&attr, &defaultSignals)
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        posix_spawnattr_setflags(
            &attr,
            Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        )
        posix_spawnattr_setpgroup(&attr, 0)

        // stdio → slave PTY
        for fd: Int32 in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            let rc = posix_spawn_file_actions_adddup2(&fileActions, slave, fd)
            if rc != 0 { throw SpawnError(rc: rc, context: "dup2 pty → \(fd)") }
        }
        // Close master/slave extras in child is handled by close-on-exec norms;
        // still close the slave fd number itself after dup.
        _ = posix_spawn_file_actions_addclose(&fileActions, slave)

        if !workingDirectory.isEmpty {
            let rc = posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory)
            if rc != 0 { throw SpawnError(rc: rc, context: "chdir \(workingDirectory)") }
        }

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = env["COLORTERM"] ?? "truecolor"
        // Do not force CI/non-interactive — these TUIs need a real interactive session.
        env.removeValue(forKey: "CI")
        env.removeValue(forKey: "NO_COLOR")

        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(executable), nil]
        defer { for p in argv where p != nil { free(p) } }

        var envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer { for p in envp where p != nil { free(p) } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executable, &fileActions, &attr, &argv, &envp)
        if rc != 0 { throw SpawnError(rc: rc, context: "posix_spawn \(executable)") }
        return pid
    }

    private struct SpawnError: Error {
        let rc: Int32
        let context: String
    }

    private static func terminateProcessGroup(_ pid: pid_t) {
        guard pid > 0 else { return }
        // SIGTERM the group first; escalate to SIGKILL if it lingers.
        _ = killpg(pid, SIGTERM)
        let graceDeadline = Date().addingTimeInterval(0.6)
        while Date() < graceDeadline {
            if childExited(pid) { return }
            _ = waitBrief(0.05)
        }
        _ = killpg(pid, SIGKILL)
        // Reap.
        var status: Int32 = 0
        _ = waitpid(pid, &status, WNOHANG)
        _ = waitBrief(0.05)
        _ = waitpid(pid, &status, WNOHANG)
    }

    private static func childExited(_ pid: pid_t) -> Bool {
        var status: Int32 = 0
        let rc = waitpid(pid, &status, WNOHANG)
        return rc == pid || (rc < 0 && errno == ECHILD)
    }

    private static func appendAvailable(from master: Int32, into buffer: inout Data) {
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(master, &chunk, chunk.count)
            if n > 0 {
                buffer.append(contentsOf: chunk[0..<n])
                continue
            }
            break
        }
    }

    private static func waitBrief(_ seconds: TimeInterval) -> Bool {
        var ts = timespec(
            tv_sec: time_t(seconds),
            tv_nsec: Int((seconds - floor(seconds)) * 1_000_000_000)
        )
        _ = nanosleep(&ts, nil)
        return true
    }

    private static func decodeAndStrip(_ data: Data) -> String {
        let raw = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        return stripANSI(raw)
    }

    private static func stripANSI(_ input: String) -> String {
        guard input.contains("\u{001B}") else { return input }
        var s = input
        // CSI sequences
        s = s.replacingOccurrences(
            of: #"\x1B\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
        // OSC sequences (BEL or ST terminated)
        s = s.replacingOccurrences(
            of: #"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)"#,
            with: "",
            options: .regularExpression
        )
        // Other ESC-lead singles
        s = s.replacingOccurrences(
            of: #"\x1B."#,
            with: "",
            options: .regularExpression
        )
        return s
    }
    #endif

    // MARK: - Unknown helper

    static func unknown(
        source: String,
        reason: CapacityUnknownReason,
        now: Date
    ) -> CapacityWindow {
        CapacityWindow.unknown(
            reason: reason,
            source: source,
            scope: .weekly,
            observedAt: now,
            sourceTier: .tuiProbe
        )
    }
}
