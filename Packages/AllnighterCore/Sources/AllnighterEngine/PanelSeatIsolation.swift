import Foundation
import AllnighterCore

/// Per-seat read-only isolation for Panel rounds (`docs/phases/Pilot_Panel.md`
/// decision 7 / PN-S06). Drivers with confirmed RO modes keep RO argv on the
/// **real** project root. Every other seat runs against an **ephemeral APFS
/// clone** (copy-on-write `cp -c -R`, plain `cp -R` fallback) under
/// `panels/<id>/clones/<seat>/` in the Allnighter support dir — a COPY, never a
/// git worktree, never any git command.
///
/// Clones exclude heavy disposable build dirs (same allowlist spirit as
/// `HandoverGate` / the project file walker) so seats read **source truth**, not
/// build artifacts. Cleanup is best-effort after each seat settles, plus a
/// sweeper on panel done / orphan reconcile.
public enum PanelSeatIsolation {
    /// How a seat is mechanically isolated for a panel round.
    public enum Mode: String, Codable, Sendable, Equatable {
        /// Confirmed driver RO mode (claude plan / codex sandbox) on the real root.
        case driverReadOnly
        /// Ephemeral project-root clone; cwd pointed at the clone.
        case clone
    }

    /// One seat's isolation plan (echoed on `panel start`; materialization is
    /// deferred until dispatch).
    public struct SeatPlan: Sendable, Equatable, Codable {
        public var workerId: String
        public var mode: Mode
        public var driverId: String?
        /// Advisory only — never a refusal. Present when mode is `.clone`.
        public var advisory: String?

        public init(workerId: String, mode: Mode, driverId: String? = nil, advisory: String? = nil) {
            self.workerId = workerId
            self.mode = mode
            self.driverId = driverId
            self.advisory = advisory
        }
    }

    /// Directory basenames excluded from clones. Case-insensitive match on the
    /// last path component. Seats read source; build/cache trees are disposable.
    public static let excludedDirectoryNames: Set<String> = [
        ".build", "node_modules", "deriveddata", "build", "dist",
        "out", ".next", "coverage", ".cache", "target", "__pycache__",
        ".pytest_cache", ".turbo", ".gradle", "bin", "obj", ".dart_tool",
        "pods", "vendor", ".gradle_cache",
    ]

    /// Stable code when clone materialization fails for a seat that needs it.
    public static let seatNotIsolatedCode = "PANEL_SEAT_NOT_ISOLATED"

    // MARK: - Planning

    /// Resolve isolation mode for one driver manifest. RO-enforcing drivers →
    /// `.driverReadOnly`; everything else → `.clone` (no seat is refused).
    public static func mode(forManifest manifest: DriverManifest?) -> Mode {
        guard let manifest, PanelReadOnlyArgs.enforce(on: manifest) != nil else {
            return .clone
        }
        return .driverReadOnly
    }

    /// Per-seat isolation plan for a roster. Unknown models still plan `.clone`
    /// (dispatch fails later with a clear seat failure if the model is missing).
    public static func plan(
        seats: [PanelSeat],
        models: [Model],
        registry: DriverRegistry
    ) -> [SeatPlan] {
        seats.map { seat in
            let modelId = PanelTeamResolver.modelId(for: seat.workerId)
            let model = models.first(where: { $0.id == modelId })
            let manifest = model.flatMap { registry.manifest(for: $0) }
            let mode = mode(forManifest: manifest)
            let driverId = manifest?.id ?? model?.driverId
            let advisory: String?
            if mode == .clone {
                let label = driverId ?? "unknown"
                advisory = "isolation: clone (driver '\(label)' has no confirmed RO mode — seat runs against an ephemeral copy of the project root)"
            } else {
                advisory = nil
            }
            return SeatPlan(
                workerId: seat.workerId,
                mode: mode,
                driverId: driverId,
                advisory: advisory
            )
        }
    }

    // MARK: - Paths

    /// `…/Panels/<panelId>/clones/` (or under an injected panels root in tests).
    public static func clonesDirectory(panelId: String, panelsRoot: URL? = nil) -> URL {
        let root = panelsRoot ?? AllnighterPaths.panels
        return root
            .appendingPathComponent(panelId, isDirectory: true)
            .appendingPathComponent("clones", isDirectory: true)
    }

    /// `…/clones/<sanitized-seat>/`
    public static func seatCloneDirectory(
        panelId: String,
        seatId: String,
        panelsRoot: URL? = nil
    ) -> URL {
        clonesDirectory(panelId: panelId, panelsRoot: panelsRoot)
            .appendingPathComponent(sanitizeSeatId(seatId), isDirectory: true)
    }

