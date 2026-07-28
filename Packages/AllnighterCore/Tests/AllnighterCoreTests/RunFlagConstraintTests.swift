import XCTest
@testable import AllnighterCore

/// Run flag constraints are honor-or-fail (Law 6). Registry owns mutual exclusion
/// plus requires/onlyWith; validation is not CLI-local.
final class RunFlagConstraintTests: XCTestCase {
    private let registry = ContractRegistry.milestone1

    private var run: ContractRegistry.CommandSpec {
        registry.commands.first { $0.name == "run" }!
    }

    private func constraintError(for args: [String]) -> CLIUsage.FlagConstraintError? {
        CLIUsage.validateFlagConstraints(args: args, commandName: "run", registry: registry)
    }

    // MARK: - Registry data

    func testRunDeclaresSeatFlagAndConstraints() {
        XCTAssertTrue(run.flags.contains { $0.name == "seat" })
        let groups = Set(run.mutuallyExclusiveFlags.map { Set($0) })
        XCTAssertTrue(groups.contains(["worker", "seat"]))
        let kinds = Dictionary(uniqueKeysWithValues: run.flagConstraints.map { ($0.subject, $0) })
        XCTAssertEqual(kinds["seat"]?.kind, .requires)
        XCTAssertEqual(kinds["seat"]?.peers, ["team"])
    }

    func testSeatRequiresTeam() {
        let bad = constraintError(for: ["probe", "--seat", "model_chatgpt"])
        XCTAssertEqual(bad?.subject, "seat")
        XCTAssertTrue(bad?.message.contains("--team") == true)
        XCTAssertNil(constraintError(for: [
            "probe", "--team", "code_spec_review_min",
            "--seat", "model_chatgpt", "--seat", "model_grok", "--seat", "model_cursor_composer_25"
        ]))
    }

    func testWorkerSeatMutuallyExclusive() {
        let err = constraintError(for: ["probe", "--worker", "model_chatgpt", "--seat", "model_grok"])
        XCTAssertNotNil(err)
        XCTAssertTrue(err?.message.contains("mutually exclusive") == true)
    }

    func testRunDeclaresRequiredModeConstraints() {
        let kinds = Dictionary(uniqueKeysWithValues: run.flagConstraints.map { ($0.subject, $0) })
        // CR-S06 deleted --detach. The three provenance ids were scoped to it and
        // are now plain foreground flags, so they must carry NO onlyWith peer.
        XCTAssertNil(kinds["thread-id"])
        XCTAssertNil(kinds["conversation-id"])
        XCTAssertNil(kinds["message-id"])
        XCTAssertEqual(kinds["executor"]?.kind, .onlyWith)
        XCTAssertEqual(kinds["executor"]?.peers, ["try-fix"])
        XCTAssertEqual(kinds["accept-survivors"]?.kind, .requires)
        XCTAssertEqual(kinds["accept-survivors"]?.peers, ["retry-of"])
    }

    func testRunMutualExclusionsCoverModesAndCommit() {
        let groups = Set(run.mutuallyExclusiveFlags.map { Set($0) })
        XCTAssertTrue(groups.contains(["json", "stream"]))
        XCTAssertTrue(groups.contains(["no-commit", "commit-message"]))
        XCTAssertTrue(groups.contains(["dry-run", "stream"]))
        XCTAssertTrue(groups.contains(["dry-run", "try-fix"]))
        XCTAssertFalse(groups.contains { $0.contains("detach") })
    }

    /// RSC-HF: `--no-wait` is mutually exclusive with `--stream` / `--dry-run` /
    /// `--try-fix`. Public `--run-id` was removed.
    func testRunDeclaresNoWaitFlag() {
        XCTAssertTrue(run.flags.contains { $0.name == "no-wait" })
        XCTAssertFalse(run.flags.contains { $0.name == "run-id" })

        let groups = Set(run.mutuallyExclusiveFlags.map { Set($0) })
        XCTAssertTrue(groups.contains(["no-wait", "stream"]))
        XCTAssertTrue(groups.contains(["no-wait", "dry-run"]))
        XCTAssertTrue(groups.contains(["no-wait", "try-fix"]))
    }

