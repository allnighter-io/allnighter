import Foundation
import AllnighterCore

/// ASR-S02c — convergent supervisor transaction.
///
/// `enable`, `disable`, `restart`, and `repair` converge through one owner that
/// reads desired state, writes the plist pointing `ProgramArguments` at the
/// canonical binary (`~/.local/share/allnighter/bin/alln`), refuses to act on an
/// unreadable desired state, verifies registration (not health) within a bounded
/// wait, and restores the prior working registration when convergence fails.
///
/// The staged-binary path and `ServeStableBinary` staging are no longer part of
/// the convergence path. All launchctl seams are injected — no test may run a
/// real `launchctl` or touch the real LaunchAgents directory.
public struct ServeLifecycle: Sendable {
    public static let label = ServeLaunchAgentStatus.label

    // MARK: - Errors

    public struct BootoutError: Error, Equatable, Sendable {
        public let terminationStatus: Int32
        public let message: String
        public init(terminationStatus: Int32, message: String) {
            self.terminationStatus = terminationStatus
            self.message = message
        }
    }

    public struct BootstrapError: Error, Equatable, Sendable {
        public let terminationStatus: Int32
        public let message: String
        public init(terminationStatus: Int32, message: String) {
            self.terminationStatus = terminationStatus
            self.message = message
        }
    }

    // MARK: - Plist shape

    public struct AgentPlist: Codable, Equatable, Sendable {
        public var label: String
        public var programArguments: [String]
        public var workingDirectory: String
        public var standardOutPath: String
        public var standardErrorPath: String
        public var runAtLoad: Bool
        public var keepAlive: KeepAliveDict
        public var throttleInterval: Int
        public var processType: String
        public var environmentVariables: EnvironmentDict

        public struct KeepAliveDict: Codable, Equatable, Sendable {
            public var successfulExit: Bool

            public init(successfulExit: Bool = false) {
                self.successfulExit = successfulExit
            }

            enum CodingKeys: String, CodingKey {
                case successfulExit = "SuccessfulExit"
            }
        }

        public struct EnvironmentDict: Codable, Equatable, Sendable {
            public var path: String
            public var home: String

            public init(path: String, home: String) {
                self.path = path
                self.home = home
            }

            enum CodingKeys: String, CodingKey {
                case path = "PATH"
                case home = "HOME"
            }
        }

        public init(label: String, programArguments: [String],
                    workingDirectory: String, standardOutPath: String,
                    standardErrorPath: String, runAtLoad: Bool = true,
                    keepAlive: KeepAliveDict = KeepAliveDict(),
                    throttleInterval: Int = 30, processType: String = "Background",
                    environmentVariables: EnvironmentDict) {
            self.label = label
            self.programArguments = programArguments
            self.workingDirectory = workingDirectory
            self.standardOutPath = standardOutPath
            self.standardErrorPath = standardErrorPath
            self.runAtLoad = runAtLoad
            self.keepAlive = keepAlive
            self.throttleInterval = throttleInterval
            self.processType = processType
            self.environmentVariables = environmentVariables
        }

        enum CodingKeys: String, CodingKey {
            case label = "Label"
            case programArguments = "ProgramArguments"
            case workingDirectory = "WorkingDirectory"
            case standardOutPath = "StandardOutPath"
            case standardErrorPath = "StandardErrorPath"
            case runAtLoad = "RunAtLoad"
            case keepAlive = "KeepAlive"
            case throttleInterval = "ThrottleInterval"
            case processType = "ProcessType"
            case environmentVariables = "EnvironmentVariables"
        }
    }

    // MARK: - Convergence result

    public enum ConvergenceOutcome: String, Codable, Sendable {
        case enabled
        case disabled
        case degraded
        case failed
        case missingCanonicalBinary
    }

    public struct ConvergenceResult: Codable, Equatable, Sendable {
        public var outcome: ConvergenceOutcome
        public var desiredStateReading: String
        public var canonicalBinaryPath: String
        public var plistWritten: Bool
        public var bootstrapped: Bool
        public var registryVerified: Bool
        public var detail: String
        public var migratedFrom: String?
        public var stagedBytesRemoved: Bool

