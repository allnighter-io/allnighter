import Foundation
import AllnighterCore

/// Injectable sleep for deterministic wake-loop tests.
public protocol PendingWakeSleeper: Sendable {
    func sleep(until: Date, jitterSeconds: TimeInterval) async throws
}

public struct DefaultPendingWakeSleeper: PendingWakeSleeper {
    public init() {}

    public func sleep(until: Date, jitterSeconds: TimeInterval) async throws {
        let jitter = jitterSeconds > 0 ? TimeInterval(Int.random(in: 0...Int(jitterSeconds))) : 0
        let target = until.addingTimeInterval(jitter)
        let interval = target.timeIntervalSinceNow
        guard interval > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}

/// Resident one-shot wake loop for due workerChat Wake Tickets (WTK-S03).
public struct PendingWakeScheduler: Sendable {
    public var store: PendingStore
    public var models: [Model]
    public var registry: DriverRegistry
    public var commandRunner: CommandRunner
    public var invocations: [String: ToolInvocation]
    public var now: @Sendable () -> Date
    public var sleeper: any PendingWakeSleeper
    public var jitterSeconds: TimeInterval

    public init(
        store: PendingStore = PendingStore(),
        models: [Model],
        registry: DriverRegistry,
        commandRunner: CommandRunner = SubprocessCommandRunner(),
        invocations: [String: ToolInvocation] = [:],
        now: @escaping @Sendable () -> Date = Date.init,
        sleeper: any PendingWakeSleeper = DefaultPendingWakeSleeper(),
        jitterSeconds: TimeInterval = 60
    ) {
        self.store = store
        self.models = models
        self.registry = registry
        self.commandRunner = commandRunner
        self.invocations = invocations
        self.now = now
        self.sleeper = sleeper
        self.jitterSeconds = jitterSeconds
    }

    /// Runs until `isCancelled` returns true. Reloads Pending truth before each attempt.
    public func run(isCancelled: @escaping @Sendable () -> Bool) async {
        while !isCancelled() {
            let items: [PendingItem]
            do { items = try store.loadOrdered().items } catch { break }

            let plan = PendingWakePlanner.plan(items: items, now: now())
            if let dueId = plan.dueItemId {
                await runOneWake(itemId: dueId, isCancelled: isCancelled)
                continue
            }

            guard let nextWake = plan.nextWakeAt else {
                try? await sleeper.sleep(until: now().addingTimeInterval(300), jitterSeconds: 0)
                continue
            }
            do {
                try await sleeper.sleep(until: nextWake, jitterSeconds: jitterSeconds)
            } catch {
                break
            }
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
