import Foundation
import AllnighterCore
import Darwin

/// Foreground resident coordinator for `alln serve`. Owns process lifetime and
/// health only — product semantics remain in `AllnighterCore`.
public final class ResidentCoordinator: @unchecked Sendable {
    public let binaryVersion: String
    public let contractVersion: String
    private let store: ResidentCoordinatorStore
    private let probe: ResidentCoordinatorProbe
    private let server: LoopbackHealthServer
    private let coordinatorId: String
    private let startedAt: Date

    public init(
        binaryVersion: String,
        contractVersion: String = ContractRegistry.contractVersion,
        store: ResidentCoordinatorStore = ResidentCoordinatorStore(),
        server: LoopbackHealthServer = LoopbackHealthServer()
    ) {
        self.binaryVersion = binaryVersion
        self.contractVersion = contractVersion
        self.store = store
        self.probe = ResidentCoordinatorProbe(store: store)
        self.server = server
        self.coordinatorId = UUID().uuidString.lowercased()
        self.startedAt = Date()
    }

    /// Starts loopback health, writes durable state, and blocks until shutdown.
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
        await untilShutdown()
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
