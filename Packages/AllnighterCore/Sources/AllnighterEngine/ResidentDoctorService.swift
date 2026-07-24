import Foundation
import AllnighterCore

/// Coordinator-owned doctor composition and vendor smoke probing. Keeping this
/// service in Engine prevents a short-lived host client from becoming the
/// process owner of a source probe (and from mistaking its sandbox limits for
/// a source failure).
public struct ResidentDoctorService: Sendable {
    public var models: [Model]
    public var registry: DriverRegistry
    public var binaryVersion: String
    public var binaryGitSha: String?
    public var runningBinaryPath: String?
    public var pathEnvironment: String?

    public init(
        models: [Model],
        registry: DriverRegistry,
        binaryVersion: String,
        binaryGitSha: String? = nil,
        runningBinaryPath: String? = ProcessOwnership.currentExecutablePath(),
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"]
    ) {
        self.models = models
        self.registry = registry
        self.binaryVersion = binaryVersion
        self.binaryGitSha = binaryGitSha
        self.runningBinaryPath = runningBinaryPath
        self.pathEnvironment = pathEnvironment
    }

    public func probe(_ request: ResidentExecutionOperation.SourceProbe) async -> DoctorResult {
        _ = ExecutionLaneFlock.garbageCollectStaleLanes()
        _ = ProcessOwnershipGarbageCollector().collect()

        let manifests = request.sourceId.map { id in registry.all.filter { $0.id == id } } ?? registry.all
        let allLabels = ModelCatalog.probeModelLabels(registry: registry)
        let labels = request.sourceId.map { sourceId in
            allLabels.filter { $0.key == sourceId }
        } ?? allLabels
        let records = await Self.probeRecords(manifests: manifests, labels: labels, full: request.full)
        // A source probe has no project-scoped work. The caller may contribute
        // only an already-computed commit identity; the resident never inherits
        // or inspects its Documents-repo CWD for this diagnostic.
        let inputs = DoctorReport.Inputs(
            binaryVersion: binaryVersion,
            contractVersion: ContractRegistry.contractVersion,
            docsVersionMatchesBinary: true,
            binaryGitSha: binaryGitSha,
            workspaceHeadSha: Self.validatedWorkspaceHeadSha(request.workspaceHeadSha),
            configDirWritable: Self.ensureWritable(AllnighterPaths.config),
            runsDirWritable: Self.ensureWritable(AllnighterPaths.runs),
            pendingDirWritable: Self.ensureWritable(AllnighterPaths.pending),
            coordinator: ResidentCoordinatorProbe().doctorCoordinator(),
            full: request.full,
            cursorCLIConfigURL: CursorShellAllowlist.defaultConfigURL,
            cursorProjectOverrideURL: nil,
            runningBinaryPath: runningBinaryPath,
            pathEnvironment: pathEnvironment,
            pilot: request.pilot ? Self.pilotContext(projectToken: request.projectToken, records: records, models: models, full: request.full) : nil,
            teachingInputs: TeachingInstalledCheck.defaultInputs(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        )
        var result = DoctorReport.build(models: models, manifests: manifests, records: records, inputs: inputs)
        if let sourceId = request.sourceId {
            let prefix = "source.\(sourceId)."
            let global = Set(["binaryVersion", "docsVersion", "configDir", "runsDir", "sources", "pilot"])
            result.checks = result.checks.filter { global.contains($0.name) || $0.name.hasPrefix(prefix) }
            result.models = result.models.filter { $0.sourceId == sourceId }
        }
        return result
    }

    public func detect() async -> ResidentDetectionResult {
        let labels = ModelCatalog.probeModelLabels(registry: registry)
        let records = await Self.probeRecords(manifests: registry.all, labels: labels, full: true)
        let store = SetupStore()
        let assembled = TeamAssembler.assemble(
            models: models,
            readyDriverIds: TeamAssembler.readyDriverIds(from: records),
            now: Date()
        )
        let previous = store.load()
        _ = try? store.save(.init(
            records: records,
            setupCompletedAt: previous.setupCompletedAt,
            assembledTeam: assembled
        ))
        return .init(records: records, assembledTeam: assembled)
    }

    /// Shared by legacy timing tests. Production callers reach it only through
    /// the resident broker.
    public static func probeRecords(
        manifests: [DriverManifest],
        labels: [String: String],
        full: Bool,
        setupStore: SetupStore = SetupStore(),
        commandRunner: CommandRunner? = nil
    ) async -> [ToolProbeRecord] {
        let runner = commandRunner ?? ProcessGroupCommandRunner(
            environmentPolicy: AllnighterSpawnEnvironmentPolicy(), spawnKind: .doctorProbe
        )
        if full {
            // Full means a real model smoke (and can spend quota), never an
            // interactive shell or setup flow.  A routine health request must
            // report a blocked source; it must not create TCC/Automation prompts.
            let records = await CLIDetector(
                commandRunner: runner, detectTimeout: .seconds(8), smokeTimeout: .seconds(60), interactive: false
            ).probeAll(manifests, models: labels, now: Date(), smoke: true)
            let previous = setupStore.load()
            let refreshed = Set(records.map(\.driverId))
            let merged = previous.records.filter { !refreshed.contains($0.driverId) } + records
            _ = try? setupStore.save(.init(records: merged.sorted { $0.driverId < $1.driverId }, setupCompletedAt: previous.setupCompletedAt, assembledTeam: previous.assembledTeam))
            return records
        }
        let headlessIds = Set(manifests.filter { $0.kind == .headlessCLI }.map(\.id))
        let cached = setupStore.load().records.filter { headlessIds.contains($0.driverId) }
        if cached.count == headlessIds.count, !cached.isEmpty { return cached.sorted { $0.driverId < $1.driverId } }
        return await CLIDetector(
            commandRunner: runner,
            resolver: ShellResolver(commandRunner: runner, timeout: .seconds(2), interactive: false),
            detectTimeout: .seconds(2), smokeTimeout: .seconds(2), interactive: false
        ).probeAll(manifests, models: labels, now: Date(), smoke: false)
    }

    private static func pilotContext(projectToken: String?, records: [ToolProbeRecord], models: [Model], full: Bool) -> DoctorReport.PilotContext {
        let project = ProjectStore().resolveFresh(projectToken ?? ".")
        let devWorkerId = project.flatMap { PilotDevSeatStore().load(projectId: $0.id)?.devWorkerId }
        let model = devWorkerId.flatMap { id in models.first { $0.id == id } }
        let record = model.flatMap { model in records.first { $0.driverId == model.driverId } }
        let installed = record.map { if case .notInstalled = $0.status { return false }; return true } ?? false
        return .init(projectLabel: project.map { "\($0.displayName) (\($0.id))" }, devWorkerId: devWorkerId, devWorkerLabel: model.map { "\($0.id) (\($0.displayName))" }, driverInstalled: installed, driverReady: full ? record?.status.isReady : nil)
    }

    private static func ensureWritable(_ url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return FileManager.default.isWritableFile(atPath: url.path)
    }

    /// A doctor client may provide only an already-computed commit identity.
    /// Keep the validation strict so a probe request cannot turn this diagnostic
    /// field into an arbitrary path, command, or opaque workspace payload.
    private static func validatedWorkspaceHeadSha(_ value: String?) -> String? {
        guard let value,
              value.count == 40,
              value.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return value.lowercased()
    }
}