    func testConstraintSubjectsAndPeersAreDeclaredFlags() {
        let declared = Set(run.flags.map(\.name))
        for group in run.mutuallyExclusiveFlags {
            for flag in group {
                XCTAssertTrue(declared.contains(flag), "mutual-exclusion unknown flag \(flag)")
            }
        }
        for constraint in run.flagConstraints {
            XCTAssertTrue(declared.contains(constraint.subject), "constraint subject unknown: \(constraint.subject)")
            for peer in constraint.peers {
                XCTAssertTrue(declared.contains(peer), "constraint peer unknown: \(peer)")
            }
            XCTAssertFalse(constraint.peers.isEmpty)
        }
    }

    // MARK: - Invalid combinations (exit-2 gate; no dispatch)

    /// The provenance ids outlived `--detach`: they describe the originating
    /// thread for a foreground run, so they must now be accepted on their own.
    func testProvenanceIdsAcceptedOnTheForegroundPath() {
        for flag in ["thread-id", "conversation-id", "message-id"] {
            XCTAssertNil(constraintError(for: ["probe", "--\(flag)", "x"]), flag)
        }
    }

    func testExecutorOnlyWithTryFix() {
        let bad = constraintError(for: ["probe", "--executor", "build_slice"])
        XCTAssertEqual(bad?.subject, "executor")
        XCTAssertTrue(bad?.message.contains("--try-fix") == true)

        XCTAssertNil(constraintError(for: ["probe", "--try-fix", "--executor", "build_slice"]))
    }

    func testAcceptSurvivorsRequiresRetryOf() {
        let bad = constraintError(for: ["probe", "--accept-survivors"])
        XCTAssertEqual(bad?.subject, "accept-survivors")
        XCTAssertTrue(bad?.message.contains("--retry-of") == true)

        XCTAssertNil(constraintError(for: ["probe", "--retry-of", "run_prior", "--accept-survivors"]))
    }

    func testDryRunStreamTryFixExclusions() {
        let stream = constraintError(for: ["probe", "--dry-run", "--stream"])
        XCTAssertNotNil(stream)
        XCTAssertTrue(stream?.message.contains("mutually exclusive") == true)

        let tryFix = constraintError(for: ["probe", "--dry-run", "--try-fix"])
        XCTAssertNotNil(tryFix)
        XCTAssertTrue(tryFix?.message.contains("mutually exclusive") == true)
    }

    /// RSC-S04: `--no-wait` paired with `--stream` / `--dry-run` / `--try-fix` is
    /// rejected at the registry gate (exit 2), before any project resolution or
    /// dispatch — the same "reject at parse time" shape as the other mode pairs.
    func testNoWaitModeExclusions() {
        for peer in ["stream", "dry-run", "try-fix"] {
            let err = constraintError(for: ["probe", "--no-wait", "--\(peer)"])
            XCTAssertNotNil(err, "--no-wait + --\(peer) should be rejected")
            XCTAssertTrue(err?.message.contains("mutually exclusive") == true, "\(peer): \(err?.message ?? "")")
        }
        // Alone, --no-wait clears the gate.
        XCTAssertNil(constraintError(for: ["probe", "--no-wait"]))
    }

    /// `--detach` is gone, so argv naming it must fail as an unknown flag rather
    /// than being silently tolerated.
    func testDetachIsNoLongerADeclaredRunFlag() {
        XCTAssertFalse(run.flags.contains { $0.name == "detach" })
    }

    func testCommitFlagsExclusive() {
        let err = constraintError(for: ["probe", "--no-commit", "--commit-message", "ship it"])
        XCTAssertNotNil(err)
        XCTAssertTrue(err?.message.contains("mutually exclusive") == true)
        XCTAssertTrue(err?.message.contains("--no-commit") == true)
        XCTAssertTrue(err?.message.contains("--commit-message") == true)
    }

