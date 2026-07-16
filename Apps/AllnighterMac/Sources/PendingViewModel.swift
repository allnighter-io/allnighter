import SwiftUI
import AllnighterCore
import AllnighterEngine

/// Drives the Pending screen + the top-bar pending pill. Pure projection of the Core
/// contract: reads `PendingService.queueJSON()` (the same `PendingQueueJSON` the CLI
/// emit) and routes every mutation back through `PendingService`. No GUI-local truth.
@Observable
@MainActor
final class PendingViewModel {
    private(set) var queue: PendingQueueJSON
    private let service: PendingService

    init(service: PendingService) {
        self.service = service
        self.queue = PendingViewModel.load(service)
    }

    /// Production: read/write the real Pending store.
    convenience init(models: [Model]) {
        self.init(service: PendingService(store: PendingStore(), models: models))
    }

    private static func load(_ service: PendingService) -> PendingQueueJSON {
        (try? service.queueJSON())
            ?? PendingQueueJSON(contractVersion: ContractRegistry.contractVersion, totalPending: 0, projects: [])
    }

    func refresh() { queue = PendingViewModel.load(service) }

    /// Full prompt for the review modal (the queue projection only carries an excerpt).
    func prompt(for id: String) -> String {
        (try? service.list().first { $0.id == id })?.prompt ?? ""
    }

    /// Armed count — drives the top-bar pill (shown only when > 0).
    var totalPending: Int { queue.totalPending }

    /// Remove from queue (Draft or Pending → cancelled).
    func remove(_ id: String) {
        _ = try? service.cancel(id: id)
        refresh()
    }

    /// Un-arm on edit (Pending → Draft). `edit` always drafts a pending item, so an
    /// empty edit is enough to flip the state the moment the user starts editing.
    func unarm(_ id: String) {
        _ = try? service.edit(id: id, .init())
        refresh()
    }

    /// Re-submit from the review modal: write the edited prompt/target, then re-arm
    /// (Draft → Pending). Mirrors the CLI edit→submit pair exactly.
    func rearm(_ id: String, prompt: String, team: String?, worker: String?) {
        _ = try? service.edit(id: id, .init(
            prompt: prompt,
            workerToken: worker,
            teamPresetId: team
        ))
        _ = try? service.submit(id: id)
        refresh()
    }
}
