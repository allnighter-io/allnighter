import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import AllnighterCore

// MARK: - capacity.sock (CWB-S02)
//
// Instant capacity = a **read** of the resident's gated in-memory snapshot
// over a local AF_UNIX socket while the Dock app is open. Product law
// (`docs/phases/Capacity_Warm_Bench.md`):
//
// - The socket is **read-only** — it never starts an acquire. Serving is a
//   memory read of the last published answer (`update(_:)`), nothing else.
// - Feature OFF answers **disabled**, never a stale snapshot.
// - App quit unlinks the socket; a hard kill leaves a stale file that the
//   next launch reconciles by unlink-before-bind (we never claim sync crash
//   cleanup).
// - CLI: try the socket once; serve only a settled snapshot younger than
//   the 30m paint gate. Warming, stale, miss, hang, or bad version → one
//   cold `CapacityFetch.liveSnapshot`. Never a retry loop against the socket.

// MARK: - Wire payload

/// Versioned read-only snapshot JSON served over `capacity.sock`.
///
/// Schema v1 fields:
/// - `schemaVersion` — must equal `currentSchemaVersion` or the client
///   treats the answer as foreign and falls back cold (version skew between
///   an old app and a new CLI must never decode into a lie).
/// - `disabled` — feature OFF answer. Carries no seats: OFF must not leak a
///   stale snapshot.
/// - `settledAt` — settle time of the resident snapshot; nil while warming
///   (app ON, no settle yet). Age is derived by the consumer's own clock —
///   the payload carries the settle instant, never a pre-computed age that
///   could go stale on the wire.
/// - `windows` — latest settled per-seat windows, **ungated**. Consumers
///   apply `CapacityPaintGate` with their own `now` so a snapshot past the
///   30-minute gate paints expired instead of fresh.
public struct CapacitySocketSnapshot: Sendable, Equatable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let disabled: Bool
    public let settledAt: Date?
    public let windows: [CapacityWindow]

    public init(
        schemaVersion: Int = CapacitySocketSnapshot.currentSchemaVersion,
        disabled: Bool,
        settledAt: Date?,
        windows: [CapacityWindow]
    ) {
        self.schemaVersion = schemaVersion
        self.disabled = disabled
        self.settledAt = settledAt
        self.windows = windows
    }

    /// Feature OFF answer — disabled, no seats (never a stale snapshot).
    public static let disabledAnswer = CapacitySocketSnapshot(
        disabled: true, settledAt: nil, windows: []
    )

    /// App ON but no settle yet — the honest launch state. The CLI instant
    /// path treats this as a miss and live-acquires (`servesAsFreshSnapshot`).
    public static let warmingAnswer = CapacitySocketSnapshot(
        disabled: false, settledAt: nil, windows: []
    )

    public func encoded() -> Data {
        (try? CoreJSON.encode(self)) ?? Data()
    }

    /// Strict decode: malformed payload or foreign schema version → nil.
    /// The caller falls back to one cold acquire — never retries the socket.
    public static func decode(_ data: Data) -> CapacitySocketSnapshot? {
        guard let snapshot = try? CoreJSON.decode(Self.self, from: data),
              snapshot.schemaVersion == Self.currentSchemaVersion else { return nil }
        return snapshot
    }
}

// MARK: - Fast-path mapping (pure)

/// Maps a socket answer to a renderable bench snapshot. Pure — no IO, no
/// clocks, and by construction **no probes**: every branch assembles rows
/// from data already in memory.
public enum CapacitySocketFastPath {

    /// Instant path is only a *settled* snapshot younger than the paint gate.
    ///
    /// Warming (`settledAt == nil`) and settled-but-stale both miss — the
    /// caller falls through to one live acquire. Disabled is also a miss;
    /// feature OFF is handled before the socket is read. One clock:
    /// `CapacityPaintGate.gateInterval` (30m).
    public static func servesAsFreshSnapshot(
        _ answer: CapacitySocketSnapshot,
        now: Date
    ) -> Bool {
        guard !answer.disabled, let settledAt = answer.settledAt else { return false }
        return now.timeIntervalSince(settledAt) < CapacityPaintGate.gateInterval
    }

