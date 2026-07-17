import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PO-S06 works/seam tests: scoped write lanes.
/// - Docs-only + build holder concurrent (two-process flock pattern from S03b)
/// - Declared-docs turn touching Sources/ → WRITE_SCOPE_VIOLATION + scopeViolation
/// - Overlapping scopes queue FIFO with tickets
/// - Undeclared scope = legacy exclusive full-build behavior
final class ProcessOwnershipScopedWriteLanesTests: XCTestCase {

    // MARK: - Scope + parser seams

    func testTurnWriteScopeOverlapAndContainment() {
        let docs = TurnWriteScope(pathPrefixes: ["docs/"], needsBuildLane: false)
        let sources = TurnWriteScope(pathPrefixes: ["Sources/"], needsBuildLane: true)
        let full = TurnWriteScope.legacyFullBuild

        XCTAssertFalse(TurnWriteScope.conflicts(docs, sources), "disjoint prefixes must not conflict")
        XCTAssertTrue(TurnWriteScope.conflicts(docs, full), "full scope conflicts with everyone")
        XCTAssertTrue(
            TurnWriteScope.conflicts(
                TurnWriteScope(pathPrefixes: ["docs/"], needsBuildLane: true),
                TurnWriteScope(pathPrefixes: ["Sources/"], needsBuildLane: true)
            ),
            "two build-lane claims conflict even when path prefixes are disjoint"
        )
        XCTAssertTrue(docs.contains(path: "docs/phases/x.md"))
        XCTAssertFalse(docs.contains(path: "Sources/Foo.swift"))
        XCTAssertEqual(
            docs.outOfScopePaths(in: ["docs/a.md", "Sources/X.swift"]),
            ["Sources/X.swift"]
        )
    }

    func testWriteScopeParserFenceAndObject() {
        let report = """
        Done.

        ```writeScope
        docs/
        docs/phases/
        ```

        ```needsBuildLane
        false
        ```
        """
        let parsed = TurnWriteScopeParser.parse(from: report)
        XCTAssertEqual(parsed?.pathPrefixes, ["docs/", "docs/phases/"])
        XCTAssertEqual(parsed?.needsBuildLane, false)

        let obj = #"tail {"writeScope":["docs/"],"needsBuildLane":false} end"#
        let fromObj = TurnWriteScopeParser.parse(from: obj)
        XCTAssertEqual(fromObj?.pathPrefixes, ["docs/"])
        XCTAssertEqual(fromObj?.needsBuildLane, false)

        XCTAssertNil(TurnWriteScopeParser.parse(from: "no declaration here"))
        XCTAssertEqual(
            TurnWriteScopeParser.resolve(turnState: nil, report: nil),
            .legacyFullBuild
        )
        let state = TurnWriteScope(pathPrefixes: ["Packages/"], needsBuildLane: true)
        XCTAssertEqual(
            TurnWriteScopeParser.resolve(turnState: state, report: report),
            state,
            "turn state wins over report"
        )
    }

    func testWriteScopeViolationErrorRegistered() {
        let codes = ContractRegistry.milestone1.errors.map(\.code)
        XCTAssertTrue(codes.contains(ScopeViolation.errorCode))
        XCTAssertEqual(ScopeViolation.errorCode, "WRITE_SCOPE_VIOLATION")
    }

    // MARK: - Overlapping scopes queue FIFO

