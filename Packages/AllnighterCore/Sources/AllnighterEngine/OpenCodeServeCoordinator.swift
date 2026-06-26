import Foundation

public enum OpenCodeServeCoordinatorError: Error, Sendable {
    case opencodeExecutableNotFound
    case spawnFailed(underlying: Error)
    case healthCheckTimedOut
}

public struct OpenCodeServeCoordinator: Sendable {
    public static let defaultURL = URL(string: "http://127.0.0.1:4096")!
    public static let defaultPort = 4096

    private let healthCheck: @Sendable () async -> Bool
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
        self.healthCheck = healthCheck
        self.state = SpawnState()
    }

    public func isHealthy() async -> Bool {
        await healthCheck()
    }

    public func ensureRunning() async throws {
        if await isHealthy() { return }

        let shouldSpawn = await state.claimSpawn()
        if shouldSpawn {
            guard let executable = SubprocessCommandRunner.resolveExecutable(
                "opencode",
                env: ProcessInfo.processInfo.environment
            ) else {
                await state.releaseSpawn()
                throw OpenCodeServeCoordinatorError.opencodeExecutableNotFound
            }

            let process = Process()
            process.executableURL = executable
            process.arguments = ["serve", "--port", String(Self.defaultPort)]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                await state.releaseSpawn()
                throw OpenCodeServeCoordinatorError.spawnFailed(underlying: error)
            }
            await state.setSpawnedPID(process.processIdentifier)
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if await isHealthy() { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw OpenCodeServeCoordinatorError.healthCheckTimedOut
    }
}

private actor SpawnState {
    private var spawnedPID: Int32?

    func claimSpawn() -> Bool {
        guard spawnedPID == nil else { return false }
        spawnedPID = 0
        return true
    }

    func setSpawnedPID(_ pid: Int32) {
        spawnedPID = pid
    }

    func releaseSpawn() {
        spawnedPID = nil
    }
}