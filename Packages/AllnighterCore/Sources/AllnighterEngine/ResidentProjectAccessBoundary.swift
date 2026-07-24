import Foundation

/// The resident coordinator is deliberately not allowed to dereference a raw
/// project path inside a macOS privacy-protected home directory. Doing so can
/// trigger a Documents/Desktop/etc. dialog in an otherwise unattended run.
///
/// CPH-3 will replace this temporary fail-closed boundary with an
/// host-authorized, provenance-recorded workspace mirror. Until then, refusing
/// the request is safer and more honest than asking the operating system for
/// surprise access. This classifier is lexical only: it performs no I/O and
/// therefore cannot itself trigger TCC.
public enum ResidentProjectAccessBoundary {
    public static let refusalCode = "PROJECT_ACCESS_BRIDGE_REQUIRED"

    private static let protectedHomeDirectories: Set<String> = [
        "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures",
    ]

    /// Returns a user-actionable refusal when `path` is inside a protected
    /// top-level home directory. Relative paths are also refused because their
    /// resolution depends on the resident's ambient working directory.
    public static func refusalMessage(
        forRawProjectPath path: String,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String? {
        guard !path.isEmpty else { return nil }
        guard path.hasPrefix("/") else {
            return "resident project execution requires an authorized project-byte bridge; relative project paths are not safe"
        }

        // `standardizedFileURL` is lexical (unlike resolvingSymlinksInPath), so
        // the admission check never probes a protected directory on its own.
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let normalizedHome = URL(fileURLWithPath: homeDirectory).standardizedFileURL.path
        let prefix = normalizedHome.hasSuffix("/") ? normalizedHome : normalizedHome + "/"
        guard normalizedPath.hasPrefix(prefix) else { return nil }

        let suffix = String(normalizedPath.dropFirst(prefix.count))
        guard let topLevel = suffix.split(separator: "/", maxSplits: 1).first,
              protectedHomeDirectories.contains(String(topLevel)) else {
            return nil
        }

        return "resident project execution is blocked for '(topLevel)' until an authorized project-byte bridge can materialize a safe workspace mirror; raw protected paths are refused to prevent macOS privacy prompts"
    }
}
