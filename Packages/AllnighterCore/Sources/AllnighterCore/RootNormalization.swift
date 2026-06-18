import Foundation

/// Core-owned, tested Project-root normalization (PRJ-S00).
///
/// Produces a stable duplicate-detection `key` and a separate user-facing
/// `displayPath`. The same normalized local root must not create duplicate active
/// Projects; nested paths are NOT inferred to be the same Project (their keys
/// differ). No git inspection here — observation only.
public enum RootNormalization {
    public struct Normalized: Equatable, Sendable {
        /// User-facing path: `~` expanded and standardized (`.`/`..` collapsed),
        /// but symlinks left as the user typed them.
        public let displayPath: String
        /// Duplicate-detection key: display path with symlinks resolved where the
        /// platform can do so safely. Two Projects with the same key are the same root.
        public let key: String
        public init(displayPath: String, key: String) {
            self.displayPath = displayPath
            self.key = key
        }
    }

    /// Normalize a user-entered path. Pure and deterministic for a given filesystem.
    public static func normalize(_ path: String) -> Normalized {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let display = url.standardizedFileURL.path
        // resolvingSymlinksInPath resolves existing symlink components; for a
        // missing path it standardizes without inventing anything.
        let key = url.resolvingSymlinksInPath().standardizedFileURL.path
        return Normalized(displayPath: display, key: key)
    }

    /// Two raw paths refer to the same Project root iff their normalized keys match.
    public static func sameRoot(_ a: String, _ b: String) -> Bool {
        normalize(a).key == normalize(b).key
    }

    /// Observe (never invent) the availability of a normalized root key.
    public static func observeRootState(key: String, fileManager: FileManager = .default) -> RootState {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: key, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing
        }
        guard fileManager.isReadableFile(atPath: key) else {
            return .permissionDenied
        }
        return .available
    }
}