    func testJsonStreamExclusive() {
        let err = constraintError(for: ["probe", "--json", "--stream"])
        XCTAssertNotNil(err)
        XCTAssertTrue(err?.message.contains("mutually exclusive") == true)
    }

    /// Every declared run flag has at least one valid argv shape.
    func testEveryDeclaredRunFlagHasValidMode() {
        var failures: [String] = []
        for flag in run.flags {
            let args = validArgv(for: flag)
            if let err = constraintError(for: args) {
                failures.append("\(flag.name): \(err.message) — argv \(args)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// Invalid mode-scoped combinations never clear the registry gate (no run/provider).
    func testInvalidModeMatrixNeverClearsGate() {
        let invalid: [[String]] = [
            ["probe", "--executor", "build_slice"],
            ["probe", "--accept-survivors"],
            ["probe", "--dry-run", "--stream"],
            ["probe", "--dry-run", "--try-fix"],
            ["probe", "--no-commit", "--commit-message", "x"],
            ["probe", "--json", "--stream"],
            ["probe", "--dry-run", "--executor", "build_slice"],
            ["probe", "--stream", "--accept-survivors"],
            ["probe", "--no-wait", "--stream"],
            ["probe", "--no-wait", "--dry-run"],
            ["probe", "--no-wait", "--try-fix"],
        ]
        for args in invalid {
            XCTAssertNotNil(constraintError(for: args), "expected gate fail for \(args)")
            // Constraint owns the reject; unknown-flag gate must stay clean.
            XCTAssertNil(CLIUsage.validateFlags(args: args, commandName: "run", registry: registry), "\(args)")
        }
    }

    func testValidModeMatrixClearsGate() {
        let valid: [[String]] = [
            ["probe", "--json"],
            ["probe", "--dry-run", "--json"],
            ["probe", "--stream"],
            ["probe", "--try-fix"],
            ["probe", "--try-fix", "--executor", "build_slice"],
            ["probe", "--thread-id", "t", "--conversation-id", "c", "--message-id", "m", "--json"],
            ["probe", "--retry-of", "run_x", "--accept-survivors"],
            ["probe", "--no-commit"],
            ["probe", "--commit-message", "ship"],
            ["probe", "--dry-run", "--worker", "model_sonnet", "--team", "code_bug_hunt", "--effort", "high"],
            ["probe", "--no-wait"],
            ["probe", "--no-wait", "--json"],
        ]
        for args in valid {
            let err = constraintError(for: args)
            XCTAssertNil(err, "unexpected reject for \(args): \(err?.message ?? "")")
        }
    }

    func testUsageErrorExitClassIsTwo() {
        XCTAssertEqual(registry.processExitCode(forErrorCode: "CLI_USAGE_ERROR"), 2)
    }

    private func validArgv(for flag: ContractRegistry.FlagSpec) -> [String] {
        switch flag.name {
        case "stream", "try-fix", "dry-run", "json", "no-commit", "no-wait":
            return ["probe", "--\(flag.name)"]
        case "commit-message":
            return ["probe", "--commit-message", "msg"]
        case "accept-survivors":
            return ["probe", "--retry-of", "run_x", "--accept-survivors"]
        case "thread-id", "conversation-id", "message-id":
            return ["probe", "--\(flag.name)", "id"]
        case "executor":
            return ["probe", "--try-fix", "--executor", "build_slice"]
        default:
            var args = ["probe"]
            if let constraint = run.flagConstraints.first(where: { $0.subject == flag.name }) {
                for peer in constraint.peers { args.append("--\(peer)") }
            }
            if flag.takesValue {
                args.append(contentsOf: ["--\(flag.name)", "value"])
            } else {
                args.append("--\(flag.name)")
            }
            return args
        }
    }
}
