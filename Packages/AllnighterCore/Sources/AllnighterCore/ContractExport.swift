import Foundation

/// Projects the `ContractRegistry` into the checked-in generated artifacts
/// (docs/phases/CLI_Implementation_Contract.md §Generated Artifacts).
///
/// These are *derived* — change the registry, then regenerate; never hand-edit
/// the artifacts. `alln dev export-contracts --check` fails when the on-disk
/// artifacts drift from the registry.
///
/// Projects the registry-backed JSON artifacts, the JSON-Schema files for the
/// public types, and the human markdown reference.
public enum ContractExport {
    public struct Artifact: Sendable, Equatable {
        public let filename: String   // relative to docs/generated/alln/
        public let contents: String
        public init(filename: String, contents: String) {
            self.filename = filename; self.contents = contents
        }
    }

    /// The directory (relative to the repo root) the artifacts live under.
    public static let generatedDir = "docs/generated/alln"

    /// Raised by `check`/`write` when the repo root — or the artifacts under
    /// it — can't be located. Kept distinct from content drift: a missing
    /// file/dir is never reported as `CONTRACT_DRIFT` (PO-F6).
    public enum NotFoundError: Error, Equatable {
        /// Ascending from `cwd` found neither `docs/generated/alln` nor `.git`.
        case repoRootNotFound(cwd: String)
        /// A repo root was found, but the generated dir doesn't exist there yet.
        case generatedDirMissing(path: String)
        /// The generated dir exists, but one or more artifact files are absent.
        case artifactsMissing(path: String, filenames: [String])
    }

    /// Ascend from `start` to the nearest directory containing `docs/generated/alln`
    /// or `.git` — the repo root. Returns `nil` if neither is found before the
    /// filesystem root. Shared by `check` and `write` so both resolve the same
    /// directory regardless of the process's current working directory.
    public static func findRepoRoot(from start: String) -> URL? {
        let fm = FileManager.default
        // String-based ascent: URL.deletingLastPathComponent() can produce
        // path forms that never compare equal at the filesystem root (a
        // Foundation quirk), which spins the ascent forever. NSString's
        // deletingLastPathComponent reliably converges: "/a" -> "/" -> "/".
        var path = (start as NSString).standardizingPath
        while true {
            if fm.fileExists(atPath: (path as NSString).appendingPathComponent(generatedDir)) {
                return URL(fileURLWithPath: path)
            }
            if fm.fileExists(atPath: (path as NSString).appendingPathComponent(".git")) {
                return URL(fileURLWithPath: path)
            }
            if path == "/" { return nil }
            let parent = (path as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == path { return nil }
            path = parent
        }
    }

    public enum CheckOutcome: Equatable {
        case upToDate(count: Int)
        case drifted([String])
    }

    /// `--check`: resolves the repo root from `cwd`, then compares the on-disk
    /// artifacts to the registry. Throws `NotFoundError` — never reports
    /// missing files as `.drifted` — when the root, the generated dir, or an
    /// individual artifact file can't be found.
    public static func check(from cwd: String, registry: ContractRegistry = .milestone1) throws -> CheckOutcome {
        guard let root = findRepoRoot(from: cwd) else {
            throw NotFoundError.repoRootNotFound(cwd: cwd)
        }
        let dir = root.appendingPathComponent(generatedDir)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw NotFoundError.generatedDirMissing(path: dir.path)
        }
        let expected = try artifacts(registry)
        var missing: [String] = []
        var drifted: [String] = []
        for a in expected {
            guard let onDisk = try? String(contentsOf: dir.appendingPathComponent(a.filename), encoding: .utf8) else {
                missing.append(a.filename); continue
            }
            if onDisk != a.contents { drifted.append(a.filename) }
        }
        if !missing.isEmpty {
            throw NotFoundError.artifactsMissing(path: dir.path, filenames: missing)
        }
        return drifted.isEmpty ? .upToDate(count: expected.count) : .drifted(drifted)
    }