    public static func sanitizeSeatId(_ seatId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_#."))
        let mapped = seatId.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let joined = String(mapped)
        return joined.isEmpty ? "seat" : joined
    }

    // MARK: - Copier (injectable for tests)

    public enum CopyError: Error, Sendable, Equatable {
        case sourceMissing(String)
        case copyFailed(String)
    }

    /// One file/directory copy attempt. Production uses `/bin/cp`; tests inject
    /// failures to exercise the clonefile → plain fallback path.
    public struct Copier: Sendable {
        /// Prefer APFS clonefile (`cp -c`). May throw when unsupported.
        public var clonefile: @Sendable (_ source: String, _ destination: String) throws -> Void
        /// Plain recursive copy (`cp -R`) fallback.
        public var plain: @Sendable (_ source: String, _ destination: String) throws -> Void

        public init(
            clonefile: @escaping @Sendable (String, String) throws -> Void,
            plain: @escaping @Sendable (String, String) throws -> Void
        ) {
            self.clonefile = clonefile
            self.plain = plain
        }

        public static let system: Copier = Copier(
            clonefile: { src, dest in try runCp(args: ["-c", "-R", src, dest]) },
            plain: { src, dest in try runCp(args: ["-R", src, dest]) }
        )
    }

    // MARK: - Materialize / cleanup

    /// Materialize an ephemeral copy of `projectRoot` for one seat. Prefers bulk
    /// `cp -c -R` (APFS clonefile — copy-on-write, near-instant) then strips
    /// excluded disposable directories so seats read source truth, not build
    /// artifacts. Falls back to plain `cp -R` when clonefile is unsupported.
    @discardableResult
    public static func materializeClone(
        projectRoot: String,
        panelId: String,
        seatId: String,
        panelsRoot: URL? = nil,
        copier: Copier = .system
    ) throws -> URL {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: projectRoot, isDirectory: &isDir), isDir.boolValue else {
            throw CopyError.sourceMissing(projectRoot)
        }

        let dest = seatCloneDirectory(panelId: panelId, seatId: seatId, panelsRoot: panelsRoot)
        try? fm.removeItem(at: dest)
        // Parent of dest must exist; bulk `cp -c -R src dest` creates `dest` itself.
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        try copyItemPreferringClonefile(source: projectRoot, destination: dest.path, copier: copier)
        stripExcludedDirectories(at: dest)
        return dest
    }

    /// Remove any directory whose basename is on the disposable exclude list
    /// (top-level and nested — e.g. `Packages/*/.build`).
    public static func stripExcludedDirectories(at root: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return }
        var doomed: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if isExcludedDirectoryName(url.lastPathComponent) {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    doomed.append(url)
                    enumerator.skipDescendants()
                }
            }
        }
        for url in doomed {
            try? fm.removeItem(at: url)
        }
    }

    /// Best-effort delete of one seat clone directory.
    public static func removeClone(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Sweep every clone under `panels/<id>/clones/` (done + orphan reconcile).
    public static func sweepPanelClones(panelId: String, panelsRoot: URL? = nil) {
        let clones = clonesDirectory(panelId: panelId, panelsRoot: panelsRoot)
        try? FileManager.default.removeItem(at: clones)
    }

    public static func isExcludedDirectoryName(_ name: String) -> Bool {
        excludedDirectoryNames.contains(name.lowercased())
    }

    // MARK: - Tree copy

    /// Copy `source` → `destination`, preferring clonefile then plain copy.
    public static func copyItemPreferringClonefile(
        source: String,
        destination: String,
        copier: Copier
    ) throws {
        do {
            try copier.clonefile(source, destination)
        } catch {
            try copier.plain(source, destination)
        }
    }

    private static func runCp(args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        let err = Pipe()
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CopyError.copyFailed("cp launch failed: \(error)")
        }
        guard process.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw CopyError.copyFailed("cp \(args.joined(separator: " ")) failed (\(process.terminationStatus)): \(msg)")
        }
    }

    /// Agent-actionable message when clone isolation cannot be materialised.
    public static func cloneFailureMessage(workerId: String, detail: String) -> String {
        "Panel seat '\(workerId)' could not materialize clone isolation (\(seatNotIsolatedCode)): \(detail). Retry the round; if it persists, free disk space or check the project root is readable."
    }
}
