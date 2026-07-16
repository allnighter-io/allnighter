import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PN-S06: clonefile isolation — real tree untouched by a fake mutating seat,
/// excluded dirs, cleanup, and clonefile→plain fallback.
final class PanelSeatIsolationTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-panel-isol-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Fixtures

    private func makeProjectTree() throws -> URL {
        let root = tmp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "source truth".write(
            to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("docs"), withIntermediateDirectories: true
        )
        try "target v1".write(
            to: root.appendingPathComponent("docs/spec.md"), atomically: true, encoding: .utf8
        )
        // Disposable dirs that must NOT appear in the clone.
        for name in [".build", "node_modules", "DerivedData"] {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "heavy".write(to: dir.appendingPathComponent("blob.bin"), atomically: true, encoding: .utf8)
        }
        // Nested disposable (Packages/*/.build style).
        let nestedBuild = root
            .appendingPathComponent("Packages/Demo/.build", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedBuild, withIntermediateDirectories: true)
        try "nested".write(to: nestedBuild.appendingPathComponent("x"), atomically: true, encoding: .utf8)
        try "keep".write(
            to: root.appendingPathComponent("Packages/Demo/Source.swift"),
            atomically: true, encoding: .utf8
        )
        return root
    }

    private func fmCopyCopier() -> PanelSeatIsolation.Copier {
        PanelSeatIsolation.Copier(
            clonefile: { src, dest in
                try FileManager.default.copyItem(atPath: src, toPath: dest)
            },
            plain: { src, dest in
                try FileManager.default.copyItem(atPath: src, toPath: dest)
            }
        )
    }

    // MARK: - Excluded dirs

    func testCloneExcludesHeavyBuildDirectories() throws {
        let root = try makeProjectTree()
        let panelsRoot = tmp.appendingPathComponent("panels", isDirectory: true)
        let clone = try PanelSeatIsolation.materializeClone(
            projectRoot: root.path,
            panelId: "panel_ex",
            seatId: "model_cursor",
            panelsRoot: panelsRoot,
            copier: fmCopyCopier()
        )
        defer { PanelSeatIsolation.removeClone(at: clone) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: clone.appendingPathComponent("README.md").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: clone.appendingPathComponent("Packages/Demo/Source.swift").path
        ))
        for name in [".build", "node_modules", "DerivedData"] {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: clone.appendingPathComponent(name).path),
                "\(name) must be excluded from clone"
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: clone.appendingPathComponent("Packages/Demo/.build").path
            ),
            "nested .build must be excluded"
        )
        // Real tree still has them.
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".build").path))
    }

    // MARK: - Cleanup

    func testRemoveCloneAndSweepPanelClones() throws {
        let root = try makeProjectTree()
        let panelsRoot = tmp.appendingPathComponent("panels", isDirectory: true)
        let clone = try PanelSeatIsolation.materializeClone(
            projectRoot: root.path,
            panelId: "panel_sweep",
            seatId: "seat_a",
            panelsRoot: panelsRoot,
            copier: fmCopyCopier()
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: clone.path))
        PanelSeatIsolation.removeClone(at: clone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: clone.path))

        // Re-materialize then sweep the whole panel clones dir.
        _ = try PanelSeatIsolation.materializeClone(
            projectRoot: root.path,
            panelId: "panel_sweep",
            seatId: "seat_b",
            panelsRoot: panelsRoot,
            copier: fmCopyCopier()
        )
        let clonesDir = PanelSeatIsolation.clonesDirectory(panelId: "panel_sweep", panelsRoot: panelsRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clonesDir.path))
        PanelSeatIsolation.sweepPanelClones(panelId: "panel_sweep", panelsRoot: panelsRoot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: clonesDir.path))
    }

    // MARK: - Clonefile fallback

    func testClonefileFailureFallsBackToPlainCopy() throws {
        let root = try makeProjectTree()
        let panelsRoot = tmp.appendingPathComponent("panels", isDirectory: true)
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var clonefile = 0
            private var plain = 0
            func bumpClonefile() { lock.lock(); clonefile += 1; lock.unlock() }
            func bumpPlain() { lock.lock(); plain += 1; lock.unlock() }
            var clonefileCount: Int { lock.lock(); defer { lock.unlock() }; return clonefile }
            var plainCount: Int { lock.lock(); defer { lock.unlock() }; return plain }
        }
        let counter = Counter()
        let copier = PanelSeatIsolation.Copier(
            clonefile: { _, _ in
                counter.bumpClonefile()
                throw PanelSeatIsolation.CopyError.copyFailed("simulated clonefile unsupported")
            },
            plain: { src, dest in
                counter.bumpPlain()
                try FileManager.default.copyItem(atPath: src, toPath: dest)
            }
        )
        let clone = try PanelSeatIsolation.materializeClone(
            projectRoot: root.path,
            panelId: "panel_fb",
            seatId: "seat",
            panelsRoot: panelsRoot,
            copier: copier
        )
        defer { PanelSeatIsolation.removeClone(at: clone) }

        XCTAssertGreaterThan(counter.clonefileCount, 0, "clonefile path must be attempted")
        XCTAssertGreaterThan(counter.plainCount, 0, "plain copy must run after clonefile failure")
        XCTAssertTrue(FileManager.default.fileExists(atPath: clone.appendingPathComponent("README.md").path))
    }

    // MARK: - Proof of truth: real tree untouched by mutating seat

    /// Stub that mutates its working directory (write file + fake commit marker).
    private struct MutatingSeatRunner: WorkerInvoking {
        let markerName: String
        let markerBody: String

        func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
            let cwd = invocation.workingDirectory ?? ""
            let marker = URL(fileURLWithPath: cwd).appendingPathComponent(markerName)
            try? markerBody.write(to: marker, atomically: true, encoding: .utf8)
            // Would-be commit: stage a marker the seat *thinks* is a commit in its tree.
            let gitDir = URL(fileURLWithPath: cwd).appendingPathComponent(".git-would-be-commit")
            try? "would commit \(markerName)".write(to: gitDir, atomically: true, encoding: .utf8)

            let report = """
            Mutating seat ran in \(cwd)

            ```json
            {"findings":[],"noMaterialFindings":true,"reason":"probe"}
            ```
            """
            return MockWorkerInvoking.answering([report]).invoke(invocation)
        }
    }

    private func hashTree(at root: URL) throws -> String {
        var hasher = SHA256Like()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ""
        }
        var paths: [String] = []
        while let url = enumerator.nextObject() as? URL {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { continue }
            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            paths.append(rel)
        }
        for rel in paths.sorted() {
            let data = (try? Data(contentsOf: root.appendingPathComponent(rel))) ?? Data()
            hasher.feed(rel)
            hasher.feed(data)
        }
        return hasher.digestHex
    }

    func testMutatingSeatLeavesRealTreeByteIdentical() async throws {
        let root = try makeProjectTree()
        let panelsRoot = tmp.appendingPathComponent("panels", isDirectory: true)
        let before = try hashTree(at: root)

        let models = [
            Model(id: "model_cursor", displayName: "Cursor", modelLabel: "c", driverId: "cursor_agent"),
        ]
        let registry = DriverRegistry([
            DriverManifest(
                id: "cursor_agent", displayName: "Cursor", kind: .headlessCLI,
                invoke: .init(command: "cursor-agent", args: ["-p", "{{prompt}}"])
            ),
        ])
        let store = PanelStateStore(rootDirectory: panelsRoot)
        let runner = MutatingSeatRunner(
            markerName: "SEAT_MUTATION.txt",
            markerBody: "I wrote into cwd"
        )
        let coord = PanelCoordinator(
            stateStore: store,
            idFactory: { "panel_proof" },
            workerRunner: runner,
            models: models,
            registry: registry,
            panelsRoot: panelsRoot,
            cloneCopier: fmCopyCopier()
        )

        let start = coord.start(
            config: .init(
                projectRoot: root.path,
                projectId: "proj",
                targetPath: "docs/spec.md",
                seats: [PanelSeat(workerId: "model_cursor", lens: "probe")]
            ),
            models: models,
            registry: registry
        )
        guard case .success(let state) = start else {
            return XCTFail("start failed: \(start)")
        }
        XCTAssertEqual(
            PanelCoordinator.isolationPlan(
                seats: state.seats, models: models, registry: registry
            ).first?.mode,
            .clone
        )

        let round = await coord.runRound(panelId: state.id)
        guard case .success(let payload) = round else {
            return XCTFail("round failed: \(round)")
        }
        XCTAssertEqual(payload.round.seatResults.first?.status, .done)

        let after = try hashTree(at: root)
        XCTAssertEqual(before, after, "real project tree must be byte-identical after mutating seat")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("SEAT_MUTATION.txt").path),
            "mutation must not land in the real tree"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".git-would-be-commit").path)
        )

        // Clones cleaned after dispatch.
        let clonesDir = PanelSeatIsolation.clonesDirectory(panelId: state.id, panelsRoot: panelsRoot)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: clonesDir.appendingPathComponent("model_cursor").path),
            "per-seat clone cleaned after settle"
        )
    }

    func testDriverReadOnlySeatUsesRealRootWithoutClone() async throws {
        let root = try makeProjectTree()
        let panelsRoot = tmp.appendingPathComponent("panels", isDirectory: true)
        var seenCwd: String?
        struct CaptureRunner: WorkerInvoking {
            let box: Box
            final class Box: @unchecked Sendable { var cwd: String? }
            func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
                box.cwd = invocation.workingDirectory
                let report = """
                ```json
                {"findings":[],"noMaterialFindings":true,"reason":"ok"}
                ```
                """
                return MockWorkerInvoking.answering([report]).invoke(invocation)
            }
        }
        let box = CaptureRunner.Box()
        let models = [
            Model(id: "model_claude", displayName: "Claude", modelLabel: "s", driverId: "claude_code"),
        ]
        let registry = DriverRegistry([
            DriverManifest(
                id: "claude_code", displayName: "Claude", kind: .headlessCLI,
                invoke: .init(command: "claude", args: ["-p", "{{prompt}}", "--model", "{{model}}"])
            ),
        ])
        let store = PanelStateStore(rootDirectory: panelsRoot)
        let coord = PanelCoordinator(
            stateStore: store,
            idFactory: { "panel_ro" },
            workerRunner: CaptureRunner(box: box),
            models: models,
            registry: registry,
            panelsRoot: panelsRoot
        )
        _ = coord.start(
            config: .init(
                projectRoot: root.path, projectId: "p", targetPath: "docs/spec.md",
                seats: [PanelSeat(workerId: "model_claude", lens: "x")]
            ),
            models: models, registry: registry
        )
        _ = await coord.runRound(panelId: "panel_ro")
        seenCwd = box.cwd
        XCTAssertEqual(seenCwd, root.path, "RO seat must use the real project root")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: PanelSeatIsolation.seatCloneDirectory(
                    panelId: "panel_ro", seatId: "model_claude", panelsRoot: panelsRoot
                ).path
            ),
            "RO seat must not materialize a clone"
        )
    }
}

// MARK: - Tiny deterministic hasher (no CryptoKit dependency in tests)

private struct SHA256Like {
    private var chunks: [UInt8] = []

    mutating func feed(_ string: String) {
        chunks.append(contentsOf: Array(string.utf8))
        chunks.append(0)
    }

    mutating func feed(_ data: Data) {
        chunks.append(contentsOf: data)
        chunks.append(0)
    }

    var digestHex: String {
        // FNV-1a 64-bit — sufficient for tree identity in this proof, not crypto.
        var hash: UInt64 = 1_469_598_103_934_665_603
        for b in chunks {
            hash ^= UInt64(b)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