    /// - disabled answer → honest disabled rows (never a stale snapshot).
    /// - warming (no settle yet) → `neverSampled` launch placeholders.
    /// - settled → windows paint-gated at the caller's clock (age always
    ///   honest; a snapshot past the 30m gate expires client-side), then
    ///   completed against the CLI's own compiled bench roster.
    ///
    /// The CLI instant path calls this only after `servesAsFreshSnapshot`.
    /// Warming/stale mapping stays so other readers can still name the
    /// honest empty/expired state without inventing numbers.
    public static func snapshot(
        from answer: CapacitySocketSnapshot,
        now: Date
    ) -> CapacityFetch.Snapshot {
        if answer.disabled {
            return CapacityFetch.disabledSnapshot(now: now)
        }
        guard let settledAt = answer.settledAt else {
            let windows = CapacityFetch.launchPlaceholders(now: now)
            return CapacityFetch.Snapshot(
                now: now,
                windows: windows,
                rows: CapacityBenchProjection.rows(from: windows, now: now)
            )
        }
        let gated = CapacityPaintGate.paintedWindows(
            answer.windows, settledAt: settledAt, now: now
        )
        let complete = completingMissingBenchSeats(gated, now: now)
        return CapacityFetch.Snapshot(
            now: now,
            windows: complete,
            rows: CapacityBenchProjection.rows(from: complete, now: now)
        )
    }

    /// Pads any seat on `CapacityAcquisition.benchSourceOrder` that is absent
    /// from a settled resident answer with an honest `neverSampled` unknown.
    ///
    /// A resident process compiled before a seat was promoted onto the bench
    /// (e.g. the OpenCode Go dashboard seat, OCG-S08) has no way to know that
    /// seat exists — its in-memory snapshot simply omits it. Without this
    /// step the fast path would silently render one row short of the current
    /// roster instead of an honest unknown; this is the CLI-side merge (the
    /// resident stays the single owner of *how* a seat is acquired, the CLI's
    /// own compiled `benchSourceOrder` stays the single owner of *which*
    /// seats exist — no second hand-maintained roster). Never invents a
    /// value: a missing seat paints `neverSampled`, matching the same reason
    /// `CapacityAcquisition.windows` uses for an unprobed seat.
    private static func completingMissingBenchSeats(
        _ windows: [CapacityWindow], now: Date
    ) -> [CapacityWindow] {
        let present = Set(windows.map(\.source))
        let missing = CapacityAcquisition.benchSourceOrder.filter { !present.contains($0) }
        guard !missing.isEmpty else { return windows }
        return windows + missing.map { source in
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: source,
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe
            )
        }
    }
}

// MARK: - Server (Dock app side)

/// Read-only AF_UNIX snapshot server bound at `capacity.sock` by the Dock app.
///
/// The served bytes are whatever `update(_:)` last published — serving a
/// connection is a lock, a copy, and a write. There is no request message
/// and no code path from this type into `CapacityFetch` / PTYs: the socket
/// cannot start an acquire even if a client asks.
public final class CapacitySocketServer: @unchecked Sendable {

    public enum StartError: Error, Equatable {
        case alreadyRunning
        /// `sun_path` holds 104 bytes; a longer support path cannot bind.
        case pathTooLong(actual: Int, max: Int)
        case directoryCreateFailed(String)
        case socketFailed(Int32)
        case bindFailed(Int32)
        case listenFailed(Int32)
    }

    private let lock = NSLock()
    private let path: String
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    /// Last published answer bytes. Read on every connection; written only
    /// by `update(_:)` (resident settle / ON/OFF transitions).
    private var payload: Data

    public init(path: URL = AllnighterPaths.capacitySocket) {
        self.path = path.path
        self.payload = CapacitySocketSnapshot.warmingAnswer.encoded()
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return listenFD >= 0
    }

    /// Publish the answer connections will receive. Thread-safe; called by
    /// the resident publisher on every settle and ON/OFF transition.
    public func update(_ snapshot: CapacitySocketSnapshot) {
        let data = snapshot.encoded()
        lock.lock()
        payload = data
        lock.unlock()
    }

    /// Bind + listen. Any pre-existing file at the path is unlinked first —
    /// that is the hard-kill reconcile story: a crashed app leaves a stale
    /// socket file, and the next launch owns the path again.
    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard listenFD < 0 else { throw StartError.alreadyRunning }

