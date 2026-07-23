import Foundation
import AllnighterCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Foreground resident coordinator for `alln serve`. Owns process lifetime,
/// health, and the one-shot Wake Ticket loop.
public final class ResidentCoordinator: @unchecked Sendable {
    public struct WakeDependencies: Sendable {
        public var models: [Model]
        public var registry: DriverRegistry
        public var teams: [TeamPreset]
        public var commandRunner: CommandRunner
        public var invocations: [String: ToolInvocation]
        public var runStore: RunStore
        public var sessionStore: ExternalWorkerSessionStore
        public var writeLock: RunWriteLockRegistry
        public var asyncTeam: AsyncTeamService
        public var readyModels: @Sendable () -> [Model]

        public init(
            models: [Model],
            registry: DriverRegistry,
            teams: [TeamPreset] = TeamCatalog.all,
            commandRunner: CommandRunner = SubprocessCommandRunner(environmentPolicy: AllnighterSpawnEnvironmentPolicy()),
            invocations: [String: ToolInvocation] = [:],
            runStore: RunStore = RunStore(),
            sessionStore: ExternalWorkerSessionStore = ExternalWorkerSessionStore(),
            writeLock: RunWriteLockRegistry = .shared,
            asyncTeam: AsyncTeamService,
            readyModels: @escaping @Sendable () -> [Model]
        ) {
            self.models = models
            self.registry = registry
            self.teams = teams
            self.commandRunner = commandRunner
            self.invocations = invocations
            self.runStore = runStore
            self.sessionStore = sessionStore
            self.writeLock = writeLock
            self.asyncTeam = asyncTeam
            self.readyModels = readyModels
        }
    }

    public struct RemoteDependencies: Sendable {
        public var coordinator: any RemoteMacAgentCoordinating

        public init(coordinator: any RemoteMacAgentCoordinating) {
            self.coordinator = coordinator
        }
    }

    public let binaryVersion: String
    public let contractVersion: String
    private let store: ResidentCoordinatorStore
    private let probe: ResidentCoordinatorProbe
    private let server: LoopbackHealthServer
    private let rendezvous: ResidentExecutionRendezvous
    private let wakeDependencies: WakeDependencies?
    private let remoteDependencies: RemoteDependencies?
    private let coordinatorId: String
    private let startedAt: Date

    public init(
        binaryVersion: String,
        contractVersion: String = ContractRegistry.contractVersion,
        store: ResidentCoordinatorStore = ResidentCoordinatorStore(),
        server: LoopbackHealthServer = LoopbackHealthServer(),
        rendezvous: ResidentExecutionRendezvous = ResidentExecutionRendezvous(),
        wakeDependencies: WakeDependencies? = nil,
        remoteDependencies: RemoteDependencies? = nil
    ) {
        self.binaryVersion = binaryVersion
        self.contractVersion = contractVersion
        self.store = store
        self.server = server
        self.rendezvous = rendezvous
        self.probe = ResidentCoordinatorProbe(store: store, rendezvous: rendezvous)
        self.wakeDependencies = wakeDependencies
        self.remoteDependencies = remoteDependencies
        self.coordinatorId = UUID().uuidString.lowercased()
        self.startedAt = Date()
    }

    /// Starts loopback health, writes durable state, runs wake loop until shutdown.
    /// Always clears durable state on exit.
    public func run(untilShutdown: @escaping @Sendable () async -> Void) async throws {
        _ = try rendezvous.prepareCoordinator(
            coordinatorId: coordinatorId,
            binaryVersion: binaryVersion,
            contractVersion: contractVersion
        )
        let healthProvider: @Sendable () -> String = { [probe, binaryVersion, contractVersion] in
            let health = probe.health(binaryVersion: binaryVersion, contractVersion: contractVersion)
            guard let data = try? CoreJSON.encode(health) else { return "{}" }
            return String(decoding: data, as: UTF8.self)
        }
        let port = try server.start(healthBody: healthProvider)
        let record = ResidentCoordinatorRecord(
            coordinatorId: coordinatorId,
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: startedAt,
            loopbackHost: "127.0.0.1",
            loopbackPort: port,
            binaryVersion: binaryVersion,
            contractVersion: contractVersion
        )
        try store.save(record)
        defer {
            server.stop()
            store.clear()
            rendezvous.deactivateCoordinator()
        }

        let shutdown = ShutdownFlag()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await untilShutdown()
                shutdown.fire()
            }
            if let wake = wakeDependencies {
                group.addTask { [rendezvous] in
                    let broker = ResidentExecutionBroker(
                        rendezvous: rendezvous,
                        dependencies: .init(
                            asyncTeam: wake.asyncTeam,
                            models: wake.models,
                            registry: wake.registry,
                            runStore: wake.runStore,
                            readyModels: wake.readyModels
                        )
                    )
                    await broker.run(isCancelled: { shutdown.isCancelled })
                }
                group.addTask {
                    let scheduler = PendingWakeScheduler(
                        models: wake.models,
                        registry: wake.registry,
                        commandRunner: wake.commandRunner,
                        invocations: wake.invocations
                    )
                    await scheduler.run { shutdown.isCancelled }
                }
                group.addTask {
                    let boost = BoostSeedScheduler(
                        registry: wake.registry,
                        models: wake.models,
                        commandRunner: wake.commandRunner,
                        invocations: wake.invocations
                    )
                    await boost.run { shutdown.isCancelled }
                }
                group.addTask { [coordinatorId] in
                    let service = RunService(
                        models: wake.models,
                        registry: wake.registry,
                        teams: wake.teams,
                        runStore: wake.runStore,
                        commandRunner: wake.commandRunner,
                        writeLock: wake.writeLock,
                        invocations: wake.invocations,
                        sessionStore: wake.sessionStore
                    )
                    let reconciler = VendorBackoffReconciler(
                        runStore: wake.runStore,
                        runService: service,
                        coordinatorId: coordinatorId
                    )
                    await reconciler.run { shutdown.isCancelled }
                }
            }
            if let remote = remoteDependencies {
                group.addTask {
                    await remote.coordinator.run { shutdown.isCancelled }
                }
            }
            await group.next()
            group.cancelAll()
        }
    }

    /// Blocks until SIGINT or SIGTERM.
    public func runUntilSignal() async throws {
        try await run(untilShutdown: Self.waitForShutdownSignal)
    }

    private static func waitForShutdownSignal() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resume = OnceResumer { continuation.resume() }
            let install: (Int32) -> Void = { sig in
                let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
                source.setEventHandler {
                    source.cancel()
                    resume.fire()
                }
                signal(sig, SIG_IGN)
                source.resume()
            }
            install(SIGINT)
            install(SIGTERM)
        }
    }
}

/// Shared shutdown flag for health block and wake loop.
final class ShutdownFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func fire() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// Ensures shutdown resumes at most once.
private final class OnceResumer: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private let action: () -> Void

    init(_ action: @escaping () -> Void) { self.action = action }

    func fire() {
        lock.lock()
        defer { lock.unlock() }
        guard !fired else { return }
        fired = true
        action()
    }
}
