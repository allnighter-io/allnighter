import Foundation
import AllnighterCore
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// Read-only assembly of `ServeStatusJSON.Input` from host observations (ASR-S03f2a).
/// Composes existing readers; performs no install, repair, or writes.
public struct ServeStatusGatherer: Sendable {

    public let homeDirectory: URL
    public let clock: @Sendable () -> Date
    public let readDesiredState: @Sendable () -> ServeDesiredState.Reading
    public let launchAgent: ServeLaunchAgentStatus
    public let readAuthorization: @Sendable (URL) -> ServeStatusJSON.Supervisor.Authorization
    public let healthClient: ServeHealthClient
    public let healthTimeout: TimeInterval
    public let readReceipt: @Sendable () -> ServeRuntimeReceipts.Reading
    public let daemonStore: ServeDaemonStore
    public let readCanonicalInstall: @Sendable () -> CanonicalInstallReading
    public let readRunningCodeIdentity: @Sendable (String) -> CanonicalCLIInstall.CodeIdentity?
    public let processRunner: @Sendable (String, [String]) -> (stdout: String, stderr: String, exitCode: Int32)
    public let activeObligationCount: @Sendable () -> Int
    public let converging: @Sendable () -> Bool

    public struct CanonicalInstallReading: Equatable, Sendable {
        public var path: String
        public var expectedGitSha: String?
        public var expectedCodeIdentity: CanonicalCLIInstall.CodeIdentity?

        public init(
            path: String,
            expectedGitSha: String?,
            expectedCodeIdentity: CanonicalCLIInstall.CodeIdentity?
        ) {
            self.path = path
            self.expectedGitSha = expectedGitSha
            self.expectedCodeIdentity = expectedCodeIdentity
        }
    }

    public struct Gathered: Equatable, Sendable {
        public var input: ServeStatusJSON.Input
        public var status: ServeStatusJSON

        public init(input: ServeStatusJSON.Input, status: ServeStatusJSON) {
            self.input = input
            self.status = status
        }
    }

    public init(
        homeDirectory: URL? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        readDesiredState: (@Sendable () -> ServeDesiredState.Reading)? = nil,
        launchAgent: ServeLaunchAgentStatus = ServeLaunchAgentStatus(),
        readAuthorization: (@Sendable (URL) -> ServeStatusJSON.Supervisor.Authorization)? = nil,
        healthClient: ServeHealthClient = ServeHealthClient(),
        healthTimeout: TimeInterval = 2.0,
        readReceipt: (@Sendable () -> ServeRuntimeReceipts.Reading)? = nil,
        daemonStore: ServeDaemonStore? = nil,
        readCanonicalInstall: (@Sendable () -> CanonicalInstallReading)? = nil,
        readRunningCodeIdentity: (@Sendable (String) -> CanonicalCLIInstall.CodeIdentity?)? = nil,
        processRunner: (@Sendable (String, [String]) -> (stdout: String, stderr: String, exitCode: Int32))? = nil,
        activeObligationCount: (@Sendable () -> Int)? = nil,
        converging: (@Sendable () -> Bool)? = nil
    ) {
        let resolvedDaemonStore = daemonStore ?? ServeDaemonStore()
        let resolvedReceipts = ServeRuntimeReceipts(directory: resolvedDaemonStore.directory)
        let resolvedHome = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.homeDirectory = resolvedHome
        self.clock = clock
        self.readDesiredState = readDesiredState ?? {
            ServeDesiredState.read(homeDirectory: resolvedHome)
        }
        self.launchAgent = launchAgent
        self.readAuthorization = readAuthorization ?? { plistURL in
            Self.defaultAuthorization(for: plistURL)
        }
        self.healthClient = healthClient
        self.healthTimeout = healthTimeout
        self.readReceipt = readReceipt ?? {
            resolvedReceipts.read()
        }
        self.daemonStore = resolvedDaemonStore
        self.readCanonicalInstall = readCanonicalInstall ?? {
            Self.defaultCanonicalInstallReading(homeDirectory: resolvedHome)
        }
        let runner = processRunner ?? { _, _ in
            (stdout: "", stderr: "process runner not configured", exitCode: -1)
        }
        self.readRunningCodeIdentity = readRunningCodeIdentity ?? { path in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let cdhash = CanonicalCLIInstall.computeCDHash(
                candidateURL: URL(fileURLWithPath: path),
                processRunner: runner
            )
            return CanonicalCLIInstall.CodeIdentity(cdhash: cdhash, version: nil)
        }
        self.processRunner = runner
        if let activeObligationCount {
            self.activeObligationCount = activeObligationCount
        } else {
            let runsDirectory = AllnighterPaths.runs
            self.activeObligationCount = { @Sendable in
                Self.countActiveObligations(runsDirectory: runsDirectory)
            }
        }
        self.converging = converging ?? { false }
    }

    /// Gathers observations, resolves status, and returns both for inspection.
    public func gather() -> Gathered {
        let input = gatherInput()
        return Gathered(input: input, status: ServeStatusJSON.resolve(input))
    }

    // MARK: - Input assembly (one source per field)

    func gatherInput() -> ServeStatusJSON.Input {
        ServeStatusJSON.Input(
            desiredState: gatherDesiredState(),
            supervisor: gatherSupervisor(),
            binary: gatherBinary(),
            activeHealth: gatherActiveHealth(),
            receipt: readReceipt(),
            converging: converging(),
            activeObligationCount: activeObligationCount()
        )
    }

