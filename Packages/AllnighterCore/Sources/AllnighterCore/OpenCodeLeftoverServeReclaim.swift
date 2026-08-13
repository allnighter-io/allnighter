import Foundation

/// Reclaim a leftover `opencode serve` on :4096 after `opencode.json` changes
/// (or after a stale-model attach failure). Never stops `alln serve`.
///
/// Production inspects `ps -p <pid> -o command=` before signalling. Tests inject
/// a `Table` and must not reach a live listener, Ollama, or `alln serve`.
public enum OpenCodeLeftoverServeReclaim {
    public static let defaultPort = 4096

    public struct Table: Sendable {
        public var listenerPID: @Sendable (Int) -> Int32?
        public var commandLine: @Sendable (Int32) -> String?
        public var terminate: @Sendable (Int32) -> Void

        public init(
            listenerPID: @escaping @Sendable (Int) -> Int32?,
            commandLine: @escaping @Sendable (Int32) -> String?,
            terminate: @escaping @Sendable (Int32) -> Void
        ) {
            self.listenerPID = listenerPID
            self.commandLine = commandLine
            self.terminate = terminate
        }

        /// No live process table. Default under XCTest and when a caller omits a table.
        public static let inactive = Table(
            listenerPID: { _ in nil },
            commandLine: { _ in nil },
            terminate: { _ in }
        )

        /// Real `lsof` / `ps` / SIGTERM. Never the XCTest default.
        public static var production: Table {
            #if os(macOS)
            Table(
                listenerPID: { port in Self.lsofListenerPID(port: port) },
                commandLine: { pid in Self.psCommand(pid: pid) },
                terminate: { pid in Self.terminateProcess(pid) }
            )
            #else
            .inactive
            #endif
        }

        #if os(macOS)
        static func lsofListenerPID(port: Int) -> Int32? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-iTCP:\(port)", "-sTCP:LISTEN", "-t", "-n", "-P"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return nil
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            guard let first = text.split(whereSeparator: \.isNewline).first else { return nil }
            return Int32(first.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        /// Packet ops law: `ps -p <pid> -o command=` (equals suppresses the header).
        static func psCommand(pid: Int32) -> String? {
            guard pid > 0 else { return nil }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-p", String(pid), "-o", "command="]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return nil
            }
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        static func terminateProcess(_ pid: Int32) {
            guard pid > 0 else { return }
            kill(pid, SIGTERM)
            for _ in 0..<40 {
                if kill(pid, 0) != 0, errno != EPERM { return }
                usleep(50_000)
            }
            _ = kill(pid, SIGKILL)
        }
        #endif
    }

    public enum Decision: Equatable, Sendable {
        case idle
        case refuseAllnServe
        case reclaimOpenCodeServe
        case skipForeign
        case skipUnreadableCommand
    }

    public enum Outcome: Equatable, Sendable {
        case notAttempted
        case idle
        case refusedAllnServe(pid: Int32, command: String)
        case reclaimed(pid: Int32, command: String)
        case skippedForeign(pid: Int32, command: String)
        case skippedUnreadableCommand(pid: Int32)

        public var action: String? {
            switch self {
            case .notAttempted: return nil
            case .idle: return "idle"
            case .refusedAllnServe: return "refused_alln_serve"
            case .reclaimed: return "reclaimed"
            case .skippedForeign: return "skipped_foreign"
            case .skippedUnreadableCommand: return "skipped_unreadable"
            }
        }

        public var pid: Int? {
            switch self {
            case .notAttempted, .idle: return nil
            case .refusedAllnServe(let pid, _),
                 .reclaimed(let pid, _),
                 .skippedForeign(let pid, _),
                 .skippedUnreadableCommand(let pid):
                return Int(pid)
            }
        }
    }

    /// Table used when the caller did not inject one. XCTest never gets production.
    public static func resolvedTable(
        override: Table?,
        isTestHost: Bool = AllnighterSupportRoot.isRunningUnderTestHost
    ) -> Table {
        if let override { return override }
        if isTestHost { return .inactive }
        return .production
    }

    public static func decide(commandLine: String?) -> Decision {
        guard let command = normalizedCommandLine(commandLine) else {
            return .skipUnreadableCommand
        }
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        if isAllnServe(tokens) { return .refuseAllnServe }
        if isOpenCodeServe(tokens) { return .reclaimOpenCodeServe }
        return .skipForeign
    }

    public static func reclaim(
        port: Int = defaultPort,
        table: Table
    ) -> Outcome {
        guard let pid = table.listenerPID(port), pid > 0 else { return .idle }
        let command = table.commandLine(pid)
        switch decide(commandLine: command) {
        case .idle:
            return .idle
        case .refuseAllnServe:
            return .refusedAllnServe(pid: pid, command: command ?? "")
        case .reclaimOpenCodeServe:
            table.terminate(pid)
            return .reclaimed(pid: pid, command: command ?? "")
        case .skipForeign:
            return .skippedForeign(pid: pid, command: command ?? "")
        case .skipUnreadableCommand:
            return .skippedUnreadableCommand(pid: pid)
        }
    }

    /// `opencode session error: Model not found: <label>` from a warm serve whose
    /// provider list was cached before `opencode.json` gained the tag.
    public static func isStaleModelNotFoundReason(_ reason: String?) -> Bool {
        guard let reason, !reason.isEmpty else { return false }
        let lower = reason.lowercased()
        return lower.contains("opencode session error:")
            && lower.contains("model not found:")
    }

    static func normalizedCommandLine(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let lines = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.uppercased() != "COMMAND" }
        guard let last = lines.last, !last.isEmpty else { return nil }
        return last
    }

    static func isAllnServe(_ tokens: [String]) -> Bool {
        guard let index = tokens.firstIndex(where: { lastPathComponent($0) == "alln" }) else {
            return false
        }
        return tokens.dropFirst(index + 1).contains("serve")
    }

    static func isOpenCodeServe(_ tokens: [String]) -> Bool {
        guard let index = tokens.firstIndex(where: { lastPathComponent($0) == "opencode" }) else {
            return false
        }
        return tokens.dropFirst(index + 1).contains("serve")
    }

    static func lastPathComponent(_ token: String) -> String {
        URL(fileURLWithPath: token).lastPathComponent
    }
}
