import Foundation
import AllnighterCore

/// Injectable sleep for deterministic wake-loop tests.
public protocol PendingWakeSleeper: Sendable {
    func sleep(until: Date, jitterSeconds: TimeInterval) async throws
}

public struct DefaultPendingWakeSleeper: PendingWakeSleeper {
    private let waiter: WakeSafeWaiter

    public init(
        now: @escaping @Sendable () -> Date = Date.init,
        performSleep: @escaping @Sendable (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    ) {
        self.waiter = WakeSafeWaiter(maxNapSeconds: 60, now: now, performSleep: performSleep)
    }

    public func sleep(until: Date, jitterSeconds: TimeInterval) async throws {
        try await waiter.sleep(until: until, jitterSeconds: jitterSeconds)
    }
}

/// Resident one-shot wake loop for due workerChat Wake Tickets (WTK-S03).
public struct PendingWakeScheduler: Sendable {
    public static let progressId = "pendingWake"

    public var store: PendingStore
    public var models: [Model]
    public var registry: DriverRegistry
    public var commandRunner: CommandRunner
    public var invocations: [String: ToolInvocation]
    public var now: @Sendable () -> Date
    public var sleeper: any PendingWakeSleeper
    public var jitterSeconds: TimeInterval
    public var progress: any SchedulerProgressReporting
    private let _overshootBox = OvershootBox()

    private final class OvershootBox: @unchecked Sendable {
        var value: TimeInterval?
    }

    public var lastWakeOvershoot: TimeInterval? {
        _overshootBox.value
    }

    public init(
        store: PendingStore = PendingStore(),
        models: [Model],
        registry: DriverRegistry,
        commandRunner: CommandRunner = SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()),
        invocations: [String: ToolInvocation] = [:],
        now: @escaping @Sendable () -> Date = Date.init,
        sleeper: any PendingWakeSleeper = WakeSafeWaiter(),
        jitterSeconds: TimeInterval = 60,
        progress: any SchedulerProgressReporting = NoOpSchedulerProgress()
    ) {
        self.store = store
        self.models = models
        self.registry = registry
        self.commandRunner = commandRunner
        self.invocations = invocations
        self.now = now
        self.sleeper = sleeper
        self.jitterSeconds = jitterSeconds
        self.progress = progress
    }

    /// Runs until `isCancelled` returns true. Reloads Pending truth before each attempt.
    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        while !isCancelled() {
            let items: [PendingItem]
            do { items = try store.loadOrdered().items } catch { break }

            let plan = PendingWakePlanner.plan(items: items, now: now())
            if let dueId = plan.dueItemId {
                progress.attempting(id: Self.progressId)
                await runOneWake(itemId: dueId, isCancelled: isCancelled)
                progress.succeeded(id: Self.progressId)
                continue
            }

            guard let nextWake = plan.nextWakeAt else {
                try? await recordOvershoot { try await sleeper.sleep(until: now().addingTimeInterval(300), jitterSeconds: 0) }
                continue
            }
            do {
                progress.waiting(id: Self.progressId, until: nextWake)
                try await recordOvershoot { try await sleeper.sleep(until: nextWake, jitterSeconds: jitterSeconds) }
            } catch {
                progress.failed(
                    id: Self.progressId,
                    error: "pendingWake sleep failed: \(error.localizedDescription)"
                )
                break
            }
        }
    }

    private func recordOvershoot(_ block: () async throws -> Void) async rethrows {
        try await block()
        if let waiter = sleeper as? WakeSafeWaiter {
            _overshootBox.value = waiter.lastOvershoot
        }
    }

    private func runOneWake(itemId: String, isCancelled: @escaping @Sendable () -> Bool) async {
        guard !isCancelled() else { return }
        guard let item = try? store.load(id: itemId) else { return }
        let plan = PendingWakePlanner.plan(items: [item], now: now())
        guard plan.dueItemId == itemId else { return }

        let service = PendingService(store: store, models: models, now: now)
        let executor = PendingRunExecutor(
            service: service,
            registry: registry,
            commandRunner: commandRunner,
            invocations: invocations,
            now: now
        )
        _ = try? await executor.run(
            id: itemId,
            options: .init(beginRun: .wakeTicket)
        )
    }
}
