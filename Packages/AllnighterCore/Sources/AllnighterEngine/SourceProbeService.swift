import Foundation
import AllnighterCore

/// What `alln doctor` and `alln detect` ask of the source bench. This is a
/// plain in-process request: there is no wire format, no transport, and no
/// second process, so it carries only what the probe itself needs.
public struct SourceProbeRequest: Equatable, Sendable {
    public var sourceId: String?
    public var full: Bool
    public var pilot: Bool
    public var projectToken: String?
    /// Already-computed commit identity for the checkout `doctor` was invoked
    /// from. Deliberately a value rather than a path, so a diagnostic can never
    /// turn into an arbitrary filesystem read.
    public var workspaceHeadSha: String?

    public init(
        sourceId: String? = nil,
        full: Bool,
        pilot: Bool = false,
        projectToken: String? = nil,
        workspaceHeadSha: String? = nil
    ) {
        self.sourceId = sourceId
        self.full = full
        self.pilot = pilot
        self.projectToken = projectToken
        self.workspaceHeadSha = workspaceHeadSha
    }
}

/// First-run detection projection: the probe records plus the team they
/// assemble into.
public struct SourceDetectionResult: Codable, Equatable, Sendable {
    public var records: [ToolProbeRecord]
    public var assembledTeam: TeamAssembler.Assembled

    public init(records: [ToolProbeRecord], assembledTeam: TeamAssembler.Assembled) {
        self.records = records
        self.assembledTeam = assembledTeam
    }
}

/// Doctor composition and vendor smoke probing, owned by the process that asked
/// for it. Code Red deleted the resident hop this used to travel through; the
/// probe was never the reason for that hop, so it simply runs here now.
public struct SourceProbeService: Sendable {
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

    public func probe(_ request: SourceProbeRequest) async -> DoctorResult {
        _ = ExecutionLaneFlock.garbageCollectStaleLanes()
        _ = ProcessOwnershipGarbageCollector().collect()

        let manifests = request.sourceId.map { id in registry.all.filter { $0.id == id } } ?? registry.all
        let parked = SetupStore().load().parkedSet
        // Parked CLIs are skipped entirely (no detect/smoke) unless the caller named
        // that one source explicitly (doctor --agent / single-driver repair).
        let probeManifests: [DriverManifest]
        if let only = request.sourceId {
            probeManifests = manifests.filter { $0.id == only }
        } else {
            probeManifests = manifests.filter { !parked.contains($0.id) }
        }
        let allLabels = ModelCatalog.probeModelLabels(registry: registry)
        let labels = request.sourceId.map { sourceId in
            allLabels.filter { $0.key == sourceId }
        } ?? allLabels.filter { !parked.contains($0.key) }
        let records = await Self.probeRecords(manifests: probeManifests, labels: labels, full: request.full)
        // Merge parked drivers' cached records so doctor still knows they exist.
        let cached = SetupStore().load()
        var doctorRecords = records
        if request.sourceId == nil {
            for rec in cached.records where parked.contains(rec.driverId) {
                DriverProbeRecords.upsert(rec, into: &doctorRecords)
            }
        }
        let inputs = DoctorReport.Inputs(
            binaryVersion: binaryVersion,
            contractVersion: ContractRegistry.contractVersion,
            docsVersionMatchesBinary: true,
            binaryGitSha: binaryGitSha,
            workspaceHeadSha: Self.validatedWorkspaceHeadSha(request.workspaceHeadSha),
            configDirWritable: Self.ensureWritable(AllnighterPaths.config),
            runsDirWritable: Self.ensureWritable(AllnighterPaths.runs),
            pendingDirWritable: Self.ensureWritable(AllnighterPaths.pending),
            coordinator: ServeDaemonProbe().doctorCoordinator(),
            full: request.full,
            cursorCLIConfigURL: CursorShellAllowlist.defaultConfigURL,
            cursorProjectOverrideURL: nil,
            runningBinaryPath: runningBinaryPath,
            pathEnvironment: pathEnvironment,
            pilot: request.pilot ? Self.pilotContext(projectToken: request.projectToken, records: doctorRecords, models: models, full: request.full) : nil,
            teachingInputs: TeachingInstalledCheck.defaultInputs(homeDirectory: FileManager.default.homeDirectoryForCurrentUser),
            update: ReleaseChannel.checkUpdate(
                currentVersion: binaryVersion,
                binaryPath: runningBinaryPath
            )
        )
        var result = DoctorReport.build(models: models, manifests: manifests, records: doctorRecords, inputs: inputs)
        result.checks.append(LoopPersistenceDoctorCheck.doctorCheck(loopsRoot: AllnighterPaths.loops))
        if let sourceId = request.sourceId {
            let prefix = "source.\(sourceId)."
            let global = Set(["binaryVersion", "docsVersion", "configDir", "runsDir", "sources", "pilot"])
            result.checks = result.checks.filter { global.contains($0.name) || $0.name.hasPrefix(prefix) }
            result.models = result.models.filter { $0.sourceId == sourceId }
        }
        return result
    }