        public init(outcome: ConvergenceOutcome, desiredStateReading: String,
                    canonicalBinaryPath: String, plistWritten: Bool, bootstrapped: Bool,
                    registryVerified: Bool, detail: String,
                    migratedFrom: String? = nil, stagedBytesRemoved: Bool = false) {
            self.outcome = outcome
            self.desiredStateReading = desiredStateReading
            self.canonicalBinaryPath = canonicalBinaryPath
            self.plistWritten = plistWritten
            self.bootstrapped = bootstrapped
            self.registryVerified = registryVerified
            self.detail = detail
            self.migratedFrom = migratedFrom
            self.stagedBytesRemoved = stagedBytesRemoved
        }
    }

    // MARK: - Injected dependencies

    public let plistURL: URL
    public let bootout: @Sendable (String) throws -> Void
    public let plistExists: @Sendable (URL) -> Bool
    public let removePlist: @Sendable (URL) throws -> Void
    public let writePlist: @Sendable (URL, AgentPlist) throws -> Void
    public let bootstrap: @Sendable (String) throws -> Void

    public let homeDirectory: URL
    public let canonicalBinaryURL: URL
    public let canonicalBinaryExists: @Sendable (URL) -> Bool
    public let readDesiredState: @Sendable (URL) -> ServeDesiredState.Reading
    public let writeDesiredState: @Sendable (ServeDesiredState.State, URL) -> Result<Void, ServeDesiredState.Failure>
    public let verifyJobLoaded: @Sendable (String) -> Bool
    public let sleep: @Sendable (TimeInterval) async throws -> Void
    public let clock: @Sendable () -> Date

    public let stagedBinaryURL: URL
    public let readExistingPlistProgramArgument: @Sendable (URL) -> String?
    public let stagedBytesExist: @Sendable (URL) -> Bool
    public let removeStagedBytes: @Sendable (URL) throws -> Void

