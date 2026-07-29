import Foundation
import AllnighterCore

/// Persists the one durable PM delivery record for each run and relay subject.
/// The record lives beside the subject journal so the owning terminal transition
/// can write it before the subject's terminal or parked state.
public struct PMTurnStore: Sendable {
    public enum StoreError: Error, Equatable, Sendable {
        case unsafeSubjectId(String)
        case invalidSequence(Int)
        case nonMonotonicSequence(existing: Int, attempted: Int)
        case identityMismatch(
            expectedKind: PMTurnJSON.Kind,
            expectedSubjectId: String,
            actualKind: PMTurnJSON.Kind,
            actualSubjectId: String
        )
    }

    public let runsRootDirectory: URL
    public let relaysRootDirectory: URL

    public init(runsRootDirectory: URL? = nil, relaysRootDirectory: URL? = nil) {
        self.runsRootDirectory = runsRootDirectory ?? AllnighterPaths.runs
        self.relaysRootDirectory = relaysRootDirectory ?? AllnighterPaths.relays
    }

    /// The PM turn's durable location. This read-only helper does not create a
    /// subject directory, so callers can safely use it for status projection.
    public func fileURL(for kind: PMTurnJSON.Kind, subjectId: String) throws -> URL {
        try Self.validateSubjectId(subjectId)
        let directory: URL
        switch kind {
        case .run:
            // Match RunStore's established `run_<id>` directory convention.
            directory = runsRootDirectory.appendingPathComponent("run_\(subjectId)", isDirectory: true)
        case .relay:
            directory = relaysRootDirectory.appendingPathComponent(subjectId, isDirectory: true)
        }
        return directory.appendingPathComponent("pm-turn.json")
    }

    /// Atomically stores a new PM turn. A sequence may only advance for a
    /// subject; identical writes are idempotent for a retry of the same boundary.
    @discardableResult
    public func save(_ turn: PMTurnJSON) throws -> URL {
        guard turn.sequence > 0 else { throw StoreError.invalidSequence(turn.sequence) }
        let url = try fileURL(for: turn.kind, subjectId: turn.subjectId)

        if let existing = try load(kind: turn.kind, subjectId: turn.subjectId) {
            if existing == turn {
                return url
            }
            guard turn.sequence > existing.sequence else {
                throw StoreError.nonMonotonicSequence(existing: existing.sequence, attempted: turn.sequence)
            }
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try CoreJSON.encode(turn).write(to: url, options: .atomic)
        return url
    }

    /// Loads the subject's PM turn. A missing file is the expected crash-window
    /// state and returns `nil`; malformed or mismatched data fails loudly.
    public func load(kind: PMTurnJSON.Kind, subjectId: String) throws -> PMTurnJSON? {
        let url = try fileURL(for: kind, subjectId: subjectId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let turn = try CoreJSON.decode(PMTurnJSON.self, from: Data(contentsOf: url))
        guard turn.kind == kind, turn.subjectId == subjectId else {
            throw StoreError.identityMismatch(
                expectedKind: kind,
                expectedSubjectId: subjectId,
                actualKind: turn.kind,
                actualSubjectId: turn.subjectId
            )
        }
        return turn
    }

    /// Returns the next monotonically increasing delivery sequence for one subject.
    public func nextSequence(for kind: PMTurnJSON.Kind, subjectId: String) throws -> Int {
        (try load(kind: kind, subjectId: subjectId)?.sequence ?? 0) + 1
    }

    private static func validateSubjectId(_ subjectId: String) throws {
        let trimmed = subjectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              trimmed != ".", trimmed != "..",
              !trimmed.contains("..") else {
            throw StoreError.unsafeSubjectId(subjectId)
        }
    }
}
