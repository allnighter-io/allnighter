import Foundation
import AllnighterCore
import AgentOSCLI

/// App-side census ingest — verifies agent-discovered paths by running them
/// (`health == runs`). Uses shared `CLIDetector.probeResolved`; does not live in
/// AgentOS (census product policy stays Allnighter-owned).
public enum CensusIngest {
    /// Verify an agent-discovered census by actually RUNNING each candidate path.
    /// When the census path is upgrade-fragile (`looksEphemeral`), a stable
    /// launcher from the manifest's `knownPaths` is tried first.
    ///
    /// When no candidate path is executable in this pass, the result is still a
    /// `.notInstalled` observation from *this* pass — but `priorRecords` are
    /// applied through `ProbeRecordMerge` so a still-valid prior `.ready` is
    /// not overwritten (see that type's docs). Pass prior SetupStore records
    /// at every call site; omitting them only affects drivers with no prior.
    public static func ingest(
        _ census: ToolCensus,
        manifests: [DriverManifest],
        models: [String: String],
        now: Date,
        smoke: Bool = true,
        detector: CLIDetector,
        home: String = NSHomeDirectory(),
        commonBinDirs: [String] = CLIDetector.defaultCommonBinDirs,
        priorRecords: [ToolProbeRecord] = []
    ) async -> [ToolProbeRecord] {
        let byId = Dictionary(manifests.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let priorById = Dictionary(priorRecords.map { ($0.driverId, $0) }, uniquingKeysWith: { a, _ in a })
        var records: [ToolProbeRecord] = []
        for candidate in census.candidates(for: manifests) {
            guard let manifest = byId[candidate.driverId] else { continue }
            let stableAlt = candidate.looksEphemeral
                ? probeKnownPaths(manifest, home: home, commonBinDirs: commonBinDirs)
                : nil
            let ordered = (candidate.looksEphemeral ? [stableAlt, candidate.path] : [candidate.path])
                .compactMap { $0 }
            var chosen: ToolProbeRecord?
            for path in ordered where FileManager.default.isExecutableFile(atPath: path) {
                let rec = await detector.probeResolved(
                    manifest,
                    model: models[manifest.id] ?? "",
                    invocation: .direct(path: path),
                    now: now,
                    smoke: smoke
                )
                chosen = rec
                if rec.version != nil { break }
            }
            let passObservation = chosen ?? ToolProbeRecord(
                driverId: manifest.id,
                status: .notInstalled,
                lastProbeAt: now,
                lastDetectedAt: now
            )
            records.append(
                ProbeRecordMerge.apply(
                    incoming: passObservation,
                    prior: priorById[manifest.id]
                )
            )
        }
        return records
    }

    private static func probeKnownPaths(
        _ manifest: DriverManifest,
        home: String,
        commonBinDirs: [String]
    ) -> String? {
        let bins: [String]
        if let b = manifest.setup?.bins, !b.isEmpty { bins = b }
        else if let command = manifest.invoke?.command { bins = [command] }
        else { bins = [] }
        for dir in (manifest.setup?.knownPaths ?? []) + commonBinDirs {
            let expanded = dir.hasPrefix("~") ? home + dir.dropFirst() : dir
            for bin in bins {
                let candidate = (expanded as NSString).appendingPathComponent(bin)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir),
                      !isDir.boolValue,
                      FileManager.default.isExecutableFile(atPath: candidate) else { continue }
                return candidate
            }
        }
        return nil
    }
}

/// Factory that always pins the neutral TCC scratch CWD.
public enum AllnighterCLIDetector {
    public static func make(
        commandRunner: CommandRunner,
        resolver: ShellResolver? = nil,
        shellPath: String? = nil,
        home: String? = nil,
        detectTimeout: Duration = .seconds(8),
        smokeTimeout: Duration = .seconds(60),
        interactive: Bool = false,
        commonBinDirs: [String] = CLIDetector.defaultCommonBinDirs
    ) -> CLIDetector {
        CLIDetector(
            commandRunner: commandRunner,
            resolver: resolver,
            shellPath: shellPath,
            home: home,
            detectTimeout: detectTimeout,
            smokeTimeout: smokeTimeout,
            workingDirectory: AllnighterPaths.ensuredProbeScratchPath(),
            interactive: interactive,
            commonBinDirs: commonBinDirs
        )
    }
}
