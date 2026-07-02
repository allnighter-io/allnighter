import Foundation

public enum OpenCodeServeCoordinatorError: Error, Sendable, Equatable {
    case opencodeExecutableNotFound
    case spawnFailed(underlyingDescription: String)
    case healthCheckTimedOut(diagnostics: String?)
    case portOwnedByForeignProcess(listenerPID: Int32)
}

public struct OpenCodeServeCoordinator: Sendable {
    public static let defaultPort = 4096

    /// Kill an idle `opencode serve` we spawned after this many seconds (default 15 min).
    /// Override: `ALLNIGHTER_OPENCODE_SERVE_IDLE_SECONDS`.
    public static var idleTTLSeconds: Int {
        if let raw = ProcessInfo.processInfo.environment["ALLNIGHTER_OPENCODE_SERVE_IDLE_SECONDS"],
           let value = Int(raw), value > 0 {
            return value
        }
        return 15 * 60
    }

    public static var defaultURL: URL {
        URL(string: "http://127.0.0.1:\(defaultPort)")!
    }

    /// Process-wide spawn state — every coordinator instance shares ownership of one child.
    private static let sharedState = SpawnState()

    private let healthCheck: @Sendable () async -> Bool
    private let portListenerPID: @Sendable (Int) -> Int32?
    private let launchServe: @Sendable () async throws -> LaunchedServe
    private let state: SpawnState

