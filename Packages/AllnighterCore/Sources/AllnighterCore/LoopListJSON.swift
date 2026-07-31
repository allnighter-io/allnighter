import Foundation

/// `alln loop list` — the smallest honest listing of loops for a project
/// (LVC v7 `docs/phases/Loop_Verb_Cutover.md` §2/S02). Read-only, no quota:
/// projects `RelayState` straight off disk, never a second copy of run-truth.
public struct LoopListJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var projectId: String
    public var projectRoot: String
    public var loops: [Entry]

    public struct Entry: Codable, Sendable, Equatable {
        public var id: String
        /// `running`, `done`, `escalated`, `stopped`, or `awaitingPM` — the real
        /// `RelayState.Status` names ("parked" is prose, never a wire value).
        public var status: String
        /// The spec doc path when this loop has one, otherwise the founder's brief.
        public var briefOrSpec: String
        /// `caller` or a canonical agent id.
        public var pm: String
        public var dev: String
        public var updatedAt: Date

        public init(id: String, status: String, briefOrSpec: String, pm: String, dev: String, updatedAt: Date) {
            self.id = id
            self.status = status
            self.briefOrSpec = briefOrSpec
            self.pm = pm
            self.dev = dev
            self.updatedAt = updatedAt
        }
    }

    public init(schemaVersion: Int = 1, projectId: String, projectRoot: String, loops: [Entry]) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.loops = loops
    }
}
