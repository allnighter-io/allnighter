import Foundation

/// Product-owned **removal** of the unsupported CODE_RED LaunchAgent
/// (`com.allnighter.resident-coordinator`) — SC-S01, docs/phases/Serve_Continuity.md
/// §3.2/§4. The hand-dropped KeepAlive plist predates lifecycle ownership and
/// thrashes (spawn scheduled / EX_CONFIG 78 / LWCR) instead of supervising;
/// `remove` boots the label out of launchd and deletes the plist.
///
/// SC-S04b adds product-owned **enable/disable**: `enable` writes a
/// product-owned LaunchAgent plist aimed at the **staged stable binary**
/// (`ServeStableBinary` destination — never the `~/.local/bin` adhoc debug
/// symlink), booting out any leftover CODE_RED registration first;
/// `disable` is removal (bootout + plist delete), leaving no orphan. Enable
/// is explicit opt-in. Callers observe with `ServeLaunchAgentStatus`
/// (SC-S00); `remove`/`repair` stay for orphan cleanup.
public struct ServeLifecycle: Sendable {
    public static let label = ServeLaunchAgentStatus.label

    public enum RemovalOutcome: String, Codable, Sendable {
        /// Bootout settled (or the job was not loaded) and the plist is gone.
        case removed
        /// Nothing was installed — no-op success.
        case absent
        /// Bootout or plist deletion failed; the orphan may still be live.
        case failed
    }

    public struct RemovalResult: Codable, Equatable, Sendable {
        public var outcome: RemovalOutcome
        public var bootoutAttempted: Bool
        public var plistDeleted: Bool
        public var detail: String

        public init(outcome: RemovalOutcome, bootoutAttempted: Bool, plistDeleted: Bool, detail: String) {
            self.outcome = outcome
            self.bootoutAttempted = bootoutAttempted
            self.plistDeleted = plistDeleted
            self.detail = detail
        }
    }

    /// `launchctl bootout` failed for a reason other than "not loaded".
    public struct BootoutError: Error, Equatable, Sendable {
        public let terminationStatus: Int32
        public let message: String
        public init(terminationStatus: Int32, message: String) {
            self.terminationStatus = terminationStatus
            self.message = message
        }
    }

    /// `launchctl bootstrap` refused the plist.
    public struct BootstrapError: Error, Equatable, Sendable {
        public let terminationStatus: Int32
        public let message: String
        public init(terminationStatus: Int32, message: String) {
            self.terminationStatus = terminationStatus
            self.message = message
        }
    }

    // MARK: - SC-S04b enable / disable

    /// The product-owned LaunchAgent plist shape (SC-S04b, ASR-S02b canonical).
    /// Keys match launchd's expected plist keys via the coding keys.
    /// KeepAlive is a dictionary (`{ SuccessfulExit = false }`), never a bare
    /// `Bool` — a deliberate exit 0 stands down instead of respawning forever.
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

    public enum EnableOutcome: String, Codable, Sendable {
        /// Staged binary present, plist written, agent bootstrapped.
        case enabled
        /// Staging, bootout, plist write, or bootstrap failed; the agent is
        /// not supervised (a partially written plist may still be on disk).
        case failed
    }

    public struct EnableResult: Codable, Equatable, Sendable {
        public var outcome: EnableOutcome
        public var stagedBinaryPath: String
        public var stagedBytesReplaced: Bool
        public var plistWritten: Bool
        public var bootstrapped: Bool
        public var detail: String

        public init(outcome: EnableOutcome, stagedBinaryPath: String, stagedBytesReplaced: Bool,
                    plistWritten: Bool, bootstrapped: Bool, detail: String) {
            self.outcome = outcome
            self.stagedBinaryPath = stagedBinaryPath
            self.stagedBytesReplaced = stagedBytesReplaced
            self.plistWritten = plistWritten
            self.bootstrapped = bootstrapped
            self.detail = detail
        }
    }

    public let plistURL: URL
    /// Boots the label out of `gui/<uid>`. "Not loaded / no such service" is
    /// success for removal; any other failure throws. Injectable — unit tests
    /// must never run a live bootout against the host.
    public let bootout: @Sendable (String) throws -> Void
    public let plistExists: @Sendable (URL) -> Bool
    public let removePlist: @Sendable (URL) throws -> Void

