import Foundation
import AllnighterCore

/// Index of Project ids in display order (newest add last).
public struct ProjectStoreIndex: Codable, Sendable, Equatable {
    public var projectOrder: [String]
    public init(projectOrder: [String] = []) { self.projectOrder = projectOrder }
}

/// Local persistence for Projects (PRJ-S01), beside thread/run/pending history.
///
/// Atomic per-Project JSON files plus an order index. Duplicate detection is by
/// `Project.normalizedRootPath` (the RootNormalization key): adding a path that
/// matches an existing **active** Project returns that Project rather than
/// creating a second one. Root availability and git metadata are observed
/// (never invented) at add/refresh time.
public final class ProjectStore: @unchecked Sendable {
    public let rootDirectory: URL
    private let fileManager: FileManager
    private let git: GitObserver

    public init(rootDirectory: URL = AllnighterPaths.projects,
                fileManager: FileManager = .default,
                git: GitObserver = GitObserver()) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.git = git
    }

    public var indexURL: URL { rootDirectory.appendingPathComponent("index.json") }
    public func projectURL(for id: String) -> URL { rootDirectory.appendingPathComponent("\(id).json") }

    public func ensureRoot() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    public func isWritable() -> Bool {
        (try? ensureRoot()) != nil && fileManager.isWritableFile(atPath: rootDirectory.path)
    }

    // MARK: - Raw persistence

    public func loadIndex() throws -> ProjectStoreIndex {
        try ensureRoot()
        guard fileManager.fileExists(atPath: indexURL.path) else { return ProjectStoreIndex() }
        return try CoreJSON.decode(ProjectStoreIndex.self, from: Data(contentsOf: indexURL))
    }

    public func saveIndex(_ index: ProjectStoreIndex) throws {
        try ensureRoot()
        try CoreJSON.encode(index).write(to: indexURL, options: .atomic)
    }

    public func load(id: String) throws -> Project? {
        let url = projectURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try CoreJSON.decode(Project.self, from: Data(contentsOf: url))
    }

    public func save(_ project: Project) throws {
        try ensureRoot()
        try CoreJSON.encode(project).write(to: projectURL(for: project.id), options: .atomic)
        var index = try loadIndex()
        if !index.projectOrder.contains(project.id) {
            index.projectOrder.append(project.id)
            try saveIndex(index)
        }
    }

    // MARK: - Listing

    /// All Projects in index order (active and archived). Use `.archived` to filter.
    ///
    /// A record that is present on disk but cannot be read is an error, not an
    /// absence. Swallowing it with `try?` is what let a restricted host be told
    /// "you have no projects" when the truth was "I could not read them" — the
    /// misreport that seeded the Code Red incident. Unreadable records now throw.
    public func list() throws -> [Project] {
        var index = try loadIndex()
        let onDisk = try listProjectIdsOnDisk()
        for id in onDisk where !index.projectOrder.contains(id) { index.projectOrder.append(id) }
        index.projectOrder.removeAll { !onDisk.contains($0) }
        return try index.projectOrder.compactMap { try load(id: $0) }
    }

    public func activeProjects() throws -> [Project] {
        try list().filter { !$0.archived }
    }

    /// Resolve by exact id first, then by an unambiguous active display name.
    public func get(_ idOrName: String) throws -> Project? {
        if let byId = try load(id: idOrName) { return byId }
        let matches = try list().filter { $0.displayName == idOrName }
        return matches.count == 1 ? matches.first : nil
    }

    /// Resolve a project token and re-observe git metadata — pilot paths must never
    /// serve stale branch/head/dirty from the cache (`Pilot_DX.md` §DX5).
    public func resolveFresh(_ idOrPath: String) -> Project? {
        let project: Project?
        if let byId = try? get(idOrPath) { project = byId }
        else {
            let key = RootNormalization.normalize(idOrPath).key
            project = try? activeProjects().first { $0.normalizedRootPath == key }
        }
        guard let project else { return nil }
        return (try? refreshObservation(id: project.id)) ?? project
    }

    // MARK: - Commands

    /// Add (or return the existing) Project for a local path. Duplicate detection
    /// is by normalized root key against active Projects.
    @discardableResult
    public func add(path: String, name: String? = nil, now: Date = Date()) throws -> Project {
        let normalized = RootNormalization.normalize(path)
        if let existing = try activeProjects().first(where: { $0.normalizedRootPath == normalized.key }) {
            return existing   // same normalized root → never a duplicate active Project
        }
        let observation = git.observe(rootPath: normalized.key)
        let rootState = RootNormalization.observeRootState(key: normalized.key)
        let displayName = name ?? URL(fileURLWithPath: normalized.displayPath).lastPathComponent
        let project = Project(
            id: "prj_" + UUID().uuidString.prefix(8).lowercased(),
            displayName: displayName.isEmpty ? "Project" : displayName,
            localRootPath: normalized.displayPath,
            normalizedRootPath: normalized.key,
            kind: observation.kind,
            rootState: rootState,
            gitRemoteURL: observation.remote,
            gitBranch: observation.branch,
            gitHead: observation.head,
            gitDirtySummary: observation.dirtySummary,
            createdAt: now,
            lastOpenedAt: now
        )
        try save(project)
        return project
    }

    /// Re-observe root availability + git metadata for `show`/open. Never invents.
    @discardableResult
    public func refreshObservation(id: String, now: Date = Date()) throws -> Project? {
        guard var project = try load(id: id) else { return nil }
        project.rootState = RootNormalization.observeRootState(key: project.normalizedRootPath)
        let observation = git.observe(rootPath: project.normalizedRootPath)
        project.kind = observation.kind
        project.gitBranch = observation.branch
        project.gitHead = observation.head
        project.gitRemoteURL = observation.remote
        project.gitDirtySummary = observation.dirtySummary
        project.lastOpenedAt = now
        try save(project)
        return project
    }

    /// Archive hides a Project from the active rail; it deletes no local files or
    /// records. Returns the archived Project, or nil if not found.
    @discardableResult
    public func archive(id: String) throws -> Project? {
        guard var project = try load(id: id) else { return nil }
        project.archived = true
        try save(project)
        return project
    }

    @discardableResult
    public func unarchive(id: String) throws -> Project? {
        guard var project = try load(id: id) else { return nil }
        project.archived = false
        try save(project)
        return project
    }

    private func listProjectIdsOnDisk() throws -> [String] {
        try ensureRoot()
        let urls = try fileManager.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil)
        return urls
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }
}
