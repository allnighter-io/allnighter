import Foundation
import AllnighterCore
import AllnighterEngine

/// GUI-side Loop construction (R-S08, `docs/phases/PM_Relay.md` §6). Mirrors
/// `LoopDispatch.makeCoordinator(runtime:)` (`AllnighterCLI`) field-for-field so a relay
/// launched from the Mac app dispatches through the exact same `RunService` shape and the
/// exact same `LoopThreadProjector` default (`ThreadStore()`/`RunStore()` roots) as the CLI
/// paths — CLI/GUI relays are indistinguishable once running.
///
/// This can't literally CALL `LoopDispatch.makeCoordinator` — `AllnighterCLI` is an
/// `executableTarget` (`Packages/AllnighterCore/Package.swift`), not a library product, so
/// the Mac app target cannot import it. Instead this sources `models`/`registry`/
/// `invocations` the same way the Mac app already does everywhere else
/// (`AppConfig.loadConfiguration()` + cached `SetupStore` invocations — see
/// `ThreadsViewModel`'s production `init`), which is the functional equivalent of
/// `ToolRuntime()`'s own sourcing (`DefaultConfig.registry` + `ModelCatalog.resolvedModels`
/// + cached `SetupStore` invocations): same registry/model catalog data on disk, same
/// transform. `teams` and every other `RunService` parameter are left at their defaults,
/// which are themselves `TeamCatalog.all` / house defaults — identical to what
/// `LoopDispatch.makeCoordinator` passes explicitly.
enum RelayGUIRuntime {
    /// One relay id, matching `LoopCoordinator`'s own default `idFactory` format
    /// (`"relay_\(UUID().uuidString.lowercased())"`) — callers that need to know the id
    /// BEFORE the coordinator's `run()` returns (so the GUI can select the thread the
    /// moment it exists) generate it here and hand it back to `makeCoordinator(idFactory:)`.
    static func newRelayId() -> String {
        "relay_\(UUID().uuidString.lowercased())"
    }

    /// Builds a `LoopCoordinator` construction-identical to `LoopDispatch.makeCoordinator`.
    /// `idFactory` defaults to a fresh `newRelayId()` per call (matching
    /// `LoopCoordinator.init`'s own default) but callers starting a NEW relay from the GUI
    /// should pass a fixed closure returning an id they generated up front (see
    /// `RelayLaunchViewModel.start`).
    static func makeCoordinator(
        idFactory: @escaping @Sendable () -> String = { RelayGUIRuntime.newRelayId() }
    ) -> LoopCoordinator {
        let configuration = AppConfig.loadConfiguration()
        let invocations = AppSetupModel.invocations(from: SetupStore().load().records)
        return LoopCoordinator(
            runService: RunService(
                models: configuration.models,
                registry: configuration.registry,
                teams: TeamCatalog.all,
                invocations: invocations
            ),
            // R-S07: real relays always project into the inbox — default `ThreadStore()`/
            // `RunStore()` roots, exactly like `LoopDispatch.makeCoordinator`.
            threadProjector: LoopThreadProjector(),
            idFactory: idFactory
        )
    }

    /// Resolves a persisted relay's `projectRoot` back to a `Project.id`, mirroring
    /// `AllnighterCLI.resolveProject`'s normalized-root match (that function isn't visible
    /// to the Mac app for the same module-boundary reason as `LoopDispatch` above). `nil`
    /// degrades gracefully — `LoopCoordinator.resume` only needs `projectId` to stamp the
    /// `RunRequest`; every other resume field re-derives from the persisted `LoopState`.
    static func resolveProjectId(forRoot root: String, store: ProjectStore) -> String? {
        let key = RootNormalization.normalize(root).key
        return (try? store.activeProjects())?.first { $0.normalizedRootPath == key }?.id
    }

    /// `--until HH:MM` parsing, ported from `LoopDispatch.parseUntil` (same module-boundary
    /// reason — not visible to the Mac app). Next occurrence of that local clock time (today
    /// if still ahead, else tomorrow); `nil`/unparseable input means no deadline.
    static func parseUntil(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0..<24).contains(hour),
              (0..<60).contains(minute) else { return nil }
        var calendar = Calendar.current
        calendar.timeZone = .current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard var deadline = calendar.date(from: components) else { return nil }
        if deadline <= now {
            deadline = calendar.date(byAdding: .day, value: 1, to: deadline) ?? deadline
        }
        return deadline
    }
}
