import Foundation

/// Safe join of run-relative image paths under a run directory.
public enum RunImagePathResolver {
    public static func isImagePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")
            || lower.hasSuffix(".webp")
    }

    public static func absolutePath(runDirectory: URL, relativePath: String) -> String? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("/") else { return nil }
        if trimmed.contains("..") { return nil }

        let runRoot = runDirectory.standardizedFileURL
        let candidate = runRoot.appendingPathComponent(trimmed).standardizedFileURL
        let rootPath = runRoot.path.hasSuffix("/") ? runRoot.path : runRoot.path + "/"
        guard candidate.path.hasPrefix(rootPath) || candidate.path == runRoot.path else { return nil }
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate.path
    }
}
