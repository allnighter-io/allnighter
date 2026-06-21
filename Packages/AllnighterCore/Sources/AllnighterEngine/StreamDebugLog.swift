import Foundation

/// Local-only debug log for the streaming pipeline. Records what each CLI ACTUALLY
/// emits (raw stdout/stderr chunks) next to what the parser made of it and the final
/// outcome — so a missing/garbled stream can be diagnosed from one real run.
///
/// Writes to `~/Library/Application Support/Allnighter/Logs/streaming.log`.
///
/// RLS-S02: this is OFF by default. It used to be on unless explicitly disabled, and it
/// did a synchronous `FileHandle` open/seek/write/close PER stdout chunk and PER parsed
/// event — thousands of blocking file ops per run, directly on the stream hot path, while
/// also recording sensitive answer/prompt text. Now it is opt-in per run via
/// `ALLNIGHTER_STREAM_DEBUG=1`, the message is only built when enabled (`@autoclosure`),
/// and the enabled path reuses one append handle instead of reopening per line.
public enum StreamDebugLog {
    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) private static var openedURL: URL?
    nonisolated(unsafe) private static let stamper = ISO8601DateFormatter()

    /// Opt-in only: `ALLNIGHTER_STREAM_DEBUG=1` enables; anything else (incl. unset) is off.
    /// Pure for testing — the default must be OFF so the hot path pays nothing.
    static func enabled(envValue: String?) -> Bool { envValue == "1" }

    public static var isEnabled: Bool {
        enabled(envValue: ProcessInfo.processInfo.environment["ALLNIGHTER_STREAM_DEBUG"])
    }

    public static var fileURL: URL {
        AllnighterPaths.support.appendingPathComponent("Logs/streaming.log")
    }

    /// Append one timestamped line. No-op (and no message construction) when disabled.
    public static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        lock.lock()
        defer { lock.unlock() }
        // Format under the lock — ISO8601DateFormatter is not concurrency-safe.
        let line = "[\(stamper.string(from: Date()))] \(text)\n"
        openHandleLocked()?.write(Data(line.utf8))
    }

    /// Open the append handle once and cache it (caller holds `lock`).
    private static func openHandleLocked() -> FileHandle? {
        let url = fileURL
        if let handle, openedURL == url { return handle }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        let opened = try? FileHandle(forWritingTo: url)
        opened?.seekToEndOfFile()
        handle = opened
        openedURL = url
        return opened
    }

    /// Truncate a long payload for readability (raw chunks can be large).
    public static func clip(_ text: String, _ max: Int = 400) -> String {
        text.count <= max ? text : String(text.prefix(max)) + "…(+\(text.count - max) chars)"
    }
}
