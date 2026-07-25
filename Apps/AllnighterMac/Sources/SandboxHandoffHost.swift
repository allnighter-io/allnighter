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
            HandoffLog.event("host started pid=\(ProcessInfo.processInfo.processIdentifier)")
            let runner = SandboxHandoffRunner(
                // Reloaded per claimed request, never snapshotted at launch. An app
                // open all day used to keep the roster and invocation map it read at
                // startup, then refuse work once either changed on disk — with no
                // journal and no log, which is what made the original failure
                // undiagnosable. Idle cost is zero: this runs only when there is work.
                makeRunService: {
                    let configuration = AppConfig.loadConfiguration()
                    return RunService(
                        models: configuration.models,
                        registry: configuration.registry,
                        teams: TeamCatalog.all,
                        invocations: AppSetupModel.invocations(from: SetupStore().load().records)
                    )
                },
                owner: "mac-app"
            )
            await runner.run { Task.isCancelled }
            HandoffLog.event("host stopped pid=\(ProcessInfo.processInfo.processIdentifier)")
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