        let maxPath = MemoryLayout<sockaddr_un>.size > 0
            ? MemoryLayout.size(ofValue: sockaddr_un().sun_path)
            : 104
        guard path.utf8.count < maxPath else {
            throw StartError.pathTooLong(actual: path.utf8.count, max: maxPath)
        }

        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
        } catch {
            throw StartError.directoryCreateFailed(error.localizedDescription)
        }
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.socketFailed(errno) }
        defer { if listenFD < 0 { close(fd) } }

        guard var addr = Self.unixAddress(path: path) else {
            throw StartError.pathTooLong(actual: path.utf8.count, max: maxPath)
        }
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw StartError.bindFailed(errno) }
        guard listen(fd, SOMAXCONN) == 0 else { throw StartError.listenFailed(errno) }

        listenFD = fd
        let source = DispatchSource.makeReadSource(
            fileDescriptor: fd, queue: .global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in self?.acceptConnections() }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        acceptSource = source
    }

    /// Graceful quit / teardown: close the listener and **unlink** the path
    /// so a later CLI sees a clean miss (one cold acquire) instead of a
    /// refused stale endpoint.
    public func stop() {
        lock.lock()
        let source = acceptSource
        acceptSource = nil
        listenFD = -1
        lock.unlock()
        source?.cancel()
        unlink(path)
    }

    private func acceptConnections() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { break }
            Task.detached(priority: .userInitiated) { [weak self] in
                self?.serve(on: client)
            }
        }
    }

    /// Write the current answer and close. The connection is never read —
    /// there is one endpoint and one verb (GET the snapshot), so a client
    /// that sends bytes cannot steer anything. A bounded send timeout keeps
    /// a vanished client from parking a server task.
    private func serve(on client: Int32) {
        defer { close(client) }
        var sendTimeout = timeval()
        sendTimeout.tv_sec = 2
        setsockopt(
            client, SOL_SOCKET, SO_SNDTIMEO,
            &sendTimeout, socklen_t(MemoryLayout<timeval>.size)
        )
        lock.lock()
        let data = payload
        lock.unlock()
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let written = write(client, base + sent, data.count - sent)
                guard written > 0 else { break }
                sent += written
            }
        }
    }

    /// `sockaddr_un` for `path`, or nil when it cannot fit `sun_path`.
    static func unixAddress(path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        #if canImport(Darwin)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        let bytes = Array(path.utf8)
        guard bytes.count < capacity else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
                _ = bytes.withUnsafeBufferPointer { src in
                    memcpy(dest, src.baseAddress, src.count)
                }
                dest[bytes.count] = 0
            }
        }
        return addr
    }
}

// MARK: - Client (CLI side)

/// One-shot socket read for `alln capacity`. Hard-budgeted: ANY failure —
/// no file, stale listener, hang, oversized or malformed payload, foreign
/// schema version — returns nil, and the caller falls back to **one** cold
/// live acquire. There is deliberately no retry: the socket is an
/// optimization over the honest cold path, not a dependency.
public enum CapacitySocketClient {

    /// Default fast-path budget. Well under any human-perceptible wait; a
    /// healthy resident answers in microseconds.
    public static let defaultTimeout: TimeInterval = 1.0

    /// Upper bound on a plausible six-seat answer. A runaway writer gets cut
    /// off and treated as a miss.
    public static let maxPayloadBytes = 256 * 1024

    public static func read(
        path: URL = AllnighterPaths.capacitySocket,
        timeout: TimeInterval = defaultTimeout
    ) -> CapacitySocketSnapshot? {
        guard let data = readRaw(path: path.path, timeout: timeout) else { return nil }
        return CapacitySocketSnapshot.decode(data)
    }

    /// Connect + read-to-EOF with a hard budget at each step:
    /// non-blocking connect behind `poll`, then blocking reads behind
    /// `SO_RCVTIMEO`. Any nil anywhere means "go cold once".
    static func readRaw(path: String, timeout: TimeInterval) -> Data? {
        guard var addr = CapacitySocketServer.unixAddress(path: path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        // Non-blocking connect behind a poll budget — a wedged listener must
        // not turn the CLI into the hang this path exists to avoid.
        let originalFlags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK)
        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connectResult != 0 {
            guard errno == EINPROGRESS else { return nil }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let budgetMs = Int32(max(1, timeout * 1000))
            guard poll(&pfd, 1, budgetMs) > 0,
                  (pfd.revents & Int16(POLLOUT)) != 0 else { return nil }
            var connectError: Int32 = 0
            var errorLen = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &connectError, &errorLen) == 0,
                  connectError == 0 else { return nil }
        }
        _ = fcntl(fd, F_SETFL, originalFlags)

        var receiveTimeout = timeval()
        receiveTimeout.tv_sec = Int(timeout)
        let fractional = timeout - Double(Int(timeout))
        #if canImport(Darwin)
        receiveTimeout.tv_usec = Int32(fractional * 1_000_000)
        #else
        receiveTimeout.tv_usec = Int(fractional * 1_000_000)
        #endif
        setsockopt(
            fd, SOL_SOCKET, SO_RCVTIMEO,
            &receiveTimeout, socklen_t(MemoryLayout<timeval>.size)
        )

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while data.count < maxPayloadBytes {
            let count = buffer.withUnsafeMutableBytes { ptr in
                Self.sysRead(fd, ptr.baseAddress, ptr.count)
            }
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard !data.isEmpty else { return nil }
        return data
    }

    /// POSIX `read` disambiguated from `CapacitySocketClient.read`.
    private static func sysRead(
        _ fd: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int
    ) -> Int {
        #if canImport(Darwin)
        return Darwin.read(fd, buffer, count)
        #elseif canImport(Glibc)
        return Glibc.read(fd, buffer, count)
        #endif
    }
}
