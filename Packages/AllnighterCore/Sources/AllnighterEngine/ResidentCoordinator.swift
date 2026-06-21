import Foundation
import AllnighterCore
import Darwin

/// Foreground resident coordinator for `alln serve`. Owns process lifetime,
/// health, and the one-shot Wake Ticket loop.
public final class ResidentCoordinator: @unchecked Sendable {
    public struct WakeDependencies: Sendable {
        public var models: [Model]
        public var registry: DriverRegistry
        public var commandRunner: CommandRunner
        public var invocations: [String: ToolInvocation]

        public init(
            models: [Model],
            registry: DriverRegistry,
            commandRunner: CommandRunner = SubprocessCommandRunner(),
            invocations: [String: ToolInvocation] = [:]
        ) {
            self.models = models
            self.registry = registry
            self.commandRunner = commandRunner
            self.invocations = invocations
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
    private let wakeDependencies: WakeDependencies?
    private let remoteDependencies: RemoteDependencies?
    private let coordinatorId: String
    private let startedAt: Date

    public init(
        binaryVersion: String,
        contractVersion: String = ContractRegistry.contractVersion,
        store: ResidentCoordinatorStore = ResidentCoordinatorStore(),
        server: LoopbackHealthServer = LoopbackHealthServer(),
        wakeDependencies: WakeDependencies? = nil,
        remoteDependencies: RemoteDependencies? = nil
    ) {
        self.binaryVersion = binaryVersion
        self.contractVersion = contractVersion
        self.store = store
        self.probe = ResidentCoordinatorProbe(store: store)
        self.server = server
        self.wakeDependencies = wakeDependencies
        self.remoteDependencies = remoteDependencies
        self.coordinatorId = UUID().uuidString.lowercased()
        self.startedAt = Date()
    }

    /// Starts loopback health, writes durable state, runs wake loop until shutdown.
    /// Always clears durable state on exit.
    public func run(untilShutdown: @escaping @Sendable () async -> Void) async throws {
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
        }

        let shutdown = ShutdownFlag()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await untilShutdown()
                shutdown.fire()
            }
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