    /// Where the stable copy lives (SC-S04a destination). The agent's
    /// `ProgramArguments` always points here — never at the `~/.local/bin`
    /// adhoc debug symlink.
    public let stagedBinaryURL: URL
    /// The running executable to stage from when no staged copy exists yet.
    public let currentExecutableURL: URL
    public let stagedBinaryExists: @Sendable (URL) -> Bool
    /// `(source, destination) -> staging result`; default is
    /// `ServeStableBinary.stage`. Injectable for tests.
    public let stage: @Sendable (URL, URL) -> Result<ServeStableBinary.StagingResult, ServeStableBinary.Failure>
    /// Writes the agent plist (creating the LaunchAgents directory).
    /// Injectable — unit tests capture the plist instead of touching the host.
    public let writePlist: @Sendable (URL, AgentPlist) throws -> Void
    /// `launchctl bootstrap gui/<uid> <plist-path>`. Injectable — unit tests
    /// must never run a live bootstrap against the host.
    public let bootstrap: @Sendable (String) throws -> Void

    public init(
        plistURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(ServeLifecycle.label).plist"),
        bootout: (@Sendable (String) throws -> Void)? = nil,
        plistExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        removePlist: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        stagedBinaryURL: URL = ServeStableBinary.defaultDestinationURL(),
        currentExecutableURL: URL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "alln"),
        stagedBinaryExists: @escaping @Sendable (URL) -> Bool = {
            FileManager.default.isExecutableFile(atPath: $0.path)
        },
        stage: @escaping @Sendable (URL, URL) -> Result<ServeStableBinary.StagingResult, ServeStableBinary.Failure> = {
            ServeStableBinary.stage(from: $0, to: $1)
        },
        writePlist: (@Sendable (URL, AgentPlist) throws -> Void)? = nil,
        bootstrap: (@Sendable (String) throws -> Void)? = nil
    ) {
        self.plistURL = plistURL
        self.bootout = bootout ?? Self.liveBootout
        self.plistExists = plistExists
        self.removePlist = removePlist
        self.stagedBinaryURL = stagedBinaryURL
        self.currentExecutableURL = currentExecutableURL
        self.stagedBinaryExists = stagedBinaryExists
        self.stage = stage
        self.writePlist = writePlist ?? Self.liveWritePlist
        self.bootstrap = bootstrap ?? Self.liveBootstrap
    }

    /// Full `alln serve repair` orchestration, testable with fixtures: absent
    /// observation is a no-op success (no bootout, no delete); anything else —
    /// wedged, running, or an orphan plist that will not print — is removed.
    public func repair(observation: ServeLaunchAgentStatus.Observation) -> RepairReport {
        guard observation.state != .absent else {
            return RepairReport(outcome: .absent, observedState: observation.state,
                                observedDetail: observation.detail, removal: nil)
        }
        let removal = remove()
        return RepairReport(outcome: removal.outcome, observedState: observation.state,
                            observedDetail: observation.detail, removal: removal)
    }

    public struct RepairReport: Codable, Equatable, Sendable {
        public var outcome: RemovalOutcome
        public var observedState: ServeLaunchAgentStatus.State
        public var observedDetail: String
        /// Nil when the observation was absent (no-op) — nothing was attempted.
        public var removal: RemovalResult?

        public init(outcome: RemovalOutcome, observedState: ServeLaunchAgentStatus.State,
                    observedDetail: String, removal: RemovalResult?) {
            self.outcome = outcome
            self.observedState = observedState
            self.observedDetail = observedDetail
            self.removal = removal
        }
    }

    /// `alln serve enable` (SC-S04b, opt-in): ensure the staged stable binary
    /// exists (staging from the running executable when missing), boot out any
    /// leftover CODE_RED registration, write the product plist with
    /// `ProgramArguments = [stagedPath, "serve"]`, and bootstrap it into
    /// `gui/<uid>`. Structured outcome; a real staging/bootout/write/bootstrap
    /// failure reads `failed`, never `enabled`.
    public func enable() -> EnableResult {
        // The login helper must never supervise the adhoc debug symlink — its
        // cdhash changes every rebuild and is exactly the CODE_RED landmine.
        guard !stagedBinaryURL.path.contains("/.local/bin/") else {
            return EnableResult(outcome: .failed, stagedBinaryPath: stagedBinaryURL.path,
                                stagedBytesReplaced: false, plistWritten: false, bootstrapped: false,
                                detail: "refusing to supervise the debug symlink path \(stagedBinaryURL.path) — staged binary must live under Application Support")
        }
        var stagedPath = stagedBinaryURL.path
        var bytesReplaced = false
        if !stagedBinaryExists(stagedBinaryURL) {
            switch stage(currentExecutableURL, stagedBinaryURL) {
            case .failure(let failure):
                return EnableResult(outcome: .failed, stagedBinaryPath: stagedPath,
                                    stagedBytesReplaced: false, plistWritten: false, bootstrapped: false,
                                    detail: "\(Self.label) enable failed: could not stage stable binary: \(failure)")
            case .success(let staging):
                stagedPath = staging.url.path
                bytesReplaced = staging.bytesWereReplaced
            }
        }
        // Migrate/replace any leftover CODE_RED registration for this label
        // before writing the product plist — never leave two registrations.
        do {
            try bootout(Self.label)
        } catch {
            return EnableResult(outcome: .failed, stagedBinaryPath: stagedPath,
                                stagedBytesReplaced: bytesReplaced, plistWritten: false, bootstrapped: false,
                                detail: "\(Self.label) enable failed: bootout of prior registration failed: \(error)")
        }
        let logDir = Self.defaultLogDirectory()
        let stagedDir = URL(fileURLWithPath: stagedPath).deletingLastPathComponent().path
        let plist = AgentPlist(label: Self.label, programArguments: [stagedPath, "serve"],
                               workingDirectory: AllnighterPaths.probeScratch.path,
                               standardOutPath: logDir.appendingPathComponent("alln-serve-stdout.log").path,
                               standardErrorPath: logDir.appendingPathComponent("alln-serve-stderr.log").path,
                               environmentVariables: AgentPlist.EnvironmentDict(
                                    path: "\(stagedDir):/usr/bin:/bin:/usr/sbin:/sbin",
                                    home: FileManager.default.homeDirectoryForCurrentUser.path))
        do {
            try writePlist(plistURL, plist)
        } catch {
            return EnableResult(outcome: .failed, stagedBinaryPath: stagedPath,
                                stagedBytesReplaced: bytesReplaced, plistWritten: false, bootstrapped: false,
                                detail: "\(Self.label) enable failed: plist write failed: \(error)")
        }
        do {
            try bootstrap(plistURL.path)
        } catch {
            return EnableResult(outcome: .failed, stagedBinaryPath: stagedPath,
                                stagedBytesReplaced: bytesReplaced, plistWritten: true, bootstrapped: false,
                                detail: "\(Self.label) enable failed: bootstrap failed: \(error)")
        }
        return EnableResult(outcome: .enabled, stagedBinaryPath: stagedPath,
                            stagedBytesReplaced: bytesReplaced, plistWritten: true, bootstrapped: true,
                            detail: "\(Self.label) enabled: LaunchAgent runs staged binary \(stagedPath) serve")
    }

    /// `alln serve disable` (SC-S04b): boot out the agent and delete the
    /// plist — plain removal, leaving no orphan. Reuses `remove()`.
    public func disable() -> RemovalResult {
        remove()
    }

    // MARK: - SC-S02 install-cli refresh

    public enum RefreshOutcome: String, Codable, Sendable {
        case refreshed
        case refreshedAndRebound
        case failed
    }

    public struct RefreshResult: Codable, Equatable, Sendable {
        public var outcome: RefreshOutcome
        public var staged: Bool
        public var bytesReplaced: Bool
        public var rebound: Bool
        public var detail: String

        public init(outcome: RefreshOutcome, staged: Bool, bytesReplaced: Bool,
                    rebound: Bool, detail: String) {
            self.outcome = outcome
            self.staged = staged
            self.bytesReplaced = bytesReplaced
            self.rebound = rebound
            self.detail = detail
        }
    }

    /// SC-S02 — called after `install-cli` succeeds: always stages the current
    /// executable to the stable binary path (even if a prior copy exists). If a
    /// product LaunchAgent plist is already installed (opt-in), rebinds it
    /// (bootout + rewrite ProgramArguments=[stagedPath,"serve"] + bootstrap) so
    /// KeepAlive starts the fresh image. If no plist is present, no agent is
    /// created — opt-in stays opt-in. Refuses `/.local/bin/`.
    public func refreshAfterInstall() -> RefreshResult {
        guard !stagedBinaryURL.path.contains("/.local/bin/") else {
            return RefreshResult(outcome: .failed, staged: false, bytesReplaced: false,
                                 rebound: false,
                                 detail: "\(Self.label) refresh refused: staged path \(stagedBinaryURL.path) is under /.local/bin/")
        }
        let staging: ServeStableBinary.StagingResult
        switch stage(currentExecutableURL, stagedBinaryURL) {
        case .failure(let failure):
            return RefreshResult(outcome: .failed, staged: false, bytesReplaced: false,
                                 rebound: false,
                                 detail: "\(Self.label) refresh failed: could not stage stable binary: \(failure)")
        case .success(let result):
            staging = result
        }
        guard plistExists(plistURL) else {
            return RefreshResult(outcome: .refreshed, staged: true,
                                 bytesReplaced: staging.bytesWereReplaced,
                                 rebound: false,
                                 detail: "\(Self.label) staged binary refreshed; no LaunchAgent installed — nothing to rebind")
        }
        do {
            try bootout(Self.label)
        } catch {
            return RefreshResult(outcome: .failed, staged: true,
                                 bytesReplaced: staging.bytesWereReplaced,
                                 rebound: false,
                                 detail: "\(Self.label) refresh failed: bootout of prior registration failed: \(error)")
        }
        let logDir2 = Self.defaultLogDirectory()
        let stagedDir2 = staging.url.deletingLastPathComponent().path
        let plist = AgentPlist(label: Self.label, programArguments: [staging.url.path, "serve"],
                               workingDirectory: AllnighterPaths.probeScratch.path,
                               standardOutPath: logDir2.appendingPathComponent("alln-serve-stdout.log").path,
                               standardErrorPath: logDir2.appendingPathComponent("alln-serve-stderr.log").path,
                               environmentVariables: AgentPlist.EnvironmentDict(
                                    path: "\(stagedDir2):/usr/bin:/bin:/usr/sbin:/sbin",
                                    home: FileManager.default.homeDirectoryForCurrentUser.path))
        do {
            try writePlist(plistURL, plist)
        } catch {
            return RefreshResult(outcome: .failed, staged: true,
                                 bytesReplaced: staging.bytesWereReplaced,
                                 rebound: false,
                                 detail: "\(Self.label) refresh failed: plist rewrite failed: \(error)")
        }
        do {
            try bootstrap(plistURL.path)
        } catch {
            return RefreshResult(outcome: .failed, staged: true,
                                 bytesReplaced: staging.bytesWereReplaced,
                                 rebound: false,
                                 detail: "\(Self.label) refresh failed: bootstrap failed: \(error)")
        }
        return RefreshResult(outcome: .refreshedAndRebound, staged: true,
                             bytesReplaced: staging.bytesWereReplaced, rebound: true,
                             detail: "\(Self.label) staged binary refreshed and LaunchAgent rebound to \(staging.url.path)")
    }

    /// Boot out the label (ignoring not-loaded) and delete the plist if one is
    /// installed. Structured outcome; never fakes success — a real bootout or
    /// delete failure reads `failed`, not `removed`.
    public func remove() -> RemovalResult {
        var bootoutFailure: String?
        do {
            try bootout(Self.label)
        } catch {
            bootoutFailure = "\(error)"
        }
        var plistDeleted = false
        var deleteFailure: String?
        if plistExists(plistURL) {
            do {
                try removePlist(plistURL)
                plistDeleted = true
            } catch {
                deleteFailure = "\(error)"
            }
        }
        if let bootoutFailure {
            return RemovalResult(outcome: .failed, bootoutAttempted: true, plistDeleted: plistDeleted,
                                 detail: "\(Self.label) bootout failed: \(bootoutFailure)")
        }
        if let deleteFailure {
            return RemovalResult(outcome: .failed, bootoutAttempted: true, plistDeleted: false,
                                 detail: "\(Self.label) plist delete failed: \(deleteFailure)")
        }
        let plistNote = plistDeleted ? "plist deleted" : "no plist installed"
        return RemovalResult(outcome: .removed, bootoutAttempted: true, plistDeleted: plistDeleted,
                             detail: "\(Self.label) removed: bootout settled, \(plistNote)")
    }

    /// Live `launchctl bootout gui/<uid>/<label>`. Never called from unit
    /// tests — tests inject `bootout` fixtures. "Could not find service" /
    /// "not loaded" means there was nothing to boot out: success for removal.
    private static func liveBootout(label: String) throws {
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

    /// Live plist writer: XML property list, required directories created
    /// first (ASR-S02b: launchd fails the spawn when WorkingDirectory is
    /// missing), atomic write. Never called from unit tests — tests inject
    /// `writePlist`.
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

    /// Default log directory: `~/Library/Logs/Allnighter/`
    public static func defaultLogDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Allnighter", isDirectory: true)
    }

    /// Live `launchctl bootstrap gui/<uid> <plist-path>`. Never called from
    /// unit tests — tests inject `bootstrap` fixtures.
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
}
