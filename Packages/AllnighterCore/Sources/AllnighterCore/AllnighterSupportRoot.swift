import Foundation

/// Core-owned support-dir resolution (mirrors `AllnighterEngine.AllnighterPaths.support`).
/// Catalog + roster persistence in Core must honor `ALLNIGHTER_SUPPORT_DIR` the same
/// way engine stores do — otherwise isolated config homes split roster state.
public enum AllnighterSupportRoot {
    public static var support: URL {
        if let override = ProcessInfo.processInfo.environment["ALLNIGHTER_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }

        // Codex's managed filesystem sandbox permits a workspace and its temp
        // directory, but deliberately denies `~/Library/Application Support`.
        // A journal is an acceptance boundary, so silently falling through to
        // the denied root makes otherwise read-only runs impossible. Keep the
        // normal macOS location outside Codex; inside a Codex sandbox use a
        // stable per-thread temp root. An explicit ALLNIGHTER_SUPPORT_DIR always
        // wins, including when a caller wants a root in its writable repository.
        if let threadID = ProcessInfo.processInfo.environment["CODEX_THREAD_ID"], !threadID.isEmpty,
           ProcessInfo.processInfo.environment["CODEX_SANDBOX"] != nil {
            let safeThreadID = threadID.unicodeScalars.map { scalar -> Character in
                switch scalar.value {
                case 45, 48...57, 65...90, 97...122: return Character(String(scalar))
                default: return "_"
                }
            }
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("Allnighter-Codex", isDirectory: true)
                .appendingPathComponent(String(safeThreadID), isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Allnighter", isDirectory: true)
    }

    public static var config: URL {
        support.appendingPathComponent("Config", isDirectory: true)
    }
}