    /// Writes the registry-derived artifacts under the repo root resolved from
    /// `cwd`. Refuses (throws `NotFoundError.repoRootNotFound`) instead of
    /// creating a stray `<cwd>/docs/generated/alln/` when no repo root is found.
    @discardableResult
    public static func write(from cwd: String, registry: ContractRegistry = .milestone1) throws -> (count: Int, path: String) {
        guard let root = findRepoRoot(from: cwd) else {
            throw NotFoundError.repoRootNotFound(cwd: cwd)
        }
        let dir = root.appendingPathComponent(generatedDir)
        let toWrite = try artifacts(registry)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for a in toWrite {
            try a.contents.write(to: dir.appendingPathComponent(a.filename), atomically: true, encoding: .utf8)
        }
        return (toWrite.count, dir.path)
    }

    public static func artifacts(_ registry: ContractRegistry = .milestone1) throws -> [Artifact] {
        [
            Artifact(filename: "alln-contract.json", contents: try jsonString(registry)),
            Artifact(filename: "error-codes.json", contents: try jsonString(registry.errors)),
            Artifact(filename: "exit-codes.json", contents: try jsonString(ExitCodeExport.rows)),
            Artifact(filename: "ndjson-events.json", contents: try jsonString(registry.events)),
            Artifact(filename: "example-recipes.json", contents: try jsonString(registry.examples)),
            Artifact(filename: "team-run.schema.json", contents: try ContractSchema.json(ContractSchema.teamRunSchema())),
            Artifact(filename: "doctor-result.schema.json", contents: try ContractSchema.json(ContractSchema.doctorResultSchema())),
            Artifact(filename: "coordinator-health.schema.json", contents: try ContractSchema.json(ContractSchema.coordinatorHealthSchema())),
            Artifact(filename: "pending-item.schema.json", contents: try ContractSchema.json(ContractSchema.pendingItemSchema())),
            Artifact(filename: "model-list.schema.json", contents: try ContractSchema.json(ContractSchema.modelListSchema())),
            Artifact(filename: "version.schema.json", contents: try ContractSchema.json(ContractSchema.versionSchema())),
            Artifact(filename: "floor-run.schema.json", contents: try ContractSchema.json(ContractSchema.floorRunSchema())),
            Artifact(filename: "spec-result.schema.json", contents: try ContractSchema.json(ContractSchema.specResultSchema())),
            Artifact(filename: "team-catalog.schema.json", contents: try ContractSchema.json(ContractSchema.teamCatalogSchema())),
            Artifact(filename: "skill-catalog.schema.json", contents: try ContractSchema.json(ContractSchema.skillCatalogSchema())),
            Artifact(filename: "history.schema.json", contents: try ContractSchema.json(ContractSchema.historySchema())),
            Artifact(filename: "thread-status.schema.json", contents: try ContractSchema.json(ContractSchema.threadStatusSchema())),
            Artifact(filename: "thread-get.schema.json", contents: try ContractSchema.json(ContractSchema.threadGetSchema())),
            Artifact(filename: "thread-attachment.schema.json", contents: try ContractSchema.json(ContractSchema.threadAttachmentSchema())),
            Artifact(filename: "ownership-ps.schema.json", contents: try ContractSchema.json(ContractSchema.ownershipPsSchema())),
            Artifact(filename: "ownership-kill.schema.json", contents: try ContractSchema.json(ContractSchema.ownershipKillSchema())),
            Artifact(filename: "help_alln_cli_spec.md", contents: ContractDocs.markdown(registry)),
        ]
    }

    /// Canonical serialization: CoreJSON (pretty + sorted keys) with a trailing
    /// newline. Export and `--check` must use this exact form so byte comparison
    /// is meaningful.
    private static func jsonString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try CoreJSON.encode(value), as: UTF8.self) + "\n"
    }
}
