import Foundation
import AllnighterCore

/// Generates a compact, source-labeled `ProjectContextPacket` from owned truth
/// (PRJ-S02). It re-observes git/root live (so a regenerated packet reflects the
/// current HEAD) and projects worker readiness into the compact summary. The
/// cross-store collections (threads, pending, runs, proposals, returns, proof
/// results) are passed in by the caller — thread/Pending binding land in
/// PRJ-S03/S04 and proposals/returns in PRJ-S09+, which wire their real stores
/// here. A packet is a receipt, never durable truth, and must never hide a failed
/// worker, missing root, dirty tree, or failed proof.
public enum ProjectContextPacketBuilder {

    public static func build(
        project: Project,
        workerReadiness: [ProjectWorkerReadiness] = [],
        recentThreadSummaries: [String] = [],
        unresolvedQuestions: [String] = [],
        activeRuns: [String] = [],
        pendingItems: [String] = [],
        openProposals: [String] = [],
        recentReturns: [String] = [],
        verificationFindings: [String] = [],
        recentlyChangedDocs: [String] = [],
        staleDocCandidates: [String] = [],
        lastProofResults: [String] = [],
        git: GitObserver = GitObserver(),
        now: Date = Date(),
        maxList: Int = 10
    ) -> ProjectContextPacket {
        // Re-observe so the packet reflects current truth, not the Project's last save.
        let rootState = RootNormalization.observeRootState(key: project.normalizedRootPath)
        let obs = git.observe(rootPath: project.normalizedRootPath)
        let recentCommits = git.recentCommits(rootPath: project.normalizedRootPath, limit: 5)

        let ready = workerReadiness.filter { $0.status == .ready }
        let blocked = workerReadiness.filter { $0.status != .ready }
        let readinessSummary = "\(ready.count) ready · \(blocked.count) blocked"
        let workers = ProjectContextPacket.Workers(
            readinessSummary: readinessSummary,
            readyWorkerIds: ready.map { $0.workerId ?? $0.sourceId },
            blockedWorkerSummaries: blocked.map { "\($0.sourceId): \($0.status.rawValue)" }
        )

        // Warnings surface (never hide) the failures the Manager must see.
        var warnings: [String] = []
        if rootState != .available { warnings.append("root \(rootState.rawValue): \(project.localRootPath)") }
        if let dirty = obs.dirtySummary { warnings.append("dirty tree: \(dirty)") }
        for summary in blocked { warnings.append("worker blocked — \(summary.sourceId): \(summary.status.rawValue)") }
        for result in lastProofResults where looksFailed(result) { warnings.append("proof: \(result)") }
        for stale in staleDocCandidates { warnings.append("stale doc: \(stale)") }

        return ProjectContextPacket(
            id: "pkt_" + UUID().uuidString.prefix(8).lowercased(),
            projectId: project.id,
            generatedAt: now,
            root: .init(localRootPath: project.localRootPath, kind: obs.kind, rootState: rootState),
            git: .init(branch: obs.branch, head: obs.head, remote: obs.remote,
                       dirtySummary: obs.dirtySummary, recentCommits: capped(recentCommits, maxList)),
            docs: .init(entrypoints: project.docsEntrypoints,
                        recentlyChanged: capped(recentlyChangedDocs, maxList),
                        staleCandidates: capped(staleDocCandidates, maxList)),
            threads: .init(managerThreadId: project.managerThreadId,
                           recentThreadSummaries: capped(recentThreadSummaries, maxList),
                           unresolvedQuestions: capped(unresolvedQuestions, maxList)),
            work: .init(activeRuns: capped(activeRuns, maxList),
                        pendingItems: capped(pendingItems, maxList),
                        openProposals: capped(openProposals, maxList),
                        recentReturns: capped(recentReturns, maxList),
                        verificationFindings: capped(verificationFindings, maxList)),
            workers: workers,
            proof: .init(commands: project.proofCommands, lastResults: capped(lastProofResults, maxList)),
            warnings: warnings
        )
    }

    private static func capped(_ items: [String], _ max: Int) -> [String] {
        items.count <= max ? items : Array(items.prefix(max))
    }

    /// A proof result line "looks failed" when it mentions a non-zero/failed/timeout
    /// marker. Heuristic only — verification (PRJ-S12) owns the authoritative outcome.
    private static func looksFailed(_ line: String) -> Bool {
        let l = line.lowercased()
        return l.contains("fail") || l.contains("timeout") || l.contains("timed out")
            || l.contains("error") || l.contains("exit 1") || l.contains("not verified")
    }
}
