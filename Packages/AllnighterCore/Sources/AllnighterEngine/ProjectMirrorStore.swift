import Foundation
import AllnighterCore

/// Owns already-materialized project mirrors. This store never receives a raw
/// project root: a host with project authority supplies a bounded directory,
/// and the resident later receives only `mirrorDirectory(id:)`.
public final class ProjectMirrorStore: @unchecked Sendable {
    public let rootDirectory: URL
    private let fileManager: FileManager

    public init(
        rootDirectory: URL = AllnighterPaths.support.appendingPathComponent("ProjectMirrors", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public enum Error: Swift.Error, Equatable {
        case invalidIdentifier
        case missingMirror
        case malformedManifest
    }

    public func mirrorDirectory(id: String) throws -> URL {
        guard Self.isSafeIdentifier(id) else { throw Error.invalidIdentifier }
        return rootDirectory.appendingPathComponent(id, isDirectory: true)
    }

    public func manifestURL(id: String) throws -> URL {
        try mirrorDirectory(id: id).appendingPathComponent("mirror.json")
    }

    public func workspaceDirectory(id: String) throws -> URL {
        try mirrorDirectory(id: id).appendingPathComponent("workspace", isDirectory: true)
    }

    public func load(id: String) throws -> ProjectMirror {
        let url = try manifestURL(id: id)
        guard fileManager.fileExists(atPath: url.path) else { throw Error.missingMirror }
        guard let mirror = try? CoreJSON.decode(ProjectMirror.self, from: Data(contentsOf: url)),
              mirror.id == id,
              mirror.contentSHA256 == ProjectMirror.contentDigest(files: mirror.files),
              mirror.manifestSHA256 == ProjectMirror.manifestDigest(
                projectId: mirror.projectId, sourceCommit: mirror.sourceCommit,
                dirtyFingerprint: mirror.dirtyFingerprint, files: mirror.files
              ) else { throw Error.malformedManifest }
        return mirror
    }

    public func remove(id: String) {
        guard let directory = try? mirrorDirectory(id: id) else { return }
        try? fileManager.removeItem(at: directory)
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

/// Materializes host-supplied bytes under Allnighter-owned storage. It has no
/// API accepting a source checkout path; that boundary is what prevents a
/// resident from re-opening Documents after a client has supplied a mirror.
public struct ProjectMirrorMaterializer {
    public static let maximumEntries = 20_000
    public static let maximumBytes = 256 * 1024 * 1024

    public enum Error: Swift.Error, Equatable {
        case emptyPayload
        case duplicatePath(String)
        case unsafePath(String)
        case environmentFile(String)
        case tooManyEntries
        case tooLarge
        case writeFailed(String)
    }

    public let store: ProjectMirrorStore
    private let fileManager: FileManager

    public init(store: ProjectMirrorStore = ProjectMirrorStore(), fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    @discardableResult
    public func materialize(_ payload: ProjectMirrorPayload) throws -> ProjectMirror {
        guard !payload.entries.isEmpty else { throw Error.emptyPayload }
        guard payload.entries.count <= Self.maximumEntries else { throw Error.tooManyEntries }
        let destination = try store.mirrorDirectory(id: payload.id)
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(payload.id).staging-\(UUID().uuidString)", isDirectory: true)
        let workspace = staging.appendingPathComponent("workspace", isDirectory: true)
        var seen: Set<String> = []
        var byteTotal = 0
        var files: [ProjectMirror.File] = []
        do {
            try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
            for entry in payload.entries.sorted(by: { $0.path < $1.path }) {
                guard seen.insert(entry.path).inserted else { throw Error.duplicatePath(entry.path) }
                guard Self.isSafeRelativePath(entry.path) else { throw Error.unsafePath(entry.path) }
                guard !Self.containsEnvironmentFile(entry.path) else { throw Error.environmentFile(entry.path) }
                byteTotal += entry.data.count
                guard byteTotal <= Self.maximumBytes else { throw Error.tooLarge }
                let url = workspace.appendingPathComponent(entry.path)
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try entry.data.write(to: url, options: .atomic)
                files.append(.init(path: entry.path, byteCount: entry.data.count, sha256: ProjectMirror.digest(entry.data)))
            }
            let sortedFiles = files.sorted { $0.path < $1.path }
            let contentHash = ProjectMirror.contentDigest(files: sortedFiles)
            let manifestHash = ProjectMirror.manifestDigest(
                projectId: payload.projectId, sourceCommit: payload.sourceCommit,
                dirtyFingerprint: payload.dirtyFingerprint, files: sortedFiles
            )
            let mirror = ProjectMirror(
                id: payload.id, projectId: payload.projectId, sourceCommit: payload.sourceCommit,
                dirtyFingerprint: payload.dirtyFingerprint, files: sortedFiles,
                manifestSHA256: manifestHash, contentSHA256: contentHash, createdAt: payload.createdAt
            )
            try CoreJSON.encode(mirror).write(to: staging.appendingPathComponent("mirror.json"), options: .atomic)
            try? fileManager.removeItem(at: destination)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: staging, to: destination)
            return mirror
        } catch let error as Error {
            try? fileManager.removeItem(at: staging)
            throw error
        } catch {
            try? fileManager.removeItem(at: staging)
            throw Error.writeFailed(error.localizedDescription)
        }
    }

    /// Re-hashes a stored mirror before handing it to a worker. A stale or
    /// tampered mirror fails closed instead of being treated as project truth.
    public func verify(id: String) throws -> ProjectMirror {
        let mirror = try store.load(id: id)
        let workspace = try store.workspaceDirectory(id: id)
        var observed: [ProjectMirror.File] = []
        for expected in mirror.files {
            guard Self.isSafeRelativePath(expected.path),
                  let data = try? Data(contentsOf: workspace.appendingPathComponent(expected.path)) else {
                throw Error.writeFailed("mirror file missing: \(expected.path)")
            }
            let actual = ProjectMirror.File(path: expected.path, byteCount: data.count, sha256: ProjectMirror.digest(data))
            guard actual == expected else { throw Error.writeFailed("mirror file changed: \(expected.path)") }
            observed.append(actual)
        }
        guard ProjectMirror.contentDigest(files: observed) == mirror.contentSHA256 else {
            throw Error.writeFailed("mirror content digest changed")
        }
        return mirror
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    private static func containsEnvironmentFile(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0.hasPrefix(".env") }
    }
}
