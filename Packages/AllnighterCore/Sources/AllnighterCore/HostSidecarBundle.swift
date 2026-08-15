import Foundation
import AgentOSCLI

/// Locate an SPM resource sidecar next to a running host.
///
/// The CLI copies a **flat** layout (`Foo.bundle/catalog.json`). Xcode wraps
/// the same sidecar as a real bundle (`Foo.bundle/Contents/Resources/catalog.json`).
/// `ExecutableResource.data` only reads the flat layout, so a Mac `.app` finds
/// the wrapper directory and then misses the file — `ModelCatalog` used to
/// `Foundation.exit(1)` with no GUI-proof last-error.
public enum HostSidecarBundle {
    /// First existing resource URL under the given search roots.
    public static func resourceURL(
        bundleName: String,
        resourceFile: String,
        subdirectory: String? = nil,
        searchRoots: [URL],
        fileManager: FileManager = .default
    ) -> URL? {
        for root in searchRoots {
            let bundleRoot = root.appendingPathComponent(bundleName)
            let bases = [
                bundleRoot,
                bundleRoot.appendingPathComponent("Contents/Resources"),
            ]
            for base in bases {
                var candidates: [URL] = []
                if let subdirectory, !subdirectory.isEmpty {
                    candidates.append(
                        base.appendingPathComponent(subdirectory)
                            .appendingPathComponent(resourceFile)
                    )
                }
                candidates.append(base.appendingPathComponent(resourceFile))
                for url in candidates where fileManager.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }

    public static func data(
        bundleName: String,
        resourceFile: String,
        subdirectory: String? = nil,
        searchRoots: [URL] = defaultSearchRoots(),
        fileManager: FileManager = .default
    ) -> Data? {
        guard let url = resourceURL(
            bundleName: bundleName,
            resourceFile: resourceFile,
            subdirectory: subdirectory,
            searchRoots: searchRoots,
            fileManager: fileManager
        ) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// `Bundle.main` Resources plus the `.app/Contents/Resources` hop from the
    /// running executable. Never walks into Documents / Desktop / Downloads.
    public static func defaultSearchRoots(
        mainResourceURL: URL? = Bundle.main.resourceURL,
        mainBundleURL: URL = Bundle.main.bundleURL,
        executableURL: URL? = ExecutableResource.currentExecutableURL()
    ) -> [URL] {
        var roots: [URL] = []
        var seen: Set<String> = []
        func add(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard !path.isEmpty, seen.insert(path).inserted else { return }
            roots.append(URL(fileURLWithPath: path))
        }
        if let mainResourceURL { add(mainResourceURL) }
        add(
            mainBundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
        )
        if let executableURL {
            let macos = executableURL.deletingLastPathComponent()
            add(macos)
            add(macos.appendingPathComponent("Resources", isDirectory: true))
            add(
                macos.deletingLastPathComponent()
                    .appendingPathComponent("Resources", isDirectory: true)
            )
        }
        return roots
    }
}
