import AppKit
import Foundation
import Observation
import AllnighterCore
import AllnighterEngine

/// The Projects surface's observable truth (PRJ-S14). Owns a `ProjectStore` and
/// the "active project" selection that scopes new work. Mirrors `ThreadsViewModel`'s
/// pattern (@Observable + @MainActor). UI reads this; project truth lives in the
/// store — every change goes through it.
@MainActor
@Observable
final class ProjectsViewModel {
    private(set) var projects: [Project] = []
    /// The project new work is scoped to. Mutating sends run against its root.
    var activeProjectId: String?

    private let store: ProjectStore

    init(store: ProjectStore = ProjectStore()) {
        self.store = store
        reload()
    }

    func reload() {
        projects = (try? store.activeProjects()) ?? []
        if activeProjectId == nil || !projects.contains(where: { $0.id == activeProjectId }) {
            activeProjectId = projects.first?.id
        }
    }

    var activeProject: Project? { projects.first { $0.id == activeProjectId } }

    func select(_ id: String) { activeProjectId = id }

    /// Add (or reuse) a project for a local root, then make it active.
    @discardableResult
    func addProject(path: String, name: String? = nil) -> Project? {
        guard let project = try? store.add(path: path, name: name) else { return nil }
        reload()
        activeProjectId = project.id
        return project
    }

    /// Open a folder picker and add the chosen root as a project (AppKit modal).
    func addProjectViaPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"
        panel.message = "Choose a local folder or git repository to manage."
        if panel.runModal() == .OK, let url = panel.url {
            _ = addProject(path: url.path)
        }
    }

    #if DEBUG
    /// Designer-mock seed for the GUI Visual Proof Gate (never real data).
    func seedForProof(_ sample: [Project], active: String?) {
        projects = sample
        activeProjectId = active ?? sample.first?.id
    }

    /// Sample projects for the projects-rail proof (ids match the seeded threads).
    static func sampleProjects() -> [Project] {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        func p(_ id: String, _ name: String, _ path: String) -> Project {
            Project(id: id, displayName: name, localRootPath: path, normalizedRootPath: path,
                    kind: .gitRepo, rootState: .available, gitBranch: "main",
                    createdAt: now, lastOpenedAt: now)
        }
        return [
            p("prj_halo", "halo-app", "~/dev/halo-app"),
            p("prj_web", "websitemd.studio", "~/dev/websitemd"),
            p("prj_fare", "FareWellMarket", "~/dev/farewell"),
        ]
    }
    #endif
}
