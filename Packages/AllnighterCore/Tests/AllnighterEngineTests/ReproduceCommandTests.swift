import XCTest
import AllnighterCore
@testable import AllnighterCLI
@testable import AllnighterEngine

/// ADP-S01 — `reproduceCommand` round-trips every explicit selector so a replay
/// resolves to the same seats and write policy as the original run.
final class ReproduceCommandTests: XCTestCase {

    // MARK: - Fixtures

    private func sonnet() -> Model {
        Model(id: "model_sonnet", displayName: "Sonnet 5", modelLabel: "sonnet",
              driverId: "claude_code", role: .both)
    }

    private func bench() -> [Model] { [sonnet()] }

    private func project() -> Project {
        Project(
            id: "proj_test", displayName: "Test", localRootPath: "/tmp/alln-adp",
            normalizedRootPath: "/tmp/alln-adp", kind: .gitRepo,
            createdAt: Date(), lastOpenedAt: Date())
    }

    private func settings() -> DefaultModelSettings {
        DefaultModelSettings(
            defaultTier: .frontier,
            allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_sonnet"], balanced: ["model_sonnet"], economy: ["model_sonnet"]))
    }

    /// A double-quote-aware tokenizer so a quoted prompt survives as one token.
    private func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var sawAny = false
        for ch in command {
            if ch == "\"" { inQuotes.toggle(); sawAny = true; continue }
            if ch == " " && !inQuotes {
                if sawAny { tokens.append(current); current = ""; sawAny = false }
                continue
            }
            current.append(ch); sawAny = true
        }
        if sawAny { tokens.append(current) }
        return tokens
    }

    /// Parse a reproduce `alln run …` command back into resolver flags + message.
    private func parse(_ command: String) -> (message: String, flags: RunInvocationNormalizedFlags) {
        var tokens = Array(tokenize(command).drop(while: { $0 == "alln" || $0 == "run" }))
        var message = ""
        var flags = RunInvocationNormalizedFlags()
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            func next() -> String? { i + 1 < tokens.count ? tokens[i + 1] : nil }
            switch t {
            case "--project": flags.projectId = next(); i += 1
            case "--team": flags.teamId = next(); i += 1
            case "--model": flags.pinnedModelId = next(); i += 1
            case "--seat":
                var seats = flags.explicitSeatModelIds ?? []
                if let seat = next() { seats.append(seat) }
                flags.explicitSeatModelIds = seats
                i += 1
            case "--effort": flags.effort = next().flatMap(EffortLevel.init(rawValue:)); i += 1
            case "--lane": flags.lane = next().flatMap(WorkLane.init(rawValue:)); i += 1
            case "--no-commit": flags.noCommit = true
            default:
                if !t.hasPrefix("--") { message = t }
            }
            i += 1
        }
        return (message, flags)
    }

    private func resolve(_ message: String, _ flags: RunInvocationNormalizedFlags) -> ResolvedRunInvocation {
        RunInvocationResolver.resolve(
            RunInvocationInput(
                message: message, projectRoot: "/tmp/alln-adp",
                flagMode: .foreground, flags: flags),
            context: RunInvocationResolveContext(
                models: bench(), teams: TeamCatalog.all,
                readyModels: bench(), readyModelIds: Set(bench().map(\.id)),
                defaultSettings: settings()))
    }

    // MARK: - Tests

    func testRunCLIBuilderEmitsExplicitWorkerAndSelectors() {
        let run = TeamRun(
            id: "r1", prompt: "Fix the bug", presetId: nil,
            createdAt: Date(), lane: .code, effort: .high,
            laneContextOnly: true, explicitWorkerIds: ["model_sonnet"],
            noCommitOrdered: true)

        let command = RunCLI.reproduceCommand(run, project: project())
        let argv = tokenize(command)

        XCTAssertTrue(argv.contains("--model"), "dropped --model: \(command)")
        XCTAssertTrue(argv.contains("model_sonnet"), "dropped worker id: \(command)")
        XCTAssertTrue(argv.contains("--project"), "dropped --project: \(command)")
        XCTAssertTrue(argv.contains("--effort") && argv.contains("high"), "dropped --effort: \(command)")
        XCTAssertTrue(argv.contains("--lane") && argv.contains("code"), "dropped explicit --lane: \(command)")
        XCTAssertTrue(argv.contains("--no-commit"), "dropped --no-commit: \(command)")
        XCTAssertTrue(argv.contains("Fix the bug"), "dropped prompt: \(command)")
    }

    func testRunCLIReproduceResolvesToSameSeatAndPolicy() {
        // Original run: explicit --model on Default Team, mutating-allowed.
        let original = resolve("Fix the bug", RunInvocationNormalizedFlags(
            projectId: "proj_test", pinnedModelId: "model_sonnet", effort: .high))
        XCTAssertTrue(original.explicitModelChosen)
        XCTAssertEqual(original.seats.map(\.modelId), ["model_sonnet"])

        let run = TeamRun(
            id: "r1", prompt: "Fix the bug", presetId: nil,
            createdAt: Date(), effort: .high,
            explicitWorkerIds: ["model_sonnet"])
        let (msg, flags) = parse(RunCLI.reproduceCommand(run, project: project()))
        let replay = resolve(msg, flags)

        XCTAssertEqual(replay.seats.map(\.modelId), original.seats.map(\.modelId),
                       "replay must resolve the same seats")
        XCTAssertEqual(replay.writePolicy, original.writePolicy,
                       "replay must resolve the same write policy")
        XCTAssertTrue(replay.explicitModelChosen, "replay preserves explicit worker selection")
        XCTAssertEqual(replay.workerId, "model_sonnet")
    }

    func testLegacyBuilderEmitsExplicitWorker() {
        let run = TeamRun(
            id: "r1", prompt: "Say hi", presetId: "code_plan",
            createdAt: Date(), effort: .med,
            explicitWorkerIds: ["model_sonnet"])
        let command = AllnighterCLI.reproduceCommand(run)
        XCTAssertTrue(command.contains("--model model_sonnet"), "legacy builder dropped --model: \(command)")
        XCTAssertTrue(command.contains("--team code_plan"), command)
        XCTAssertTrue(command.contains("\"Say hi\""), command)
    }

    /// `explicitWorkerIds` is additive + optional: a run with no explicit worker
    /// encodes WITHOUT the key (so an old `run.json` predating it is byte-identical
    /// to a modern nil), and that key-less JSON decodes back to nil.
    func testExplicitWorkerIdsIsLegacySafeOptional() throws {
        let noWorker = TeamRun(
            id: "old-run", prompt: "hello", origin: .cli, createdAt: Date())
        XCTAssertNil(noWorker.explicitWorkerIds)

        let json = try JSONEncoder().encode(noWorker)
        let text = String(decoding: json, as: UTF8.self)
        XCTAssertFalse(text.contains("explicitWorkerIds"),
                       "a run with no explicit worker must not emit the key (legacy byte-parity)")

        let decoded = try JSONDecoder().decode(TeamRun.self, from: json)
        XCTAssertNil(decoded.explicitWorkerIds)
        // And the builders don't emit a spurious --model for such a run.
        XCTAssertFalse(AllnighterCLI.reproduceCommand(decoded).contains("--model"))

        // A run WITH an explicit worker round-trips the key.
        let withWorker = TeamRun(
            id: "r", prompt: "hi", createdAt: Date(), explicitWorkerIds: ["model_sonnet"])
        let rt = try JSONDecoder().decode(
            TeamRun.self, from: try JSONEncoder().encode(withWorker))
        XCTAssertEqual(rt.explicitWorkerIds, ["model_sonnet"])
    }
}
