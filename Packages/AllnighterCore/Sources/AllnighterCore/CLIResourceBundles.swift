import Foundation

/// SPM resource bundles that must sit next to a relocated `alln` binary.
///
/// `Bundle.module` for AgentOSCLI / AllnighterCore looks beside the executable
/// (the PATH symlink's directory, not the canonical inode) and then at the
/// original build path. A published Mach-O without these sidecars crashes on
/// any machine except the builder's — that is how 1.1.5–1.1.8 `curl | sh`
/// died in production.
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

    /// PATH `alln` is a symlink; SPM looks beside argv0, so the same bundles
    /// must be visible in the symlink directory.
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
