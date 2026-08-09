import Foundation

/// SC-S04a — Stage a stable copy of the running `alln` binary under Application
/// Support so an OS-managed supervisor can target a product-owned identity that
/// does not change cdhash every `rebuild_cli.sh`.
///
/// Pure copy, never a symlink. Atomic: writes to a temp name then replaces the
/// final path so a reader never sees a partially-written file.
public enum ServeStableBinary {

    public static let binaryName = "alln"
    public static let defaultCLIDirName = "CLI"

    public struct StagingResult: Equatable, Sendable {
        public let url: URL
        public let bytesWereReplaced: Bool

        public init(url: URL, bytesWereReplaced: Bool) {
            self.url = url
            self.bytesWereReplaced = bytesWereReplaced
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        case sourceNotReadable(URL)
        case sourceDataEmpty(URL)
        case destinationDirectoryNotCreatable(URL)
        case tempWriteFailed(URL)
        case tempNotReplaced(URL)
        case executableBitNotSettable(URL)
    }

    /// Default destination directory: `~/Library/Application Support/Allnighter/CLI/`
    public static func defaultDestinationDirectory(fileManager: FileManager = .default) -> URL {
        AllnighterPaths.support.appendingPathComponent(defaultCLIDirName, isDirectory: true)
    }

    /// Default destination URL: `…/CLI/alln`
    public static func defaultDestinationURL(fileManager: FileManager = .default) -> URL {
        defaultDestinationDirectory(fileManager: fileManager).appendingPathComponent(binaryName)
    }

    /// Copy `sourceURL` atomically to `destinationURL` (or the default path).
    /// Returns the staged URL and whether the bytes actually changed.
    ///
    /// - Parameters:
    ///   - sourceURL: Path to the running executable to copy.
    ///   - destinationURL: Where to place the stable copy. Defaults to `…/CLI/alln`.
    ///   - fileManager: Injectable for tests.
    public static func stage(
        from sourceURL: URL,
        to destinationURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> Result<StagingResult, Failure> {
        guard fileManager.isReadableFile(atPath: sourceURL.path) else {
            return .failure(.sourceNotReadable(sourceURL))
        }
        guard let data = try? Data(contentsOf: sourceURL), !data.isEmpty else {
            return .failure(.sourceDataEmpty(sourceURL))
        }

        let destURL = destinationURL ?? defaultDestinationURL(fileManager: fileManager)
        let destDir = destURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.destinationDirectoryNotCreatable(destDir))
        }

        let bytesWereReplaced: Bool
        if let existing = try? Data(contentsOf: destURL) {
            bytesWereReplaced = existing != data
        } else {
            bytesWereReplaced = true
        }

        let tempURL = destDir.appendingPathComponent(".\(binaryName).staging.\(UUID().uuidString)")
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            return .failure(.tempWriteFailed(tempURL))
        }

        if fileManager.fileExists(atPath: destURL.path) {
            do {
                try fileManager.removeItem(at: destURL)
            } catch {
                try? fileManager.removeItem(at: tempURL)
                return .failure(.tempNotReplaced(destURL))
            }
        }
        do {
            try fileManager.moveItem(at: tempURL, to: destURL)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            return .failure(.tempNotReplaced(destURL))
        }

        let permissions: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        do {
            try fileManager.setAttributes(permissions, ofItemAtPath: destURL.path)
        } catch {
            return .failure(.executableBitNotSettable(destURL))
        }

        return .success(StagingResult(url: destURL, bytesWereReplaced: bytesWereReplaced))
    }
}
