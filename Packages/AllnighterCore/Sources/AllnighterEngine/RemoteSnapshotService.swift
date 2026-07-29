import Foundation
import AllnighterCore

public struct RemoteSnapshotPolicy: Equatable, Sendable {
    public var maxRuns: Int
    public var promptExcerptLimit: Int
    public var replayEventLimit: Int

    public init(
        maxRuns: Int = 50,
        promptExcerptLimit: Int = 160,
        replayEventLimit: Int = 500
    ) {
        self.maxRuns = max(0, maxRuns)
        self.promptExcerptLimit = max(1, promptExcerptLimit)
        self.replayEventLimit = max(0, replayEventLimit)
    }
}

public enum RemoteResumeResult: Equatable, Sendable {
    case snapshot(SnapshotEnvelope)
    case events([RunEvent], lastSeq: Int64)
    case resyncRequired(ResyncRequired)
}

public struct RemoteSnapshotService: Sendable {
    public let runStore: RunStore
    public let journal: RemoteRunEventJournal
    public let policy: RemoteSnapshotPolicy
    private let now: @Sendable () -> Date

    public init(
        runStore: RunStore = RunStore(),
        journal: RemoteRunEventJournal = RemoteRunEventJournal(),
        policy: RemoteSnapshotPolicy = RemoteSnapshotPolicy(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.runStore = runStore
        self.journal = journal
        self.policy = policy
        self.now = now
    }

    public func snapshot(since _: Int64? = nil) throws -> SnapshotEnvelope {
        let runs = runStore.list()
            .prefix(policy.maxRuns)
            .map { lightRun(from: $0) }
        return SnapshotEnvelope(
            runs: Array(runs),
            lastSeq: try journal.lastSeq(),
            serverTime: now()
        )
    }

    public func resume(since seq: Int64?) throws -> RemoteResumeResult {
        guard let seq, seq > 0 else {
            return .snapshot(try snapshot(since: seq))
        }

        guard seq <= (try journal.lastSeq()) else {
            return .resyncRequired(ResyncRequired(
                reason: "cursorAheadOfJournal",
                snapshotHint: "Fetch a snapshot, then resume from its lastSeq."
            ))
        }
        let replay = try journal.replay(after: seq, limit: replayProbeLimit)
        guard replay.events.count <= policy.replayEventLimit else {
            return .resyncRequired(ResyncRequired(
                reason: "eventWindowExceeded",
                snapshotHint: "Fetch a snapshot, then resume from its lastSeq."
            ))
        }
        return .events(replay.events.map { RemoteRunEventPrivacy.contentLight($0) }, lastSeq: replay.lastSeq)
    }

    private var replayProbeLimit: Int? {
        guard policy.replayEventLimit < Int.max else { return nil }
        return policy.replayEventLimit + 1
    }

    private func lightRun(from run: TeamRun) -> TeamRunLight {
        let mapped = TeamRunJSONMapper.map(
            run,
            models: [],
            manifests: [],
            context: TeamRunJSONMapper.Context(
                runJournalPath: journal.eventsURL(forRunId: run.id).path
            )
        )
        return TeamRunLight(
            id: run.id,
            status: mapped.teamRun.status,
            origin: mapped.teamRun.origin,
            promptExcerpt: "",
            teamDisplayName: mapped.teamRun.teamDisplayName,
            createdAt: run.createdAt,
            completedAt: completedAt(for: run)
        )
    }

    private func completedAt(for run: TeamRun) -> Date? {
        guard run.status.isTerminal else { return nil }
        return run.answers.compactMap(\.result.timing.finishedAt).max()
            ?? run.stages.compactMap(\.finishedAt).max()
            ?? run.createdAt
    }
}
