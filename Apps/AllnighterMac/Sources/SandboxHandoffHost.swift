import Foundation
import AllnighterCore
import AllnighterEngine

/// Hosts the sandbox hand-off while the app is open.
///
/// A caller inside a sandboxed host (today: Codex) can't start the vendor CLIs —
/// they need Keychain access the sandbox denies. It drops the request in the
/// shared mailbox instead; this drains that mailbox through the same
/// `RunService.run` every other path uses, and the caller reads its answer back
/// from the ordinary run journal.
///
/// Deliberately owns nothing: no window, no state, no UI. It exists so the app
/// is the thing that can run your tools when your terminal can't.
@MainActor
final class SandboxHandoffHost {
    static let shared = SandboxHandoffHost()

    private var task: Task<Void, Never>?

    private init() {}

    func start() {
        guard task == nil else { return }
        task = Task.detached(priority: .utility) {
            let configuration = AppConfig.loadConfiguration()
            let invocations = AppSetupModel.invocations(from: SetupStore().load().records)
            let runner = SandboxHandoffRunner(
                runService: RunService(
                    models: configuration.models,
                    registry: configuration.registry,
                    teams: TeamCatalog.all,
                    invocations: invocations
                ),
                owner: "mac-app"
            )
            await runner.run { Task.isCancelled }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
