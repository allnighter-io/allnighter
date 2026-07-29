import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// CR-S03 proof wall: a research Team of two explicitly configured, DISTINCT
/// vendor CLIs runs both of them, once each, in the one canonical root, and
/// returns separately attributed non-empty answers. The selected roster survives
/// substitution pressure and never collapses.
///
/// The live gesture (real authenticated `claude` + `codex`) is
/// `scripts/code_red_works_test.sh live-direct`; this is its deterministic twin —
/// same `RunService.run` owner, injected runner instead of real vendors, so the
/// roster invariants are provable in the wall.
/// See docs/archive/phases/CODE_RED_Core_Infrastructure_Repair.md.
final class TwoSourceResearchTeamTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-two-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        setenv("ALLNIGHTER_SUPPORT_DIR", tmp.appendingPathComponent("support").path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("ALLNIGHTER_SUPPORT_DIR")
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Fixture

    /// Records every spawn as (command, workingDirectory) and answers with a
    /// per-vendor sentinel so attribution is checkable, not assumed.
    private final class SpawnRecorder: CommandRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var spawns: [(command: String, cwd: String?)] = []

        func run(
            command: String, args: [String], stdin: String?, env: [String: String],
            workingDirectory: String?, timeout: Duration
        ) async -> CommandResult {
            record(command: command, cwd: workingDirectory)
            let vendor = (command as NSString).lastPathComponent
            return CommandResult(
                stdout: "# Answer\nANSWER_FROM_\(vendor.uppercased())", stderr: "", exitCode: 0)
        }

        private func record(command: String, cwd: String?) {
            lock.lock(); spawns.append((command, cwd)); lock.unlock()
        }

        func recorded() -> [(command: String, cwd: String?)] {
            lock.lock(); defer { lock.unlock() }; return spawns
        }

        func vendorNames() -> [String] {
            recorded().map { ($0.command as NSString).lastPathComponent }
        }
    }

    private func runGit(_ args: [String], cwd: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd.path] + args
        p.standardOutput = Pipe(); p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    /// A clean disposable Git fixture — the live works test uses the same shape, so
    /// the Git observation assertion is exact.
    private func makeGitRepo() throws -> URL {
        let dir = tmp.appendingPathComponent("repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for a in [["init", "-q"], ["config", "user.email", "t@t.dev"], ["config", "user.name", "T"],
                  ["config", "commit.gpgsign", "false"]] { runGit(a, cwd: dir) }
        try "CODE_RED_SENTINEL\n".write(to: dir.appendingPathComponent("sentinel.txt"),
                                        atomically: true, encoding: .utf8)
        runGit(["add", "."], cwd: dir)
        runGit(["commit", "-q", "-m", "c1"], cwd: dir)
        return dir
    }

    private let claude = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                               driverId: "claude_code", role: .both)
    private let codex = Model(id: "model_chatgpt", displayName: "ChatGPT", modelLabel: "gpt",
                              driverId: "codex", role: .both)

    /// crew seat -> codex, lead seat -> claude_code. Exactly two seats, two
    /// distinct vendor CLIs, research (`mutating == false`). Mirrors the roster
    /// `scripts/code_red_works_test.sh` registers for the live gesture — same
    /// skills, same outputKind, same pinned models — so the two proofs describe
    /// one team rather than two lookalikes.
    private func twoSourceTeam(id: String = "code_red_two_source",
                               crewSpecs: [TeamWorkerSpec]? = nil) -> TeamPreset {
        TeamPreset(
            id: id, displayName: "Code Red Two Source", lane: .code, outputKind: .bugPacket,
            mutating: false,
            workerSpecs: crewSpecs ?? [
                TeamWorkerSpec(id: "bug_reproducer", skillId: "bug_reproducer",
                               purpose: .answer, preferredModelId: "model_chatgpt",
                               allowedModelIds: ["model_chatgpt"], fallbackPolicy: .exactOnly),
            ],
            lead: TeamLeadSpec(skillId: "bug_packet_writer", preferredModelId: "model_opus",
                               fallbackPolicy: .exactOnly))
    }

    private func service(
        team: TeamPreset, runner: CommandRunner, bench: [Model]? = nil, tiers: [String]? = nil
    ) -> RunService {
        let models = bench ?? [claude, codex]
        return RunService(
            models: models,
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "claude_code", command: "claude"),
                TestSupport.headlessManifest(id: "codex", command: "codex"),
                TestSupport.headlessManifest(id: "grok", command: "grok"),
            ]),
            teams: [team],
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs-\(UUID().uuidString)")),
            commandRunner: runner,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(
                    defaultTier: .frontier,
                    // Substitution is ON: the roster must hold because it was
                    // explicitly selected, not because swapping was disabled.
                    allowHealthySubstitutions: true,
                    tiers: TierMembership(frontier: tiers ?? models.map(\.id)))
            },
            probeRecords: {
                [
                    ToolProbeRecord(driverId: "claude_code", status: .ready(version: "1"), lastProbeAt: .distantPast),
                    ToolProbeRecord(driverId: "codex", status: .ready(version: "1"), lastProbeAt: .distantPast),
                    ToolProbeRecord(driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast),
                ]
            })
    }

    private func research(
        _ service: RunService, repo: URL, presetId: String = "code_red_two_source", id: String
    ) async throws -> TeamRun {
        let result = await service.run(
            RunRequest(message: "Inspect this repository and independently name its most important "
                                + "infrastructure risk. Research only; return evidence.",
                       repoRoot: repo.path, presetId: presetId),
            origin: .cli, runId: id)
        guard case .success(let run) = result else {
            XCTFail("two-source research run failed: \(result)"); throw TestError.runFailed
        }
        return run
    }

    private enum TestError: Error { case runFailed }

    // MARK: - Two distinct CLIs, once each, in the canonical root

    func testTwoDistinctSourcesEachSpawnOnceInTheCanonicalRoot() async throws {
        let repo = try makeGitRepo()
        let canonical = RunWriteLock.normalize(repo.path) ?? repo.path
        let recorder = SpawnRecorder()

        let run = try await research(service(team: twoSourceTeam(), runner: recorder),
                                     repo: repo, id: "cr-s03-two-source")

        // Exactly two vendor spawns: one `codex`, one `claude`. No duplication,
        // no third vendor, no collapse onto a single CLI.
        XCTAssertEqual(recorder.vendorNames().sorted(), ["claude", "codex"],
                       "the two selected distinct CLIs spawn exactly once each")

        // Both ran in the ONE canonical registered root.
        for spawn in recorder.recorded() {
            XCTAssertEqual(RunWriteLock.normalize(spawn.cwd ?? ""), canonical,
                           "\(spawn.command) must run in the canonical registered root")
        }
        XCTAssertEqual(RunWriteLock.normalize(run.repoRoot ?? ""), canonical)

        // The roster the run reports is the roster that was selected.
        XCTAssertEqual(Set(run.workers.map(\.modelId)), ["model_chatgpt", "model_opus"],
                       "workers: \(run.workers.map(\.modelId))")
        XCTAssertEqual(run.workers.count, 2, "no duplicated seat")
        XCTAssertFalse(run.mutating, "the research Team must not be mutating")
    }

    // MARK: - Separately attributed, non-empty answers

    func testEachSourceReturnsItsOwnNonEmptyAttributedAnswer() async throws {
        let repo = try makeGitRepo()
        let run = try await research(service(team: twoSourceTeam(), runner: SpawnRecorder()),
                                     repo: repo, id: "cr-s03-attribution")

        // Crew seat: its answer carries its own real source identity and its own
        // text — the per-vendor sentinel proves it was not copied from the other CLI.
        XCTAssertEqual(run.workerAnswers.count, 1, "one crew answer for the one crew seat")
        let crew = try XCTUnwrap(run.workerAnswers.first(where: { $0.modelId == "model_chatgpt" }),
                                 "no answer attributed to the codex crew seat")
        XCTAssertEqual(crew.result.status, .done)
        let crewText = crew.result.output ?? ""
        XCTAssertFalse(crewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "the codex seat returned an empty answer")
        XCTAssertTrue(crewText.contains("ANSWER_FROM_CODEX"),
                      "the codex seat must carry ITS OWN source's answer, got: \(crewText)")

        // Lead seat: a separate stage, separately attributed to the OTHER vendor,
        // carrying that vendor's own output. Two sources, two distinct records.
        let leadWorker = try XCTUnwrap(run.workers.first(where: { $0.modelId == "model_opus" }),
                                       "the claude lead seat is missing from the roster")
        let leadStage = try XCTUnwrap(
            run.stages.first(where: { $0.producedByWorkerId == leadWorker.id }),
            "no stage attributed to the claude lead seat; stages: "
                + "\(run.stages.map { "\($0.purpose):\($0.producedByWorkerId ?? "nil")" })")
        XCTAssertEqual(leadStage.status, .done)
        let leadText = leadStage.payload?.markdown ?? ""
        XCTAssertFalse(leadText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "the claude lead returned an empty output")
        XCTAssertTrue(leadText.contains("ANSWER_FROM_CLAUDE"),
                      "the lead must carry ITS OWN source's output, got: \(leadText)")
        XCTAssertFalse(crewText.contains("ANSWER_FROM_CLAUDE"),
                       "the crew answer must not be overwritten by the lead's source")
    }

    // MARK: - Bounded pre/post Git observation

    func testResearchRunRecordsCleanGitObservationForBothSources() async throws {
        let repo = try makeGitRepo()
        let head = GitObserver().observe(rootPath: repo.path).head
        let run = try await research(service(team: twoSourceTeam(), runner: SpawnRecorder()),
                                     repo: repo, id: "cr-s03-git-obs")

        let obs = try XCTUnwrap(run.researchGitObservation,
                                "a two-source research run must record bounded Git observation")
        XCTAssertFalse(obs.changed)
        XCTAssertEqual(obs.baselineHead, head)
        XCTAssertEqual(obs.head, head)
        XCTAssertTrue(obs.changedPaths.isEmpty)
        XCTAssertFalse(run.warnings.contains { $0.contains("research-write violation") })
    }

    // MARK: - An explicit roster ignores the rest of the bench

    /// Named for what it proves. An explicitly selected preset resolves each seat
    /// from its own declaration, so a third ready model — even one placed first in
    /// the default tier — is never consulted. It does NOT prove the auto-selection
    /// substitution policy: `SubstitutionResolver` is reached only for the default
    /// team route and for an explicit `--model`, never for a `presetId` run, so
    /// `allowHealthySubstitutions` is inert on this path by construction.
    /// Reseat-on-failure is covered by `BenchReadinessAndSeatReseatTests`.
    func testExplicitlySelectedRosterIgnoresOtherReadyBenchModels() async throws {
        let repo = try makeGitRepo()
        let recorder = SpawnRecorder()
        let grok = Model(id: "model_grok", displayName: "Grok", modelLabel: "grok",
                         driverId: "grok", role: .both)
        let svc = service(team: twoSourceTeam(), runner: recorder,
                          bench: [grok, claude, codex],
                          tiers: ["model_grok", "model_opus", "model_chatgpt"])

        let run = try await research(svc, repo: repo, id: "cr-s03-explicit-roster")

        XCTAssertFalse(recorder.vendorNames().contains("grok"),
                       "a ready bench mate must never appear in an explicitly selected roster")
        XCTAssertEqual(recorder.vendorNames().sorted(), ["claude", "codex"])
        XCTAssertEqual(Set(run.workers.map(\.modelId)), ["model_chatgpt", "model_opus"])
        XCTAssertEqual(run.status, .complete, "the run reaches one terminal state")
    }

    /// The seat that goes DOWN is the one the packet cares about: a declared model
    /// that is disabled must not be quietly re-seated onto another ready model.
    /// `exactOnly` is what the live works-test roster pins, so prove it here.
    func testDisabledDeclaredSeatIsNotReseatedOntoAnotherReadyModel() async throws {
        let repo = try makeGitRepo()
        let recorder = SpawnRecorder()
        // The declared crew model is disabled; a same-vendor sibling and a
        // different vendor are both ready and would be tempting substitutes.
        let downCodex = Model(id: "model_chatgpt", displayName: "ChatGPT", modelLabel: "gpt",
                              driverId: "codex", role: .both, enabled: false)
        let siblingCodex = Model(id: "model_chatgpt_54", displayName: "ChatGPT 5.4",
                                 modelLabel: "gpt-54", driverId: "codex", role: .both)
        var team = twoSourceTeam(id: "code_red_two_source_exact")
        team.workerSpecs[0].fallbackPolicy = .exactOnly
        team.workerSpecs[0].allowedModelIds = ["model_chatgpt"]
        team.lead.fallbackPolicy = .exactOnly

        let svc = service(team: team, runner: recorder,
                          bench: [downCodex, siblingCodex, claude],
                          tiers: ["model_chatgpt_54", "model_opus"])
        let result = await svc.run(
            RunRequest(message: "research only", repoRoot: repo.path,
                       presetId: "code_red_two_source_exact"),
            origin: .cli, runId: "cr-s03-no-reseat")

        // The run must fail CLOSED, naming the seat and the unavailable model —
        // not quietly reseat and return a plausible answer from the wrong mind.
        guard case .failure(let reason) = result else {
            return XCTFail("a down exactOnly seat must fail closed, got: \(result)")
        }
        let text = String(describing: reason)
        XCTAssertTrue(text.contains("exactOnly") && text.contains("model_chatgpt"),
                      "the failure must name the policy and the unavailable model, got: \(text)")
        XCTAssertTrue(recorder.vendorNames().isEmpty,
                      "nothing may spawn once a required seat cannot resolve: \(recorder.vendorNames())")
        XCTAssertFalse(text.contains("model_chatgpt_54"),
                       "the sibling model must not appear anywhere in the outcome")
    }

    // MARK: - No roster collapse

    func testTwoCrewSeatsSharingOneSkillDoNotCollapse() async throws {
        let repo = try makeGitRepo()
        let recorder = SpawnRecorder()
        // Same skill on both crew rows: the roster is defined by the SELECTED
        // sources, so identical skills must not be deduplicated into one seat.
        let team = twoSourceTeam(crewSpecs: [
            TeamWorkerSpec(id: "crew_codex", skillId: "bug_reproducer",
                           purpose: .answer, preferredModelId: "model_chatgpt"),
            TeamWorkerSpec(id: "crew_claude", skillId: "bug_reproducer",
                           purpose: .answer, preferredModelId: "model_opus"),
        ])

        let run = try await research(service(team: team, runner: recorder),
                                     repo: repo, id: "cr-s03-no-collapse")

        XCTAssertEqual(run.workers.filter { $0.purpose == .answer }.count, 2,
                       "two selected crew seats stay two seats: \(run.workers.map(\.modelId))")
        XCTAssertEqual(Set(run.workers.map(\.modelId)), ["model_chatgpt", "model_opus"])
        XCTAssertEqual(recorder.vendorNames().sorted(), ["claude", "claude", "codex"],
                       "two crew spawns plus the lead's own spawn")
    }
}
