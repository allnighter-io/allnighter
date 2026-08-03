import AppKit
import Foundation
import AllnighterCore
import AllnighterEngine
import AgentOSTeam

@MainActor
extension ThreadsViewModel {
    // MARK: - Timeline visibility / read clear (06 S05)

    /// Timeline reports geometrically visible turn ids; debounced read-clear goes through
    /// `ThreadStore.markReadToLatestVisible` — never GUI-only unread truth.
    func reportTimelineVisibility(threadId: String, visibleTurnIds: [String]) {
        latestVisibleTurnIds[threadId] = Set(visibleTurnIds)
        guard threadId == selectedThreadId else { return }
        readClearDebounceTask?.cancel()
        readClearDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.readClearDebounceNs)
            guard !Task.isCancelled else { return }
            applyReadClearIfNeeded(threadId: threadId, visibleTurnIds: visibleTurnIds)
        }
    }

    func applyReadClearIfNeeded(threadId: String, visibleTurnIds: [String]) {
        guard isAppActiveForReadClear() else { return }
        let before = store.get(threadId)
        guard let updated = try? store.markReadToLatestVisible(
            threadId: threadId, visibleTurnIds: visibleTurnIds, now: Date()
        ) else { return }
        if before?.readCursor != updated.readCursor || before?.hasUnread != updated.hasUnread {
            refreshPublishedThread(threadId)
            reload()
        }
    }

    // MARK: - Rail controls (07)

    func renameThread(_ threadId: String, title: String) {
        guard (try? store.renameThread(threadId: threadId, title: title)) != nil else { return }
        refreshPublishedThread(threadId)
        reload()
    }

    func setPinned(_ threadId: String, pinned: Bool) {
        guard (try? store.setPinned(threadId: threadId, pinned: pinned, now: Date())) != nil else { return }
        refreshPublishedThread(threadId)
        reload()
    }

    func archiveThread(_ threadId: String) {
        guard (try? store.archiveThread(threadId: threadId)) != nil else { return }
        refreshPublishedThread(threadId)
        if selectedThreadId == threadId, showingArchive == false {
            selectedThreadId = ThreadsPresenter.triagedActive(threads).first?.id
        }
        reload()
    }

    func unarchiveThread(_ threadId: String) {
        guard (try? store.unarchiveThread(threadId: threadId)) != nil else { return }
        refreshPublishedThread(threadId)
        reload()
    }

    func togglePin(for thread: WorkThread) {
        guard !thread.isArchived else { return }
        setPinned(thread.id, pinned: !thread.isPinned)
    }

    /// Rail-row (id-based) convenience so the sidebar can act from a `ThreadRailRowState`
    /// without holding a full `WorkThread` (PERF-S02 — keeps the rail off the live array).
    func select(threadId: String) {
        guard let thread = threads.first(where: { $0.id == threadId }) else { return }
        select(thread)
    }

    func togglePin(threadId: String) {
        guard let thread = threads.first(where: { $0.id == threadId }) else { return }
        togglePin(for: thread)
    }

    @discardableResult
    func newThread(title: String = "New thread", workingDir: String? = nil) -> WorkThread? {
        guard let scope = projectScope(fallbackWorkingDir: workingDir) else {
            #if DEBUG
            if GUIFixture.isActive {
                return fixtureThread(title: title, workingDir: workingDir)
            }
            #endif
            return nil
        }
        let thread = try? store.create(
            id: UUID().uuidString, title: title, now: Date(), workingDir: scope.root
        )
        if let thread {
            bindThread(thread.id, to: scope, snapshot: workingDir)
            refreshPublishedThread(thread.id)
            selectedThreadId = thread.id
        }
        reload()
        return thread
    }

    struct ProjectScope {
        var projectId: String
        var root: String
    }

    func bindThread(_ threadId: String, to scope: ProjectScope, snapshot: String? = nil) {
        _ = try? store.bindProject(
            threadId: threadId,
            projectId: scope.projectId,
            localRootPathSnapshot: snapshot
        )
    }

    func projectScope(preferredProjectId: String? = nil, fallbackWorkingDir: String? = nil) -> ProjectScope? {
        if let preferredProjectId, let scope = scope(forProjectId: preferredProjectId) {
            return scope
        }

        if let rawPath = fallbackWorkingDir?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawPath.isEmpty,
           let projects = try? projectStore.activeProjects() {
            switch ProjectBinding.resolve(rawPath: rawPath, projects: projects) {
            case .existing(let projectId):
                if let scope = scope(forProjectId: projectId) { return scope }
            case .repoRoot(let path):
                guard let project = try? projectStore.add(path: path), project.rootState == .available else {
                    return nil
                }
                currentProjectId = project.id
                return ProjectScope(projectId: project.id, root: project.normalizedRootPath)
            case .unassigned:
                break
            }
        }

        if let projectId = currentProjectId {
            if let scope = scope(forProjectId: projectId) { return scope }
        }
        return nil
    }

    func scope(forProjectId projectId: String) -> ProjectScope? {
        guard let project = try? projectStore.load(id: projectId),
              project.rootState == .available else {
            return nil
        }
        let root = project.normalizedRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { return nil }
        return ProjectScope(projectId: project.id, root: root)
    }

    #if DEBUG
    func fixtureThread(title: String, workingDir: String?) -> WorkThread? {
        let thread = try? store.create(
            id: UUID().uuidString, title: title, now: Date(), workingDir: workingDir
        )
        if let thread {
            refreshPublishedThread(thread.id)
            selectedThreadId = thread.id
        }
        reload()
        return thread
    }
    #endif

    /// Empty thread for the "Start a run" flow.
    func newRun() {
        _ = newThread(title: Self.newChatTitle)
    }
}