    public func detect() async -> SourceDetectionResult {
        let store = SetupStore()
        let previous = store.load()
        let parked = previous.parkedSet
        let labels = ModelCatalog.probeModelLabels(registry: registry)
            .filter { !parked.contains($0.key) }
        let manifests = registry.all.filter { !parked.contains($0.id) }
        let fresh = await Self.probeRecords(manifests: manifests, labels: labels, full: true)
        // Keep last-known records for parked CLIs; never wipe park intent on detect.
        var records = previous.records.filter { parked.contains($0.driverId) }
        for rec in fresh {
            DriverProbeRecords.upsert(rec, into: &records)
        }
        let assembled = TeamAssembler.assemble(
            models: models,
            readyDriverIds: TeamAssembler.readyDriverIds(from: records, excludingParked: parked),
            now: Date()
        )
        _ = try? store.save(.init(
            records: records.sorted { $0.driverId < $1.driverId },
            setupCompletedAt: previous.setupCompletedAt,
            assembledTeam: assembled,
            parkedDriverIds: previous.parkedDriverIds
        ))
        return .init(records: records, assembledTeam: assembled)
    }

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
        let previous = setupStore.load()
        let parked = previous.parkedSet
        // Callers that pass a full registry still skip parked (Re-check all).
        // A single-driver repair passes one manifest — probe it even if parked so
        // Unpark → Run works without a second gesture.
        let activeManifests = manifests.count == 1
            ? manifests
            : manifests.filter { !parked.contains($0.id) }
        let activeLabels = labels.filter { key, _ in
            activeManifests.contains(where: { $0.id == key })
        }
        if full {
            // Full means a real model smoke (and can spend quota), never an
            // interactive shell or setup flow.  A routine health request must
            // report a blocked source; it must not create TCC/Automation prompts.
            let records = await AllnighterCLIDetector.make(
                commandRunner: runner, detectTimeout: .seconds(8), smokeTimeout: .seconds(60), interactive: false
            ).probeAll(activeManifests, models: activeLabels, now: Date(), smoke: true)
            let refreshed = Set(records.map(\.driverId))
            var merged = previous.records.filter { !refreshed.contains($0.driverId) }
            for rec in records {
                DriverProbeRecords.upsert(rec, into: &merged)
            }
            _ = try? setupStore.save(.init(
                records: merged.sorted { $0.driverId < $1.driverId },
                setupCompletedAt: previous.setupCompletedAt,
                assembledTeam: previous.assembledTeam,
                parkedDriverIds: previous.parkedDriverIds
            ))
            return records
        }
        let headlessIds = Set(activeManifests.filter { $0.kind == .headlessCLI }.map(\.id))
        let cached = previous.records.filter { headlessIds.contains($0.driverId) }
        if cached.count == headlessIds.count, !cached.isEmpty { return cached.sorted { $0.driverId < $1.driverId } }
        return await AllnighterCLIDetector.make(
            commandRunner: runner,
            resolver: ShellResolver(commandRunner: runner, timeout: .seconds(2), workingDirectory: AllnighterPaths.ensuredProbeScratchPath(), interactive: false),
            detectTimeout: .seconds(2), smokeTimeout: .seconds(2), interactive: false
        ).probeAll(activeManifests, models: activeLabels, now: Date(), smoke: false)
    }

    private static func pilotContext(projectToken: String?, records: [ToolProbeRecord], models: [Model], full: Bool) -> DoctorReport.PilotContext {
        let project = ProjectStore().resolveFresh(projectToken ?? ".")
        let devModelId = project.flatMap { PilotDevSeatStore().load(projectId: $0.id)?.devModelId }
        let model = devModelId.flatMap { id in models.first { $0.id == id } }
        let record = model.flatMap { model in records.first { $0.driverId == model.driverId } }
        let installed = record.map { if case .notInstalled = $0.status { return false }; return true } ?? false
        return .init(projectLabel: project.map { "\($0.displayName) (\($0.id))" }, devModelId: devModelId, devWorkerLabel: model.map { "\($0.id) (\($0.displayName))" }, driverInstalled: installed, driverReady: full ? record?.status.isSmokeReady : nil)
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
