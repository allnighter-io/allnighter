import Foundation
import AllnighterCore

/// PRJ-S09: durable per-project proposals. A proposal is NOT Project truth — it's a
/// derived bounded next move (Project/git/proof win on conflict) — but it is durable
/// so it can be approved/edited/postponed later (PRJ-S10). One JSON file per project.
public final class ProjectProposalStore: @unchecked Sendable {
    public let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL = AllnighterPaths.projectProposals, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    private func fileURL(projectId: String) -> URL {
        rootDirectory.appendingPathComponent("\(projectId).json")
    }

    private func ensureRoot() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    /// All proposals for a project, oldest first.
    public func load(projectId: String) -> [ProjectProposal] {
        let url = fileURL(projectId: projectId)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let proposals = try? CoreJSON.decode([ProjectProposal].self, from: data)
        else { return [] }
        return proposals
    }

    public func get(projectId: String, proposalId: String) -> ProjectProposal? {
        load(projectId: projectId).first { $0.id == proposalId }
    }

    /// Append a new proposal (run truth for the propose turn).
    @discardableResult
    public func append(_ proposal: ProjectProposal) throws -> ProjectProposal {
        try ensureRoot()
        var all = load(projectId: proposal.projectId)
        all.append(proposal)
        try CoreJSON.encode(all).write(to: fileURL(projectId: proposal.projectId), options: .atomic)
        return proposal
    }

    /// Replace an existing proposal in place (used by approve/edit/postpone, S10).
    @discardableResult
    public func update(_ proposal: ProjectProposal) throws -> ProjectProposal {
        try ensureRoot()
        var all = load(projectId: proposal.projectId)
        guard let idx = all.firstIndex(where: { $0.id == proposal.id }) else {
            all.append(proposal)
            try CoreJSON.encode(all).write(to: fileURL(projectId: proposal.projectId), options: .atomic)
            return proposal
        }
        all[idx] = proposal
        try CoreJSON.encode(all).write(to: fileURL(projectId: proposal.projectId), options: .atomic)
        return proposal
    }
}
