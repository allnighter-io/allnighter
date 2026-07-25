import Foundation
#if canImport(os)
import os
#endif

/// What the sandbox hand-off did, said out loud.
///
/// The hand-off host used to be completely silent: when a request was claimed and
/// then failed to start, nothing was written anywhere, so the cause of the
/// founder-facing failure was unrecoverable after the fact. This is the fix for
/// that specific hole — one line per lifecycle step, to the unified log (so
/// `log show --predicate 'process == "Allnighter"'` tells the whole story) and to
/// a plain file (so a test, or a founder without Console, can read it).
///
/// Deliberately not a logging framework: no levels, no categories to choose from,
/// no configuration. A hand-off either happened or it did not, and this says which.
public enum HandoffLog {
    #if canImport(os)
    private static let logger = Logger(subsystem: "com.allnighter.alln", category: "handoff")
    #endif

    /// Where the file copy lands. Injectable so tests never write to the real root.
    nonisolated(unsafe) public static var fileURL: URL? = AllnighterPaths.logs
        .appendingPathComponent("handoff.log", isDirectory: false)

    public static func event(_ message: String) {
        #if canImport(os)
        logger.log("\(message, privacy: .public)")
        #endif
        append(message)
    }

    private static func append(_ message: String) {
        guard let fileURL else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