    func testOverlappingScopesQueueWithTicket() async throws {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/po-s06-overlap-\(UUID().uuidString)")
        let identity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))
        let docsScope = TurnWriteScope(pathPrefixes: ["docs/"], needsBuildLane: false)

        let first = await reg.tryAcquire(
            key,
            claim: .make(
                id: "docs-a", kind: "relayDevTurn", identity: identity, writeScope: docsScope
            )
        )
        guard case .success(let tokenA) = first else {
            return XCTFail("first docs-only holder must acquire")
        }
        defer { Task { await reg.release(key, token: tokenA) } }

        let second = await reg.tryAcquire(
            key,
            claim: .make(
                id: "docs-b", kind: "relayDevTurn", identity: identity, writeScope: docsScope
            )
        )
        guard case .failure(let ticket) = second else {
            return XCTFail("overlapping docs scopes must queue with a ticket, not co-hold")
        }
        XCTAssertEqual(ticket.holder.id, "docs-a")
        XCTAssertEqual(ticket.position, 1)
    }

    // MARK: - Disjoint scopes co-hold (in-process)

    func testDisjointDocsAndBuildCoHoldInProcess() async throws {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/po-s06-disjoint-\(UUID().uuidString)")
        let identity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))

        let build = await reg.tryAcquire(
            key,
            claim: .make(
                id: "build-holder",
                kind: "relayDevTurn",
                identity: identity,
                writeScope: TurnWriteScope(pathPrefixes: ["Sources/"], needsBuildLane: true)
            )
        )
        guard case .success(let buildToken) = build else {
            return XCTFail("build holder must acquire")
        }
        defer { Task { await reg.release(key, token: buildToken) } }

        let docs = await reg.tryAcquire(
            key,
            claim: .make(
                id: "docs-holder",
                kind: "pilotDevTurn",
                identity: identity,
                writeScope: TurnWriteScope(pathPrefixes: ["docs/"], needsBuildLane: false)
            )
        )
        guard case .success(let docsToken) = docs else {
            return XCTFail("docs-only disjoint scope must co-hold with build lane: \(docs)")
        }
        let countWhileBoth = await reg.localHolderCount(for: key)
        XCTAssertEqual(countWhileBoth, 2)
        await reg.release(key, token: docsToken)
        let countAfterDocs = await reg.localHolderCount(for: key)
        XCTAssertEqual(countAfterDocs, 1)
    }

    // MARK: - Same-id nested re-acquire (PO-S06 self-deadlock fix)

    /// Stall-retry / nested same-turn re-acquire must reuse the hold (refcount bump)
    /// and return immediately — never queue behind itself in waiters.
    func testSameIdNestedReacquireReusesHoldImmediately() async throws {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/po-s06-sameid-\(UUID().uuidString)")
        let identity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))
        let claim = ExecutionLane.Claim.make(
            id: "relay-turn-1",
            kind: "relayDevTurn",
            identity: identity,
            writeScope: .legacyFullBuild
        )

        let first = await reg.tryAcquire(key, claim: claim)
        guard case .success(let token) = first else {
            return XCTFail("first acquire must succeed: \(first)")
        }

        // Nested same-id re-acquire: must return the same token immediately
        // (depth bump), not park in the waiter queue.
        let nested = await reg.waitToAcquire(
            key, claim: claim, timeout: .milliseconds(200)
        )
        XCTAssertEqual(nested, token, "same-id re-acquire must reuse the existing hold")
        let waiters = await reg.waiterCount(for: key)
        XCTAssertEqual(waiters, 0, "same-id re-acquire must not enqueue a waiter")

        // Two releases required (depth 2 → 1 → 0).
        await reg.release(key, token: token)
        let heldAfterOne = await reg.isHeld(key)
        XCTAssertTrue(heldAfterOne, "outer hold remains after one nested release")
        await reg.release(key, token: token)
        let heldAfterTwo = await reg.isHeld(key)
        XCTAssertFalse(heldAfterTwo, "outermost release frees the lane")
    }

    /// Two different claim ids with disjoint scopes still co-hold (S06 feature intact).
    func testTwoHolderDisjointScopeCoHoldStillWorks() async throws {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/po-s06-twoholder-\(UUID().uuidString)")
        let identity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))

        let a = await reg.tryAcquire(
            key,
            claim: .make(
                id: "docs-a",
                kind: "pilotDevTurn",
                identity: identity,
                writeScope: TurnWriteScope(pathPrefixes: ["docs/"], needsBuildLane: false)
            )
        )
        let b = await reg.tryAcquire(
            key,
            claim: .make(
                id: "docs-b",
                kind: "relayDevTurn",
                identity: identity,
                writeScope: TurnWriteScope(pathPrefixes: ["Packages/AllnighterCore/"], needsBuildLane: false)
            )
        )
        guard case .success(let tokenA) = a else {
            return XCTFail("first disjoint holder must acquire: \(a)")
        }
        guard case .success(let tokenB) = b else {
            return XCTFail("second disjoint-scope holder must co-hold: \(b)")
        }
        XCTAssertNotEqual(tokenA, tokenB)
        let count = await reg.localHolderCount(for: key)
        XCTAssertEqual(count, 2, "disjoint scopes co-hold as two distinct holders")
        await reg.release(key, token: tokenA)
        await reg.release(key, token: tokenB)
        let finalCount = await reg.localHolderCount(for: key)
        XCTAssertEqual(finalCount, 0)
    }

    /// Cross-registry nested acquire (relay shared lane + private RunService write lock)
    /// must succeed via process-wide flock refcount — the stall-retry hang path.
    func testCrossRegistryNestedAcquireDoesNotSelfDeadlock() async throws {
        let outer = ExecutionLaneRegistry()
        let inner = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/po-s06-xreg-\(UUID().uuidString)")
        let identity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))

        let outerClaim = ExecutionLane.Claim.make(
            id: "relay-abc", kind: "relayDevTurn", identity: identity
        )
        let outerTok = await outer.waitToAcquire(
            key, claim: outerClaim, timeout: .seconds(1)
        )
        XCTAssertNotNil(outerTok, "outer registry must take the lane")

        // Inner registry (different actor instance, same process) re-acquires for
        // a mutating run — must not park forever on the outer's disk metadata.
        let innerClaim = ExecutionLane.Claim.make(
            id: "mutatingRun", kind: "mutatingRun", identity: identity
        )
        let innerTok = await inner.waitToAcquire(
            key, claim: innerClaim, timeout: .milliseconds(500)
        )
        XCTAssertNotNil(
            innerTok,
            "nested same-process acquire via second registry must reuse flock refcount"
        )
        if let innerTok {
            await inner.release(key, token: innerTok)
        }
        if let outerTok {
            await outer.release(key, token: outerTok)
        }
    }

    // MARK: - Undeclared = legacy exclusive

    func testUndeclaredScopeIsLegacyExclusive() async throws {
        let reg = ExecutionLaneRegistry()
        let key = ExecutionLane.key(repoRoot: "/tmp/po-s06-legacy-\(UUID().uuidString)")
        let identity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))

        let a = await reg.tryAcquire(
            key,
            claim: .make(id: "legacy-a", kind: "relayDevTurn", identity: identity)
        )
        guard case .success(let tokenA) = a else {
            return XCTFail("first legacy claim must acquire")
        }
        defer { Task { await reg.release(key, token: tokenA) } }

        let b = await reg.tryAcquire(
            key,
            claim: .make(id: "legacy-b", kind: "relayDevTurn", identity: identity)
        )
        guard case .failure(let ticket) = b else {
            return XCTFail("undeclared claims are exclusive (legacy full-build)")
        }
        XCTAssertEqual(ticket.holder.id, "legacy-a")
    }

    // MARK: - Cross-process: docs-only concurrent with build flock holder (S03b pattern)

    func testCrossProcessDocsOnlyConcurrentWithBuildHolder() async throws {
        let support = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-s06-xproc-support-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        setenv("ALLNIGHTER_SUPPORT_DIR", support.path, 1)
        defer {
            unsetenv("ALLNIGHTER_SUPPORT_DIR")
            try? FileManager.default.removeItem(at: support)
        }

        let key = ExecutionLane.key(repoRoot: "/tmp/po-s06-xproc-\(UUID().uuidString)")
        let laneDir = ExecutionLaneFlock.directory(forLaneKey: key)
        let lockPath = ExecutionLaneFlock.lockURL(forLaneKey: key).path
        let holderPath = ExecutionLaneFlock.holderURL(forLaneKey: key).path
        try FileManager.default.createDirectory(at: laneDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: laneDir) }

        // Child holds exclusive build flock + multi-holder file with Sources/ scope.
        // Identity uses the child's real pid so isIdentityAlive stays true while it runs
        // (fake pids are pruned as dead and would skip conflict checks).
        let script = """
        python3 -c '
        import fcntl, os, time, sys, json
        lock_path = sys.argv[1]
        holder_path = sys.argv[2]
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        meta = {
          "holders": [{
            "acquiredAt": "2020-01-01T00:00:00Z",
            "id": "child_build",
            "identity": {"kind": "inProcess", "pid": os.getpid(), "startTimeTicks": 1},
            "kind": "relayDevTurn",
            "needsBuildLane": True,
            "writeScope": ["Sources/"]
          }]
        }
        with open(holder_path, "w") as f:
            f.write(json.dumps(meta))
        sys.stdout.write("HELD\\n")
        sys.stdout.flush()
        time.sleep(120)
        ' '\(lockPath)' '\(holderPath)'
        """

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", script]
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = Pipe()
        try child.run()
        defer {
            if child.isRunning {
                child.terminate()
                child.waitUntilExit()
            }
        }

        let ready = pipe.fileHandleForReading
        var sawHeld = false
        let deadline = Date().addingTimeInterval(5)
        var buf = Data()
        while Date() < deadline, !sawHeld {
            let chunk = ready.availableData
            if !chunk.isEmpty {
                buf.append(chunk)
                if String(data: buf, encoding: .utf8)?.contains("HELD") == true {
                    sawHeld = true
                    break
                }
            } else {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        XCTAssertTrue(sawHeld, "child must flock and signal HELD")
        XCTAssertTrue(child.isRunning)

        // Note: startTimeTicks may not match the real process; if identity is still
        // considered dead, conflict checks fall back to build-flock occupancy below.

        let reg = ExecutionLaneRegistry()
        let live = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))
        let docsScope = TurnWriteScope(pathPrefixes: ["docs/"], needsBuildLane: false)
        let acquired = await reg.tryAcquire(
            key,
            claim: .make(
                id: "parent_docs", kind: "pilotDevTurn", identity: live, writeScope: docsScope
            ),
            now: Date()
        )
        guard case .success(let token) = acquired else {
            return XCTFail(
                "docs-only disjoint scope must proceed concurrently with remote build holder: \(acquired)"
            )
        }
        await reg.release(key, token: token)

        // Overlapping scope against the same child must still ticket.
        let overlap = await reg.tryAcquire(
            key,
            claim: .make(
                id: "parent_overlap",
                kind: "relayDevTurn",
                identity: live,
                writeScope: TurnWriteScope(pathPrefixes: ["Sources/Allnighter"], needsBuildLane: false)
            ),
            now: Date()
        )
        guard case .failure(let ticket) = overlap else {
            return XCTFail("overlapping scope with remote build holder must queue")
        }
        XCTAssertEqual(ticket.holder.id, "child_build")
    }

    // MARK: - Fail-closed commit-diff → scopeViolation

    func testDeclaredDocsTurnTouchingSourcesRejectedWithScopeViolation() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-s06-violation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let repo = try makeGitRepo(in: tmp)
        let git = GitObserver()
        let baseline = try XCTUnwrap(git.observe(rootPath: repo.path).head)

        // Simulate a "docs" turn that also touched Sources/ (out of scope).
        let sourcesDir = repo.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try "bad".write(
            to: sourcesDir.appendingPathComponent("Evil.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "ok".write(
            to: repo.appendingPathComponent("docs").appendingPathComponent("note.md"),
            atomically: true,
            encoding: .utf8
        )
        // ensure docs/ exists
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent("docs"), withIntermediateDirectories: true
        )
        try "ok".write(
            to: repo.appendingPathComponent("docs/note.md"),
            atomically: true,
            encoding: .utf8
        )
        func runGit(_ args: [String]) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", repo.path] + args
            p.standardOutput = Pipe(); p.standardError = Pipe()
            p.standardInput = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        }
        runGit(["add", "."])
        runGit(["commit", "-q", "-m", "out of scope"])
        let head = try XCTUnwrap(git.observe(rootPath: repo.path).head)
        XCTAssertNotEqual(baseline, head)

        let scope = TurnWriteScope(pathPrefixes: ["docs/"], needsBuildLane: false)
        let changed = git.changedFilesInRange(
            rootPath: repo.path, baseline: baseline, head: head
        )
        let outOfScope = scope.outOfScopePaths(in: changed)
        XCTAssertTrue(
            outOfScope.contains(where: { $0.hasPrefix("Sources/") || $0.contains("Evil.swift") }),
            "expected Sources/ path in out-of-scope set: \(outOfScope)"
        )

        let violation = ScopeViolation(
            declaredScope: scope.pathPrefixes,
            outOfScopePaths: outOfScope
        )
        XCTAssertEqual(violation.code, "WRITE_SCOPE_VIOLATION")

        // Wire surface: endReason stays reported; scopeViolation on roundLog.
        let round = RelayRound(
            roundNumber: 1,
            baselineHead: baseline,
            headAfterDev: head,
            startedAt: Date(),
            devTurnEndReason: .reported,
            writeScope: scope,
            scopeViolation: violation
        )
        let state = RelayState(
            id: "relay_scope_violation",
            projectRoot: repo.path,
            docPath: "docs/spec.md",
            pmWorkerId: "model_pm",
            devWorkerId: "model_dev",
            status: .awaitingPM,
            rounds: [round],
            createdAt: Date()
        )
        let json = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        XCTAssertEqual(json.roundLog[0].endReason, "reported")
        XCTAssertEqual(json.roundLog[0].scopeViolation?.code, "WRITE_SCOPE_VIOLATION")
        XCTAssertEqual(json.roundLog[0].writeScope?.pathPrefixes, ["docs/"])
        XCTAssertFalse(json.roundLog[0].scopeViolation?.outOfScopePaths.isEmpty ?? true)
        // Registered typed error — agents recover via catalog, not honor system.
        XCTAssertNotNil(
            ContractRegistry.milestone1.errors.first { $0.code == "WRITE_SCOPE_VIOLATION" }
        )
    }

    // MARK: - Fixtures

    private func makeGitRepo(in tmp: URL) throws -> URL {
        let dir = tmp.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func git(_ args: [String]) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", dir.path] + args
            p.standardOutput = Pipe(); p.standardError = Pipe()
            p.standardInput = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        }
        for a in [["init", "-q"], ["config", "user.email", "t@t.dev"],
                  ["config", "user.name", "T"], ["config", "commit.gpgsign", "false"]] {
            git(a)
        }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("docs"), withIntermediateDirectories: true
        )
        try "spec".write(
            to: dir.appendingPathComponent("docs/spec.md"), atomically: true, encoding: .utf8
        )
        git(["add", "."]); git(["commit", "-q", "-m", "c1"])
        return dir
    }
}
