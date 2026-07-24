import Foundation
import AllnighterCore

/// Runs only in the calling host, before a resident request. It reads tracked
/// source bytes while that host already has project authority, then hands the
/// resident an owned mirror id. The resident never calls this type.
public struct ProjectMirrorCapture {
    public enum Error: Swift.Error, Equatable {
        case gitUnavailable(String)
        case unsafeTrackedPath(String)
        case unreadableTrackedFile(String)
    }

    public let materializer: ProjectMirrorMaterializer

    public init(materializer: ProjectMirrorMaterializer) {
        self.materializer = materializer
    }

    @discardableResult
    public func capture(projectRoot: String, projectId: String?) throws -> ProjectMirror {
        let paths = try gitNul(arguments: ["ls-files", "-z"], root: projectRoot)
        var entries: [ProjectMirrorPayload.Entry] = []
        for path in paths {
            guard Self.isSafeTrackedPath(path) else { throw Error.unsafeTrackedPath(path) }
            // Dotenv files never enter a mirror, even if mistakenly committed.
            guard !path.split(separator: "/").contains(where: { $0.hasPrefix(".env") }) else { continue }
            let url = URL(fileURLWithPath: projectRoot).appendingPathComponent(path)
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true,
                  let data = try? Data(contentsOf: url) else {
                throw Error.unreadableTrackedFile(path)
            }
            entries.append(.init(path: path, data: data))
        }
        let dirty = try gitRaw(arguments: ["status", "--porcelain=v1", "-z"], root: projectRoot)
        let commit = try? gitRaw(arguments: ["rev-parse", "HEAD"], root: projectRoot)
        return try materializer.materialize(.init(
            id: "mirror-\(UUID().uuidString.lowercased())",
            projectId: projectId,
            sourceCommit: commit?.trimmingCharacters(in: .whitespacesAndNewlines),
            dirtyFingerprint: ProjectMirror.digest(Data(dirty.utf8)),
            entries: entries
        ))
    }

    private func gitNul(arguments: [String], root: String) throws -> [String] {
        let data = try gitData(arguments: arguments, root: root)
        return data.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
    }

    private func gitRaw(arguments: [String], root: String) throws -> String {
        String(decoding: try gitData(arguments: arguments, root: root), as: UTF8.self)
    }

    private func gitData(arguments: [String], root: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = URL(fileURLWithPath: root)
        process.arguments = arguments
        let output = Pipe(); let errors = Pipe()
        process.standardOutput = output; process.standardError = errors; process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw Error.gitUnavailable(error.localizedDescription) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Error.gitUnavailable(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    private static func isSafeTrackedPath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && path.split(separator: "/").allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
