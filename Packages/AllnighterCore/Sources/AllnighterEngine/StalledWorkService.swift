import Foundation
import AllnighterCore

/// Durable stall episode store (SWW-S00).
public struct StallEpisodeStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AllnighterPaths.stalled
        try? FileManager.default.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
    }

    public func loadAll() -> [StallEpisode] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> StallEpisode? in
                try? CoreJSON.decode(StallEpisode.self, from: Data(contentsOf: url))
            }
    }

    public func save(_ episode: StallEpisode) throws {
        let url = rootDirectory.appendingPathComponent("\(episode.id).json")
        try CoreJSON.encode(episode).write(to: url, options: .atomic)
    }

    public func delete(id: String) throws {
        let url = rootDirectory.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: url)
    }
}

/// Orchestrates scan, refresh-before-declare, and durable episode projection.
public struct StalledWorkService: Sendable {
    public var threadStore: ThreadStore
    public var runStore: RunStore
    public var pendingStore: PendingStore
    public var episodeStore: StallEpisodeStore
    public var now: @Sendable () -> Date

    public init(
        threadStore: ThreadStore = ThreadStore(),
        runStore: RunStore = RunStore(),
        pendingStore: PendingStore = PendingStore(),
        episodeStore: StallEpisodeStore = StallEpisodeStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.threadStore = threadStore
        self.runStore = runStore
        self.pendingStore = pendingStore
        self.episodeStore = episodeStore
        self.now = now
    }

    public func scanAndRefresh(thresholds: StalledWorkThresholds = StalledWorkThresholds()) throws -> [StallEpisode] {
        let threads = threadStore.list()
        let runs = runStore.list()
        let pending = (try? pendingStore.loadOrdered().items) ?? []
        let input = StalledWorkScanInput(threads: threads, runs: runs, pendingItems: pending, now: now())

        let candidates = StalledWorkDetector.scan(input: input, thresholds: thresholds)
        var confirmed: [StallEpisode] = []
        for var episode in candidates {
            let refreshedInput = StalledWorkScanInput(
                threads: threadStore.list(),
                runs: runStore.list(),
                pendingItems: (try? pendingStore.loadOrdered().items) ?? [],
                now: now()
            )
            let thread = refreshedInput.threads.first { $0.id == episode.threadId }
            let turn = episode.targetKind == .workerTurn
                ? thread.flatMap { StalledWorkDetector.refreshWorkerTurn(thread: $0, turnId: episode.targetId) }
                : nil
            let run = episode.targetKind == .teamRun
                ? StalledWorkDetector.refreshTeamRun(runStore: runStore, runId: episode.targetId)
                : nil
            guard StalledWorkDetector.isStillStalledAfterRefresh(
                thread: thread, turn: turn, run: run, input: refreshedInput, thresholds: thresholds
            ) else { continue }
            episode.lastRefreshAt = now()
            try episodeStore.save(episode)
            confirmed.append(episode)
        }
        _ = candidates
        return confirmed
    }

    public func activeEpisodes(projectId: String? = nil, includeCleared: Bool = false) -> [StallEpisode] {
        episodeStore.loadAll().filter { episode in
            if !includeCleared && episode.status == .cleared { return false }
            if let projectId { return episode.projectId == projectId }
            return episode.status != .cleared
        }
    }

    public func projectStalledJSON(projectId: String, includeCleared: Bool = false) -> StallEpisodeListJSON {
        StallEpisodeListJSON(
            contractVersion: ContractRegistry.contractVersion,
            projectId: projectId,
            episodes: activeEpisodes(projectId: projectId, includeCleared: includeCleared)
        )
    }

    public func aggregateStalledJSON() -> StallListJSON {
        let episodes = activeEpisodes()
        let grouped = Dictionary(grouping: episodes, by: \.projectId)
        let projectStore = ProjectStore()
        let projects = grouped.map { projectId, eps -> StallProjectGroup in
            let name = (try? projectStore.get(projectId))?.displayName
            return StallProjectGroup(projectId: projectId, projectName: name, episodes: eps)
        }.sorted { $0.projectId < $1.projectId }
        return StallListJSON(contractVersion: ContractRegistry.contractVersion, projects: projects)
    }
}