    public init(healthCheck: @escaping @Sendable () async -> Bool = {
            var req = URLRequest(url: OpenCodeServeCoordinator.defaultURL)
            req.httpMethod = "GET"
            req.timeoutInterval = 2
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    return true
                }
                return false
            } catch {
                return false
            }
        }) {
        self.init(
            healthCheck: healthCheck,
            portListenerPID: Self.portListenerPID,
            launchServe: Self.defaultLaunchServe
        )
    }

    init(
        healthCheck: @escaping @Sendable () async -> Bool,
        portListenerPID: @escaping @Sendable (Int) -> Int32?,
        launchServe: @escaping @Sendable () async throws -> LaunchedServe,
        state: SpawnState = OpenCodeServeCoordinator.sharedState
    ) {
        self.healthCheck = healthCheck
        self.portListenerPID = portListenerPID
        self.launchServe = launchServe
        self.state = state
    }

    public func isHealthy() async -> Bool {
        await healthCheck()
    }

    public func ensureRunning() async throws {
        await state.reapIfIdle(maxIdleSeconds: Self.idleTTLSeconds)
        await reclaimForeignListenerIfNeeded()

        if try await isOwnedAndHealthy() {
            await state.touchActivity()
            return
        }

        if await state.claimSpawn() {
            do {
                let launched = try await launchServe()
                await state.attachLaunchedServe(launched)
            } catch let error as OpenCodeServeCoordinatorError {
                await state.recordSpawnFailure(error)
                throw error
            } catch {
                let wrapped = OpenCodeServeCoordinatorError.spawnFailed(underlyingDescription: String(describing: error))
                await state.recordSpawnFailure(wrapped)
                throw wrapped
            }
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if let failure = await state.spawnFailure() {
                throw failure
            }

            if try await isOwnedAndHealthy() {
                await state.touchActivity()
                return
            }

            if await state.shouldClearDeadChild() {
                await state.releaseSpawn()
                if await state.claimSpawn() {
                    do {
                        let launched = try await launchServe()
                        await state.attachLaunchedServe(launched)
                    } catch let error as OpenCodeServeCoordinatorError {
                        await state.recordSpawnFailure(error)
                        throw error
                    } catch {
                        let wrapped = OpenCodeServeCoordinatorError.spawnFailed(underlyingDescription: String(describing: error))
                        await state.recordSpawnFailure(wrapped)
                        throw wrapped
                    }
                }
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        let diagnostics = await state.capturedStderrTail()
        throw OpenCodeServeCoordinatorError.healthCheckTimedOut(diagnostics: diagnostics)
    }

    /// Stop the child we spawned. Safe to call when nothing is running.
    public func stop() async {
        await state.terminateChild()
    }

    private func reclaimForeignListenerIfNeeded() async {
        guard await state.currentSpawnedPID() == nil else { return }
        guard let foreignPID = portListenerPID(Self.defaultPort), foreignPID > 0 else { return }
        Self.terminateProcess(foreignPID)
        for _ in 0..<40 {
            if portListenerPID(Self.defaultPort) == nil { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func isOwnedAndHealthy() async throws -> Bool {
        guard await healthCheck() else { return false }
        guard let spawnedPID = await state.currentSpawnedPID(), spawnedPID > 0 else {
            if portListenerPID(Self.defaultPort) != nil {
                return false
            }
            return true
        }
        guard RunStore.processAlive(spawnedPID) else { return false }
        if let listenerPID = portListenerPID(Self.defaultPort), listenerPID != spawnedPID {
            return false
        }
        return true
    }

    static func terminateProcess(_ pid: Int32) {
        guard pid > 0, RunStore.processAlive(pid) else { return }
        kill(pid, SIGTERM)
        for _ in 0..<40 {
            if !RunStore.processAlive(pid) { return }
            usleep(50_000)
        }
        if RunStore.processAlive(pid) {
            kill(pid, SIGKILL)
        }
    }

    static func portListenerPID(port: Int) -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-iTCP:\(port)", "-sTCP:LISTEN", "-t", "-n", "-P"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard let first = text.split(whereSeparator: \.isNewline).first else { return nil }
        return Int32(first.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func defaultLaunchServe() async throws -> LaunchedServe {
        guard let executable = SubprocessCommandRunner.resolveExecutable(
            "opencode",
            env: ProcessInfo.processInfo.environment
        ) else {
            throw OpenCodeServeCoordinatorError.opencodeExecutableNotFound
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["serve", "--port", String(defaultPort)]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let drain = PipeDrain(stdout: stdoutPipe, stderr: stderrPipe)
        drain.start()

        do {
            try process.run()
        } catch {
            drain.stop()
            throw OpenCodeServeCoordinatorError.spawnFailed(underlyingDescription: String(describing: error))
        }

        return LaunchedServe(
            process: process,
            pid: process.processIdentifier,
            stderrDrain: drain
        )
    }
}

struct LaunchedServe: @unchecked Sendable {
    let process: Process
    let pid: Int32
    let stderrDrain: PipeDrain
}

final class PipeDrain: @unchecked Sendable {
    private let stdout: Pipe
    private let stderr: Pipe
    private let lock = NSLock()
    private var stderrTail = ""
    private var tasks: [Task<Void, Never>] = []

    init(stdout: Pipe, stderr: Pipe) {
        self.stdout = stdout
        self.stderr = stderr
    }

    func start() {
        tasks = [
            Task.detached { [stdout] in Self.drainToNull(stdout) },
            Task.detached { [weak self, stderr] in self?.drainStderr(stderr) },
        ]
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    func stderrSnapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return stderrTail
    }

    private func drainStderr(_ pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        while !Task.isCancelled {
            let data = handle.availableData
            if data.isEmpty { break }
            guard let chunk = String(data: data, encoding: .utf8) else { continue }
            lock.lock()
            stderrTail = String((stderrTail + chunk).suffix(4096))
            lock.unlock()
        }
    }

    private static func drainToNull(_ pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        while !Task.isCancelled {
            let data = handle.availableData
            if data.isEmpty { break }
        }
    }
}

actor SpawnState {
    private var process: Process?
    private var spawnedPID: Int32?
    private var spawnInProgress = false
    private var lastSpawnFailure: OpenCodeServeCoordinatorError?
    private var stderrDrain: PipeDrain?
    private var lastActivity = Date()

    func claimSpawn() -> Bool {
        guard spawnedPID == nil, !spawnInProgress, lastSpawnFailure == nil else { return false }
        spawnInProgress = true
        return true
    }

    func attachLaunchedServe(_ launched: LaunchedServe) {
        process = launched.process
        spawnedPID = launched.pid
        stderrDrain = launched.stderrDrain
        spawnInProgress = false
        lastSpawnFailure = nil
        lastActivity = Date()

        let state = self
        launched.process.terminationHandler = { _ in
            Task { await state.handleChildExit() }
        }
    }

    func recordSpawnFailure(_ error: OpenCodeServeCoordinatorError) {
        stderrDrain?.stop()
        stderrDrain = nil
        process = nil
        spawnedPID = nil
        spawnInProgress = false
        lastSpawnFailure = error
    }

    func releaseSpawn() {
        stderrDrain?.stop()
        stderrDrain = nil
        process = nil
        spawnedPID = nil
        spawnInProgress = false
    }

    func spawnFailure() -> OpenCodeServeCoordinatorError? {
        lastSpawnFailure
    }

    func currentSpawnedPID() -> Int32? {
        spawnedPID
    }

    func touchActivity() {
        lastActivity = Date()
    }

    func reapIfIdle(maxIdleSeconds: Int) {
        guard let pid = spawnedPID, pid > 0 else { return }
        guard Date().timeIntervalSince(lastActivity) >= Double(maxIdleSeconds) else { return }
        terminateChild()
    }

    func shouldClearDeadChild() -> Bool {
        guard let pid = spawnedPID, pid > 0 else { return spawnInProgress == false && spawnedPID == nil }
        return !RunStore.processAlive(pid)
    }

    func handleChildExit() {
        stderrDrain?.stop()
        stderrDrain = nil
        process = nil
        spawnedPID = nil
        spawnInProgress = false
    }

    func capturedStderrTail() -> String? {
        let tail = stderrDrain?.stderrSnapshot() ?? ""
        return tail.isEmpty ? nil : tail
    }

    func terminateChild() {
        if let process, process.isRunning {
            process.terminate()
        }
        if let pid = spawnedPID, pid > 0 {
            OpenCodeServeCoordinator.terminateProcess(pid)
        }
        handleChildExit()
    }
}
