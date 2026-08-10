import AgentOSCLI
import Foundation

/// Machine + human projection for `alln detect` / `alln detect --json`.
/// Agents get disease + fixCommand without needing the Mac app.
public struct DetectJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var sources: [Source]
    public var benchTally: MenuJSON.BenchTallyPayload
    public var nextActions: [AgentSurfaceNextAction]
    public var assembledTeam: Assembled

    public struct Source: Codable, Sendable, Equatable {
        public var driverId: String
        public var displayName: String
        public var status: String
        public var version: String?
        public var path: String?
        public var detail: String?
        public var fixCommand: String?
    }

    public struct Assembled: Codable, Sendable, Equatable {
        public var readyModelCount: Int
        public var planWriterModelId: String?
    }

    public init(
        schemaVersion: Int = 1,
        contractVersion: String = ContractRegistry.contractVersion,
        sources: [Source],
        benchTally: MenuJSON.BenchTallyPayload,
        nextActions: [AgentSurfaceNextAction],
        assembledTeam: Assembled
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.sources = sources
        self.benchTally = benchTally
        self.nextActions = nextActions
        self.assembledTeam = assembledTeam
    }
}

public enum DetectReport {
    public static func build(
        records: [ToolProbeRecord],
        registry: DriverRegistry,
        assembled: TeamAssembler.Assembled,
        parked: Set<String> = []
    ) -> DetectJSON {
        let tally = BenchTallyProjector.tally(registry: registry, records: records, parked: parked)
        var sources: [DetectJSON.Source] = []
        var nextActions: [AgentSurfaceNextAction] = []
        var seenKeys = Set<String>()

        for r in records.sorted(by: { $0.driverId < $1.driverId }) {
            let manifest = registry.manifest(id: r.driverId)
            let recovery = SetupRecoveryCopy.recovery(for: r, manifest: manifest)
            sources.append(
                .init(
                    driverId: r.driverId,
                    displayName: manifest?.displayName ?? r.driverId,
                    status: recovery.statusKind,
                    version: r.version,
                    path: r.invocation?.resolvedPath,
                    detail: recovery.detail,
                    fixCommand: recovery.fixCommand
                )
            )
            if let next = recovery.nextAction,
               seenKeys.insert("\(next.kind)\u{1F}\(next.command)").inserted {
                nextActions.append(next)
            }
        }

        if nextActions.isEmpty, tally.headline == .neverScanned {
            nextActions = [
                AgentSurfaceNextAction(
                    kind: "detectCLIs",
                    label: "Find CLIs on this Mac",
                    command: BenchTallyProjector.detectCommand
                )
            ]
        } else if nextActions.isEmpty,
                  tally.headline == .partial
                    || tally.headline == .noneReady
                    || tally.needsStep > 0
                    || tally.notInstalled > 0 {
            nextActions = [
                AgentSurfaceNextAction(
                    kind: "runDoctorFull",
                    label: "Diagnose CLI setup",
                    command: "alln doctor --full --json"
                )
            ]
        }

        return DetectJSON(
            sources: sources,
            benchTally: MenuJSON.BenchTallyPayload(tally: tally),
            nextActions: Array(nextActions.prefix(5)),
            assembledTeam: .init(
                readyModelCount: assembled.benchModelIds.count,
                planWriterModelId: assembled.planWriterModelId
            )
        )
    }
}