    private func gatherDesiredState() -> ServeStatusJSON.DesiredStateObservation {
        switch readDesiredState() {
        case .absent:
            return .known(.enabled)
        case .present(let state, _):
            return .known(state)
        case .unreadable(let reason):
            return .unknown(reason: reason)
        }
    }

    private func gatherSupervisor() -> ServeStatusJSON.SupervisorObservation {
        let plistPresent = launchAgent.plistExists(launchAgent.plistURL)
        let observation = launchAgent.observe()
        // `ServeLaunchAgentStatus` owns supervisor pid and lastExitCode — not the
        // durable daemon record (handshake + receipt own runtime identity).
        let loaded = Self.supervisorLoaded(plistPresent: plistPresent, observation: observation)
        let authorization: ServeStatusJSON.Supervisor.Authorization
        if plistPresent {
            authorization = readAuthorization(launchAgent.plistURL)
        } else {
            authorization = .enabled
        }
        return ServeStatusJSON.SupervisorObservation(
            kind: .launchAgent,
            label: ServeLaunchAgentStatus.label,
            plistPresent: plistPresent,
            loaded: loaded,
            authorization: authorization,
            pid: observation.pid,
            lastExitCode: observation.lastExitCode
        )
    }

    private func gatherBinary() -> ServeStatusJSON.BinaryObservation {
        let canonical = readCanonicalInstall()
        let daemonRecord = daemonStore.load()
        let runningGitSha = daemonRecord?.binaryGitSha
        let baseIdentity = readRunningCodeIdentity(canonical.path)
        let runningCodeIdentity: CanonicalCLIInstall.CodeIdentity?
        if let baseIdentity {
            runningCodeIdentity = CanonicalCLIInstall.CodeIdentity(
                cdhash: baseIdentity.cdhash,
                version: daemonRecord?.binaryVersion ?? baseIdentity.version
            )
        } else {
            runningCodeIdentity = nil
        }
        return ServeStatusJSON.BinaryObservation(
            path: canonical.path,
            expectedGitSha: canonical.expectedGitSha,
            runningGitSha: runningGitSha,
            expectedCodeIdentity: canonical.expectedCodeIdentity,
            runningCodeIdentity: runningCodeIdentity
        )
    }

    private func gatherActiveHealth() -> ServeStatusJSON.ActiveHealthObservation {
        guard let record = daemonStore.load() else {
            return .noResponse(reason: "no durable daemon record")
        }
        switch healthClient.probe(host: record.loopbackHost, port: record.loopbackPort, timeout: healthTimeout) {
        case .success(let response):
            // Handshake body only — receipt match is resolved in `ServeStatusJSON.resolve`.
            return .responded(
                daemonId: response.daemonId,
                pid: response.pid,
                respondedAt: clock()
            )
        case .failure(let failure):
            return Self.mapHealthFailure(failure)
        }
    }

    // MARK: - Defaults

    private static func supervisorLoaded(
        plistPresent: Bool,
        observation: ServeLaunchAgentStatus.Observation
    ) -> Bool? {
        guard plistPresent else { return false }
        if observation.state == .unknown,
           observation.detail.contains("launchctl print failed") {
            return nil
        }
        if observation.state == .absent {
            return false
        }
        return true
    }

    private static func mapHealthFailure(
        _ failure: ServeHealthClient.Failure
    ) -> ServeStatusJSON.ActiveHealthObservation {
        switch failure {
        case .timeout(let address):
            return .unknown(reason: "timeout at \(address)")
        case .unparseableBody(let detail), .nonLoopbackHost(let detail):
            return .unknown(reason: detail)
        case .connectionRefused(let address):
            return .noResponse(reason: "connection refused at \(address)")
        case .non200Status(let code, let address):
            return .noResponse(reason: "HTTP \(code) at \(address)")
        }
    }

    private static func defaultCanonicalInstallReading(homeDirectory: URL) -> CanonicalInstallReading {
        let path = CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: homeDirectory).path
        let identityURL = CanonicalCLIInstall.identityRecordURL(homeDirectory: homeDirectory)
        var expectedIdentity: CanonicalCLIInstall.CodeIdentity?
        if let data = try? Data(contentsOf: identityURL),
           let record = try? CoreJSON.decode(InstalledBinaryRecord.self, from: data) {
            expectedIdentity = record.identity
        }
        return CanonicalInstallReading(
            path: path,
            expectedGitSha: AllnighterBuildInfo.gitSha,
            expectedCodeIdentity: expectedIdentity
        )
    }

    private static func defaultAuthorization(for plistURL: URL) -> ServeStatusJSON.Supervisor.Authorization {
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            return .enabled
        }
        #if canImport(ServiceManagement)
        let status = SMAppService.statusForLegacyPlist(at: plistURL)
        switch status {
        case .requiresApproval:
            return .requiresApproval
        case .enabled, .notFound, .notRegistered:
            return .enabled
        @unknown default:
            return .unknown
        }
        #else
        return .unknown
        #endif
    }

    private static func countActiveObligations(runsDirectory: URL) -> Int {
        let activeRuns = RunStore(rootDirectory: runsDirectory).list().count {
            !$0.status.isTerminal && $0.blocker?.resource != .vendorBackoff
        }
        return activeRuns
    }
}

private struct InstalledBinaryRecord: Codable {
    let schemaVersion: Int
    let canonicalPath: String
    let identity: CanonicalCLIInstall.CodeIdentity
    let updatedAt: Date
}
