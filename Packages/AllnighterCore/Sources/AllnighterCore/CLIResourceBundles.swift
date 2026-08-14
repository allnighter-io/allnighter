import Foundation

/// SPM resource bundles that must sit next to a relocated `alln` binary.
///
/// Production loaders read files from these sidecar directories via
/// `ExecutableResource` (`_NSGetExecutablePath` + symlink resolve — never
/// argv[0]). Keep shipping the sidecars next to the canonical binary; do not
/// resurrect the SwiftPM resource-bundle accessor.
public enum CLIResourceBundles {
    public static let requiredNames: [String] = [
        "AgentOS_AgentOSCLI.bundle",
        "AllnighterCore_AllnighterCore.bundle",
    ]

    public static func siblingBundles(
        nextTo binary: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        let dir = binary.deletingLastPathComponent()
        guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else {
            return []
        }
        return names
            .filter { $0.hasSuffix(".bundle") }
            .sorted()
            .compactMap { name -> URL? in
                let url = dir.appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    return nil
                }
                return url
            }
    }

    public static func copySiblings(
        from candidateBinary: URL,
        into destinationDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        for source in siblingBundles(nextTo: candidateBinary, fileManager: fileManager) {
            let dest = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.copyItem(at: source, to: dest)
        }
    }

    /// PATH `alln` is a symlink. Catalog load follows the canonical inode, but
    /// keep these links so a mistaken symlink-directory lookup still finds
    /// the sidecars.
    public static func linkSiblings(
        from canonicalDirectory: URL,
        into pathDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        let probe = canonicalDirectory.appendingPathComponent("alln")
        for source in siblingBundles(nextTo: probe, fileManager: fileManager) {
            let dest = pathDirectory.appendingPathComponent(source.lastPathComponent)
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.createSymbolicLink(atPath: dest.path, withDestinationPath: source.path)
        }
    }
}