    public init(
        plistURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(ServeLifecycle.label).plist"),
        bootout: (@Sendable (String) throws -> Void)? = nil,
        plistExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        removePlist: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        writePlist: (@Sendable (URL, AgentPlist) throws -> Void)? = nil,
        bootstrap: (@Sendable (String) throws -> Void)? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        canonicalBinaryURL: URL? = nil,
        canonicalBinaryExists: (@Sendable (URL) -> Bool)? = nil,
        readDesiredState: (@Sendable (URL) -> ServeDesiredState.Reading)? = nil,
        writeDesiredState: (@Sendable (ServeDesiredState.State, URL) -> Result<Void, ServeDesiredState.Failure>)? = nil,
        verifyJobLoaded: (@Sendable (String) -> Bool)? = nil,
        sleep: (@Sendable (TimeInterval) async throws -> Void)? = nil,
        clock: (@Sendable () -> Date)? = nil,
        stagedBinaryURL: URL? = nil,
        readExistingPlistProgramArgument: (@Sendable (URL) -> String?)? = nil,
        stagedBytesExist: (@Sendable (URL) -> Bool)? = nil,
        removeStagedBytes: (@Sendable (URL) throws -> Void)? = nil
    ) {
        self.plistURL = plistURL
        self.bootout = bootout ?? Self.liveBootout
        self.plistExists = plistExists
        self.removePlist = removePlist
        self.writePlist = writePlist ?? Self.liveWritePlist
        self.bootstrap = bootstrap ?? Self.liveBootstrap
        self.homeDirectory = homeDirectory
        self.canonicalBinaryURL = canonicalBinaryURL ?? CanonicalCLIInstall.canonicalBinaryURL(homeDirectory: homeDirectory)
        self.canonicalBinaryExists = canonicalBinaryExists ?? { FileManager.default.isExecutableFile(atPath: $0.path) }
        self.readDesiredState = readDesiredState ?? { ServeDesiredState.read(homeDirectory: $0) }
        self.writeDesiredState = writeDesiredState ?? { ServeDesiredState.write($0, homeDirectory: $1) }
        self.verifyJobLoaded = verifyJobLoaded ?? Self.liveVerifyJobLoaded
        self.sleep = sleep ?? { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
        self.clock = clock ?? { Date() }
        self.stagedBinaryURL = stagedBinaryURL ?? ServeStableBinary.defaultDestinationURL()
        self.readExistingPlistProgramArgument = readExistingPlistProgramArgument ?? Self.liveReadExistingPlistProgramArgument
        self.stagedBytesExist = stagedBytesExist ?? { FileManager.default.fileExists(atPath: $0.path) }
        self.removeStagedBytes = removeStagedBytes ?? { try FileManager.default.removeItem(at: $0) }
    }

    // MARK: - Four verbs

    public func enable() async -> ConvergenceResult {
        switch writeDesiredState(.enabled, homeDirectory) {
        case .failure(let f):
            return ConvergenceResult(outcome: .failed, desiredStateReading: "write-failed",
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: false, bootstrapped: false,
                                     registryVerified: false,
                                     detail: "\(Self.label) enable failed: could not write desired state: \(f.message)")
        case .success:
            return await converge()
        }
    }

    public func disable() async -> ConvergenceResult {
        switch writeDesiredState(.disabled, homeDirectory) {
        case .failure(let f):
            return ConvergenceResult(outcome: .failed, desiredStateReading: "write-failed",
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: false, bootstrapped: false,
                                     registryVerified: false,
                                     detail: "\(Self.label) disable failed: could not write desired state: \(f.message)")
        case .success:
            return await converge()
        }
    }

    public func restart() async -> ConvergenceResult {
        let reading = readDesiredState(homeDirectory)
        let readingLabel = _labelForReading(reading)

        if case .unreadable(let reason) = reading {
            return ConvergenceResult(outcome: .degraded, desiredStateReading: readingLabel,
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: false, bootstrapped: false,
                                     registryVerified: false,
                                     detail: "\(Self.label) restart refused: desired state unreadable — \(reason)")
        }

        guard reading.effectiveState == .enabled else {
            return ConvergenceResult(outcome: .degraded, desiredStateReading: readingLabel,
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: false, bootstrapped: false,
                                     registryVerified: false,
                                     detail: "\(Self.label) restart refused: desired state is not enabled")
        }

        do { try bootout(Self.label) } catch { }

        let plist = _makePlist()
        do {
            try writePlist(plistURL, plist)
        } catch {
            return ConvergenceResult(outcome: .failed, desiredStateReading: readingLabel,
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: false, bootstrapped: false,
                                     registryVerified: false,
                                     detail: "\(Self.label) restart failed: plist write: \(error)")
        }
        do {
            try bootstrap(plistURL.path)
        } catch {
            return ConvergenceResult(outcome: .failed, desiredStateReading: readingLabel,
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: true, bootstrapped: false,
                                     registryVerified: false,
                                     detail: "\(Self.label) restart failed: bootstrap: \(error)")
        }

        let verified = await _boundedVerify(expectedLoaded: true)
        return ConvergenceResult(outcome: .enabled, desiredStateReading: readingLabel,
                                 canonicalBinaryPath: canonicalBinaryURL.path,
                                 plistWritten: true, bootstrapped: true,
                                 registryVerified: verified,
                                 detail: "\(Self.label) restarted: agent \(verified ? "registered" : "unverified")")
    }

    public func repair() async -> ConvergenceResult {
        return await converge()
    }

    // MARK: - Convergence

    private func converge() async -> ConvergenceResult {
        let reading = readDesiredState(homeDirectory)
        let readingLabel = _labelForReading(reading)

        switch reading {
        case .unreadable(let reason):
            return ConvergenceResult(outcome: .degraded, desiredStateReading: readingLabel,
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: false, bootstrapped: false,
                                     registryVerified: false,
                                     detail: "\(Self.label) cannot converge: desired state unreadable — \(reason)")

        case .present(.disabled, _):
            do { try bootout(Self.label) } catch { }

            var plistRemoved = false
            if plistExists(plistURL) {
                do {
                    try removePlist(plistURL)
                    plistRemoved = true
                } catch {
                    return ConvergenceResult(outcome: .failed, desiredStateReading: readingLabel,
                                             canonicalBinaryPath: canonicalBinaryURL.path,
                                             plistWritten: false, bootstrapped: false,
                                             registryVerified: false,
                                             detail: "\(Self.label) converge disabled: plist delete failed: \(error)")
                }
            }

            let stopped = await _boundedVerify(expectedLoaded: false)
            return ConvergenceResult(outcome: .disabled, desiredStateReading: readingLabel,
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: false, bootstrapped: false,
                                     registryVerified: stopped,
                                     detail: "\(Self.label) disabled: bootout settled, plist \(plistRemoved ? "removed" : "absent"), \(stopped ? "stopped verified" : "stopped unverified")")

        case .absent:
            if !canonicalBinaryExists(canonicalBinaryURL) {
                return ConvergenceResult(outcome: .missingCanonicalBinary, desiredStateReading: readingLabel,
                                         canonicalBinaryPath: canonicalBinaryURL.path,
                                         plistWritten: false, bootstrapped: false,
                                         registryVerified: false,
                                         detail: "SERVE_INSTALL_FAILED: canonical binary not found at \(canonicalBinaryURL.path) — run `alln install-cli` first")
            }

            let priorPlistBytes: Data?
            if plistExists(plistURL) {
                priorPlistBytes = try? Data(contentsOf: plistURL)
            } else {
                priorPlistBytes = nil
            }

            if let bootoutErr = _tryBootout() {
                if let priorBytes = priorPlistBytes {
                    try? priorBytes.write(to: plistURL, options: .atomic)
                    try? bootstrap(plistURL.path)
                }
                return ConvergenceResult(outcome: .failed, desiredStateReading: readingLabel,
                                         canonicalBinaryPath: canonicalBinaryURL.path,
                                         plistWritten: false, bootstrapped: false,
                                         registryVerified: false,
                                         detail: "\(Self.label) converge enabled: bootout failed — prior registration restored: \(bootoutErr.message)")
            }

            let absentPlist = _makePlist()
            do {
                try writePlist(plistURL, absentPlist)
            } catch {
                if let priorBytes = priorPlistBytes {
                    try? priorBytes.write(to: plistURL, options: .atomic)
                    try? bootstrap(plistURL.path)
                }
                return ConvergenceResult(outcome: .failed, desiredStateReading: readingLabel,
                                         canonicalBinaryPath: canonicalBinaryURL.path,
                                         plistWritten: false, bootstrapped: false,
                                         registryVerified: false,
                                         detail: "\(Self.label) converge enabled: plist write failed — prior registration restored: \(error)")
            }

            do {
                try bootstrap(plistURL.path)
            } catch {
                if let priorBytes = priorPlistBytes {
                    try? priorBytes.write(to: plistURL, options: .atomic)
                    try? bootstrap(plistURL.path)
                } else {
                    try? removePlist(plistURL)
                }
                return ConvergenceResult(outcome: .failed, desiredStateReading: readingLabel,
                                         canonicalBinaryPath: canonicalBinaryURL.path,
                                         plistWritten: true, bootstrapped: false,
                                         registryVerified: false,
                                         detail: "\(Self.label) converge enabled: bootstrap failed — prior registration restored: \(error)")
            }

            let absentVerified = await _boundedVerify(expectedLoaded: true)
            return ConvergenceResult(outcome: .enabled, desiredStateReading: readingLabel,
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: true, bootstrapped: true,
                                     registryVerified: absentVerified,
                                     detail: "\(Self.label) enabled (migrated from absent): agent registered at \(canonicalBinaryURL.path)")

        case .present(.enabled, _):
            guard canonicalBinaryExists(canonicalBinaryURL) else {
                return ConvergenceResult(outcome: .missingCanonicalBinary, desiredStateReading: readingLabel,
                                         canonicalBinaryPath: canonicalBinaryURL.path,
                                         plistWritten: false, bootstrapped: false,
                                         registryVerified: false,
                                         detail: "SERVE_INSTALL_FAILED: canonical binary not found at \(canonicalBinaryURL.path) — run `alln install-cli` first")
            }

            let priorPlistBytes: Data?
            if plistExists(plistURL) {
                priorPlistBytes = try? Data(contentsOf: plistURL)
            } else {
                priorPlistBytes = nil
            }

            let needsMigration: Bool = {
                if !plistExists(plistURL) { return false }
                guard let prog = readExistingPlistProgramArgument(plistURL) else { return false }
                let resolved = URL(fileURLWithPath: prog).resolvingSymlinksInPath().standardizedFileURL.path
                let stagedResolved = stagedBinaryURL.resolvingSymlinksInPath().standardizedFileURL.path
                return resolved == stagedResolved
            }()

            if needsMigration {
                return await _migrateFromStaged(readingLabel: readingLabel, priorPlistBytes: priorPlistBytes)
            }

            if let bootoutErr = _tryBootout() {
                if let priorBytes = priorPlistBytes {
                    try? priorBytes.write(to: plistURL, options: .atomic)
                    try? bootstrap(plistURL.path)
                }
                return ConvergenceResult(outcome: .failed, desiredStateReading: readingLabel,
                                         canonicalBinaryPath: canonicalBinaryURL.path,
                                         plistWritten: false, bootstrapped: false,
                                         registryVerified: false,
                                         detail: "\(Self.label) converge enabled: bootout failed — prior registration restored: \(bootoutErr.message)")
            }

            let plist = _makePlist()
            do {
                try writePlist(plistURL, plist)
            } catch {
                if let priorBytes = priorPlistBytes {
                    try? priorBytes.write(to: plistURL, options: .atomic)
                    try? bootstrap(plistURL.path)
                }
                return ConvergenceResult(outcome: .failed, desiredStateReading: readingLabel,
                                         canonicalBinaryPath: canonicalBinaryURL.path,
                                         plistWritten: false, bootstrapped: false,
                                         registryVerified: false,
                                         detail: "\(Self.label) converge enabled: plist write failed — prior registration restored: \(error)")
            }

            do {
                try bootstrap(plistURL.path)
            } catch {
                if let priorBytes = priorPlistBytes {
                    try? priorBytes.write(to: plistURL, options: .atomic)
                    try? bootstrap(plistURL.path)
                } else {
                    try? removePlist(plistURL)
                }
                return ConvergenceResult(outcome: .failed, desiredStateReading: readingLabel,
                                         canonicalBinaryPath: canonicalBinaryURL.path,
                                         plistWritten: true, bootstrapped: false,
                                         registryVerified: false,
                                         detail: "\(Self.label) converge enabled: bootstrap failed — prior registration restored: \(error)")
            }

            let verified = await _boundedVerify(expectedLoaded: true)
            return ConvergenceResult(outcome: .enabled, desiredStateReading: readingLabel,
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: true, bootstrapped: true,
                                     registryVerified: verified,
                                     detail: "\(Self.label) enabled: agent registered at \(canonicalBinaryURL.path)")
        }
    }

    /// Step 2 ordered migration: bootout → write canonical plist → bootstrap →
    /// verify → remove staged bytes. On any failure before removal, restore the
    /// prior plist, re-bootstrap the prior job, and leave staged bytes untouched.
    private func _migrateFromStaged(readingLabel: String, priorPlistBytes: Data?) async -> ConvergenceResult {
        let stagedPath = stagedBinaryURL.path

        if let bootoutErr = _tryBootout() {
            if let priorBytes = priorPlistBytes {
                try? priorBytes.write(to: plistURL, options: .atomic)
                try? bootstrap(plistURL.path)
            }
            return ConvergenceResult(outcome: .failed, desiredStateReading: readingLabel,
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: false, bootstrapped: false,
                                     registryVerified: false,
                                     detail: "\(Self.label) migration failed: bootout error — prior registration restored: \(bootoutErr.message)")
        }

        let plist = _makePlist()
        do {
            try writePlist(plistURL, plist)
        } catch {
            if let priorBytes = priorPlistBytes {
                try? priorBytes.write(to: plistURL, options: .atomic)
                try? bootstrap(plistURL.path)
            }
            return ConvergenceResult(outcome: .failed, desiredStateReading: readingLabel,
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: false, bootstrapped: false,
                                     registryVerified: false,
                                     detail: "\(Self.label) migration failed: plist write — prior registration restored: \(error)")
        }

        do {
            try bootstrap(plistURL.path)
        } catch {
            if let priorBytes = priorPlistBytes {
                try? priorBytes.write(to: plistURL, options: .atomic)
                try? bootstrap(plistURL.path)
            } else {
                try? removePlist(plistURL)
            }
            return ConvergenceResult(outcome: .failed, desiredStateReading: readingLabel,
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: true, bootstrapped: false,
                                     registryVerified: false,
                                     detail: "\(Self.label) migration failed: bootstrap — prior registration restored: \(error)")
        }

        let verified = await _boundedVerify(expectedLoaded: true)
        guard verified else {
            if let priorBytes = priorPlistBytes {
                try? priorBytes.write(to: plistURL, options: .atomic)
                try? bootstrap(plistURL.path)
            }
            return ConvergenceResult(outcome: .failed, desiredStateReading: readingLabel,
                                     canonicalBinaryPath: canonicalBinaryURL.path,
                                     plistWritten: true, bootstrapped: true,
                                     registryVerified: false,
                                     detail: "\(Self.label) migration failed: verify — prior registration restored")
        }

        var removed = false
        if stagedBytesExist(stagedBinaryURL) {
            do {
                try removeStagedBytes(stagedBinaryURL)
                removed = true
            } catch {
                // staged removal failure is non-fatal after successful migration
            }
        }

        let suffix = removed ? "staged bytes cleaned" : "staged bytes left on disk"
        return ConvergenceResult(outcome: .enabled, desiredStateReading: readingLabel,
                                 canonicalBinaryPath: canonicalBinaryURL.path,
                                 plistWritten: true, bootstrapped: true,
                                 registryVerified: verified, detail: "\(Self.label) migrated from \(stagedPath) to \(canonicalBinaryURL.path) — \(suffix)",
                                 migratedFrom: stagedPath, stagedBytesRemoved: removed)
    }

    /// Attempt bootout; returns nil on success/not-loaded, or a BootoutError
    /// on a genuine failure.
    private func _tryBootout() -> BootoutError? {
        do {
            try bootout(Self.label)
            return nil
        } catch let e as BootoutError {
            return e
        } catch {
            return BootoutError(terminationStatus: -1, message: "\(error)")
        }
    }

    // MARK: - Helpers

    private func _labelForReading(_ reading: ServeDesiredState.Reading) -> String {
        switch reading {
        case .absent: return "absent"
        case .present(let state, _): return "present(\(state.rawValue))"
        case .unreadable: return "unreadable"
        }
    }

    private func _makePlist() -> AgentPlist {
        let logDir = Self.defaultLogDirectory()
        let binDir = canonicalBinaryURL.deletingLastPathComponent().path
        return AgentPlist(
            label: Self.label,
            programArguments: [canonicalBinaryURL.path, "serve"],
            workingDirectory: AllnighterPaths.probeScratch.path,
            standardOutPath: logDir.appendingPathComponent("alln-serve-stdout.log").path,
            standardErrorPath: logDir.appendingPathComponent("alln-serve-stderr.log").path,
            environmentVariables: AgentPlist.EnvironmentDict(
                path: "\(binDir):/usr/bin:/bin:/usr/sbin:/sbin",
                home: homeDirectory.path
            )
        )
    }

    private func _boundedVerify(expectedLoaded: Bool, timeout: TimeInterval = 10) async -> Bool {
        let deadline = clock().addingTimeInterval(timeout)
        while clock() < deadline {
            if verifyJobLoaded(Self.label) == expectedLoaded {
                return true
            }
            do { try await sleep(0.1) } catch { break }
        }
        return verifyJobLoaded(Self.label) == expectedLoaded
    }

    // MARK: - Default log directory

    public static func defaultLogDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Allnighter", isDirectory: true)
    }

    // MARK: - Live launchctl (never called from unit tests)

    public static func liveBootout(label: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        let pipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return }
        let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = message.lowercased()
        if lower.contains("could not find service") || lower.contains("not loaded") || lower.contains("no such process") {
            return
        }
        throw BootoutError(terminationStatus: process.terminationStatus, message: message)
    }

    private static func liveWritePlist(url: URL, plist: AgentPlist) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(plist)
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: plist.workingDirectory),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: plist.standardOutPath).deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func liveBootstrap(plistPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootstrap", "gui/\(getuid())", plistPath]
        let pipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return }
        let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw BootstrapError(terminationStatus: process.terminationStatus, message: message)
    }

    private static func liveVerifyJobLoaded(label: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func liveReadExistingPlistProgramArgument(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        guard let args = plist["ProgramArguments"] as? [String], let first = args.first else { return nil }
        return first
    }
}
