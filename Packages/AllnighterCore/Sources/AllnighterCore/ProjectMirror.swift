import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Provenance for a bounded read-only project mirror. The mirror is the only
/// project directory a resident answer worker may receive once CPH-3 is wired:
/// the original checkout path is a receipt for the host, never worker input.
public struct ProjectMirror: Codable, Equatable, Sendable {
    public struct File: Codable, Equatable, Sendable {
        public var path: String
        public var byteCount: Int
        public var sha256: String

        public init(path: String, byteCount: Int, sha256: String) {
            self.path = path
            self.byteCount = byteCount
            self.sha256 = sha256
        }
    }

    public var schemaVersion: Int
    public var id: String
    public var projectId: String?
    /// Host-observed Git commit. It is provenance, not a filesystem reference.
    public var sourceCommit: String?
    /// SHA-256 of the host-observed tracked dirty state.
    public var dirtyFingerprint: String
    public var files: [File]
    public var manifestSHA256: String
    public var contentSHA256: String
    public var createdAt: Date

    public init(
        schemaVersion: Int = 1,
        id: String,
        projectId: String? = nil,
        sourceCommit: String? = nil,
        dirtyFingerprint: String,
        files: [File],
        manifestSHA256: String,
        contentSHA256: String,
        createdAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.projectId = projectId
        self.sourceCommit = sourceCommit
        self.dirtyFingerprint = dirtyFingerprint
        self.files = files
        self.manifestSHA256 = manifestSHA256
        self.contentSHA256 = contentSHA256
        self.createdAt = createdAt
    }

    /// Deterministic digest over a length-prefixed sequence; prevents ambiguity
    /// between names and content when a mirror is transferred between hosts.
    public static func contentDigest(files: [File]) -> String {
        let canonical = files.sorted { $0.path < $1.path }.map {
            "\($0.path.utf8.count):\($0.path)|\($0.byteCount)|\($0.sha256)"
        }.joined(separator: "\n")
        return digest(Data(canonical.utf8))
    }

    public static func manifestDigest(
        projectId: String?, sourceCommit: String?, dirtyFingerprint: String, files: [File]
    ) -> String {
        let canonical = [projectId ?? "", sourceCommit ?? "", dirtyFingerprint, contentDigest(files: files)]
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        return digest(Data(canonical.utf8))
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Typed project bytes supplied by a host that already has authority to read a
/// checkout. This deliberately contains no source path: a resident must never
/// fall back to opening the host's Documents directory.
public struct ProjectMirrorPayload: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public var path: String
        public var data: Data

        public init(path: String, data: Data) {
            self.path = path
            self.data = data
        }
    }

    public var id: String
    public var projectId: String?
    public var sourceCommit: String?
    public var dirtyFingerprint: String
    public var entries: [Entry]
    public var createdAt: Date

    public init(
        id: String,
        projectId: String? = nil,
        sourceCommit: String? = nil,
        dirtyFingerprint: String,
        entries: [Entry],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.sourceCommit = sourceCommit
        self.dirtyFingerprint = dirtyFingerprint
        self.entries = entries
        self.createdAt = createdAt
    }
}
