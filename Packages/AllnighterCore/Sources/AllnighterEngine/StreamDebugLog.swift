import Foundation

/// Local-only debug log for the streaming pipeline. Records what each CLI ACTUALLY
/// emits (raw stdout/stderr chunks) next to what the parser made of it and the final
/// outcome — so a missing/garbled stream can be diagnosed from one real run instead
/// of guessing against spec samples.
///
/// Writes to `~/Library/Application Support/Allnighter/Logs/streaming.log`. Enabled
/// unless `ALLNIGHTER_STREAM_DEBUG=0`. Sensitive (it contains answer text), so it is
/// strictly local and never relayed — same rule as partial chat text.
public enum StreamDebugLog {
    nonisolated(unsafe) private static let lock = NSLock()

    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["ALLNIGHTER_STREAM_DEBUG"] != "0"
    }

    public static var fileURL: URL {
        AllnighterPaths.support.appendingPathComponent("Logs/streaming.log")
    }

    /// Append one line with a timestamp. No-op when disabled.
    public static func log(_ message: String) {
        guard isEnabled else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        lock.lock()
        defer { lock.unlock() }
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// Truncate a long payload for readability (raw chunks can be large).
    public static func clip(_ text: String, _ max: Int = 400) -> String {
        text.count <= max ? text : String(text.prefix(max)) + "…(+\(text.count - max) chars)"
    }
}
