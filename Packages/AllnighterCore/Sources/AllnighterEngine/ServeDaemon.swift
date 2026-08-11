import Foundation
import AllnighterCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Background daemon for `alln serve`. Owns process lifetime, loopback health,
/// and the scheduler loops (Pending wake, Boost seeding, vendor-backoff
/// continuation, local OS notifications for relay/pilot/team-run state, and
/// the optional cloud relay).
///
/// It owns NO run semantics and exposes no request/response surface. Code Red
/// deleted the resident execution control plane that used to be hosted here;
/// every scheduler below calls `RunService`/`AsyncTeamService` directly,
/// in-process, exactly as a foreground `alln run` does.
public final class ServeDaemon: @unchecked Sendable {
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
    public let binaryGitSha: String
    public let contractVersion: String
    private let store: ServeDaemonStore
    private let probe: ServeDaemonProbe
    private let server: LoopbackHealthServer
    private let pmTurnWakeScheduler: PMTurnWakeScheduler
    private let wakeDependencies: WakeDependencies?
    private let remoteDependencies: RemoteDependencies?
    private let receipts: ServeRuntimeReceipts
    private let daemonId: String
    private let startedAt: Date

    public init(
        binaryVersion: String,
        binaryGitSha: String = AllnighterBuildInfo.gitSha,
        contractVersion: String = ContractRegistry.contractVersion,
        store: ServeDaemonStore = ServeDaemonStore(),
        receipts: ServeRuntimeReceipts = ServeRuntimeReceipts(),
        server: LoopbackHealthServer = LoopbackHealthServer(),
        pmTurnWakeScheduler: PMTurnWakeScheduler = PMTurnWakeScheduler(),
        wakeDependencies: WakeDependencies? = nil,
        remoteDependencies: RemoteDependencies? = nil
    ) {
        self.binaryVersion = binaryVersion
        self.binaryGitSha = binaryGitSha
        self.contractVersion = contractVersion
        self.store = store
        self.receipts = receipts
        self.server = server
        self.probe = ServeDaemonProbe(store: store)
        self.pmTurnWakeScheduler = pmTurnWakeScheduler
        self.wakeDependencies = wakeDependencies
        self.remoteDependencies = remoteDependencies
        self.daemonId = UUID().uuidString.lowercased()
        self.startedAt = Date()
    }

    /// Starts loopback health, writes durable state, runs the scheduler loops
    /// until shutdown. Always clears durable state on exit.
    public func run(untilShutdown: @escaping @Sendable () async -> Void) async throws {
        let healthProvider: @Sendable () -> String = { [probe, binaryVersion, binaryGitSha, contractVersion] in
            let health = probe.health(binaryVersion: binaryVersion, binaryGitSha: binaryGitSha, contractVersion: contractVersion)
            guard let data = try? CoreJSON.encode(health) else { return "{}" }
            return String(decoding: data, as: UTF8.self)
        }
        let port = try server.start(healthBody: healthProvider)
        let record = ServeDaemonRecord(
            daemonId: daemonId,
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: startedAt,
            loopbackHost: "127.0.0.1",
            loopbackPort: port,
            binaryVersion: binaryVersion,
            binaryGitSha: binaryGitSha,
            contractVersion: contractVersion
        )
        try store.save(record)
        defer {
            server.stop()
            store.clear()
        }

        let shutdown = ShutdownFlag()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await untilShutdown()
                shutdown.fire()
            }
            group.addTask {
                await self.pmTurnWakeScheduler.run { shutdown.isCancelled }
            }
            _ = receipts.register(schedulerId: "pmTurnWake", daemonId: daemonId, pid: ProcessInfo.processInfo.processIdentifier, startedAt: startedAt)
            if let wake = wakeDependencies {
                group.addTask {
                    let scheduler = PendingWakeScheduler(
                        models: wake.models,
                        registry: wake.registry,
                        commandRunner: wake.commandRunner,
                        invocations: wake.invocations
                    )
                    await scheduler.run { shutdown.isCancelled }
                }
                _ = receipts.register(schedulerId: "pendingWake", daemonId: daemonId, pid: ProcessInfo.processInfo.processIdentifier, startedAt: startedAt)
                group.addTask {
                    let boost = BoostSeedScheduler(
                        registry: wake.registry,
                        models: wake.models,
                        commandRunner: wake.commandRunner,
                        invocations: wake.invocations
                    )
                    await boost.run { shutdown.isCancelled }
                }
                _ = receipts.register(schedulerId: "boostSeed", daemonId: daemonId, pid: ProcessInfo.processInfo.processIdentifier, startedAt: startedAt)
                group.addTask { [daemonId] in
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
                        coordinatorId: daemonId
                    )
                    await reconciler.run { shutdown.isCancelled }
                }
                _ = receipts.register(schedulerId: "vendorBackoff", daemonId: daemonId, pid: ProcessInfo.processInfo.processIdentifier, startedAt: startedAt)
                group.addTask {
                    // Capacity refresh without the Dock app (Probe_Freshness
                    // §0.2). No-ops while the app is refreshing, because both
                    // write the same durable history and this loop reads its
                    // recency — see CapacityRefreshScheduler.
                    await CapacityRefreshScheduler().run { shutdown.isCancelled }
                }
                _ = receipts.register(schedulerId: "capacityRefresh", daemonId: daemonId, pid: ProcessInfo.processInfo.processIdentifier, startedAt: startedAt)
                group.addTask {
                    // Probe_Freshness founder B 2026-08-09
                    await ProbeRecordRefreshScheduler().run { shutdown.isCancelled }
                }
                _ = receipts.register(schedulerId: "probeRecordRefresh", daemonId: daemonId, pid: ProcessInfo.processInfo.processIdentifier, startedAt: startedAt)
                group.addTask {
                    let notifications = NotificationScheduler(
                        commandRunner: wake.commandRunner,
                        models: wake.models,
                        registry: wake.registry
                    )
                    await notifications.run { shutdown.isCancelled }
                }
                _ = receipts.register(schedulerId: "notifications", daemonId: daemonId, pid: ProcessInfo.processInfo.processIdentifier, startedAt: startedAt)
            }
            if let remote = remoteDependencies {
                group.addTask {
                    await remote.coordinator.run { shutdown.isCancelled }
                }
                _ = receipts.register(schedulerId: "cloudRelay", daemonId: daemonId, pid: ProcessInfo.processInfo.processIdentifier, startedAt: startedAt)
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
