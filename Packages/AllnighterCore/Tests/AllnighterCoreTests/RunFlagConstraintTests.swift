import XCTest
@testable import AllnighterCore

/// SH-S04 — run flag constraints are honor-or-fail (Law 6).
/// Registry owns mutual exclusion + requires/onlyWith; validation is not CLI-local.
final class RunFlagConstraintTests: XCTestCase {
    private let registry = ContractRegistry.milestone1

    private var run: ContractRegistry.CommandSpec {
        registry.commands.first { $0.name == "run" }!
    }

    private func present(_ args: [String]) -> CLIUsage.FlagConstraintError? {
        CLIUsage.validateFlagConstraints(args: args, commandName: "run", registry: registry)
    }

    // MARK: - Registry data

    func testRunDeclaresRequiredModeConstraints() {
        let kinds = Dictionary(uniqueKeysWithValues: run.flagConstraints.map { ($0.subject, $0) })
        XCTAssertEqual(kinds["thread-id"]?.kind, .onlyWith)
        XCTAssertEqual(kinds["thread-id"]?.peers, ["detach"])
        XCTAssertEqual(kinds["conversation-id"]?.kind, .onlyWith)
        XCTAssertEqual(kinds["conversation-id"]?.peers, ["detach"])
        XCTAssertEqual(kinds["message-id"]?.kind, .onlyWith)
        XCTAssertEqual(kinds["message-id"]?.peers, ["detach"])
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
        XCTAssertTrue(groups.contains(["detach", "stream"]))
        XCTAssertTrue(groups.contains(["detach", "try-fix"]))
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

    func testDetachOnlyIdsRejectedOutsideDetach() {
        for flag in ["thread-id", "conversation-id", "message-id"] {
            let err = present(["probe", "--\(flag)", "x"])
            XCTAssertNotNil(err, flag)
            XCTAssertEqual(err?.subject, flag)
            XCTAssertTrue(err?.message.contains("--detach") == true, err?.message ?? "")
            XCTAssertTrue(err?.message.contains("only valid with") == true, err?.message ?? "")
        }
    }

    func testDetachOnlyIdsAcceptedWithDetach() {
        for flag in ["thread-id", "conversation-id", "message-id"] {
            XCTAssertNil(present(["probe", "--detach", "--\(flag)", "x", "--json"]), flag)
        }
    }

    func testExecutorOnlyWithTryFix() {
        let bad = present(["probe", "--executor", "build_slice"])
        XCTAssertEqual(bad?.subject, "executor")
        XCTAssertTrue(bad?.message.contains("--try-fix") == true)

        XCTAssertNil(present(["probe", "--try-fix", "--executor", "build_slice"]))
    }

    func testAcceptSurvivorsRequiresRetryOf() {
        let bad = present(["probe", "--accept-survivors"])
        XCTAssertEqual(bad?.subject, "accept-survivors")
        XCTAssertTrue(bad?.message.contains("--retry-of") == true)

        XCTAssertNil(present(["probe", "--retry-of", "run_prior", "--accept-survivors"]))
    }

    func testDryRunStreamTryFixExclusions() {
        XCTAssertNotNil(present(["probe", "--dry-run", "--stream"]))
        XCTAssertTrue(present(["probe", "--dry-run", "--stream"])?.message.contains("mutually exclusive") == true)

        XCTAssertNotNil(present(["probe", "--dry-run", "--try-fix"]))
        XCTAssertTrue(present(["probe", "--dry-run", "--try-fix"])?.message.contains("mutually exclusive") == true)
    }

    func testDetachStreamTryFixExclusions() {
        XCTAssertNotNil(present(["probe", "--detach", "--stream"]))
        XCTAssertNotNil(present(["probe", "--detach", "--try-fix"]))
    }

    func testCommitFlagsExclusive() {
        let err = present(["probe", "--no-commit", "--commit-message", "ship it"])
        XCTAssertNotNil(err)
        XCTAssertTrue(err?.message.contains("mutually exclusive") == true)
        XCTAssertTrue(err?.message.contains("--no-commit") == true)
        XCTAssertTrue(err?.message.contains("--commit-message") == true)
    }

    func testJsonStreamExclusive() {
        let err = present(["probe", "--json", "--stream"])
        XCTAssertNotNil(err)
        XCTAssertTrue(err?.message.contains("mutually exclusive") == true)
    }

    /// Every declared run flag has at least one valid argv shape (or is a mode flag).
    func testEveryDeclaredRunFlagHasValidMode() {
        let modeFlags: Set<String> = ["dry-run", "detach", "stream", "try-fix"]
        var failures: [String] = []
        for flag in run.flags {
            let name = flag.name
            var args = ["probe"]
            // Satisfy companion constraints first.
            if let constraint = run.flagConstraints.first(where: { $0.subject == name }) {
                for peer in constraint.peers { args.append("--\(peer)") }
            }
            if flag.takesValue {
                args.append(contentsOf: ["--\(name)", "value"])
            } else {
                args.append("--\(name)")
            }
            // Avoid mutual-exclusion collisions with companions we added.
            if name == "stream" {
                args = ["probe", "--stream"]
            } else if name == "try-fix" {
                args = ["probe", "--try-fix"]
            } else if name == "dry-run" {
                args = ["probe", "--dry-run"]
            } else if name == "detach" {
                args = ["probe", "--detach"]
            } else if name == "json" {
                args = ["probe", "--json"]
            } else if name == "no-commit" {
                args = ["probe", "--no-commit"]
            } else if name == "commit-message" {
                args = ["probe", "--commit-message", "msg"]
            } else if name == "accept-survivors" {
                args = ["probe", "--retry-of", "run_x", "--accept-survivors"]
            } else if ["thread-id", "conversation-id", "message-id"].contains(name) {
                args = ["probe", "--detach", "--\(name)", "id"]
            } else if name == "executor" {
                args = ["probe", "--try-fix", "--executor", "build_slice"]
            }

            if let err = present(args) {
                failures.append("\(name): \(err.message) — argv \(args)")
            }
            // Mode flags themselves are always valid alone.
            if modeFlags.contains(name) {
                XCTAssertNil(present(["probe", "--\(name)"]), name)
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// Invalid mode-scoped combinations never clear the registry gate (no run/provider).
    func testInvalidModeMatrixNeverClearsGate() {
        let invalid: [[String]] = [
            ["probe", "--thread-id", "t"],
            ["probe", "--conversation-id", "c"],
            ["probe", "--message-id", "m"],
            ["probe", "--executor", "build_slice"],
            ["probe", "--accept-survivors"],
            ["probe", "--dry-run", "--stream"],
            ["probe", "--dry-run", "--try-fix"],
            ["probe", "--detach", "--stream"],
            ["probe", "--detach", "--try-fix"],
            ["probe", "--no-commit", "--commit-message", "x"],
            ["probe", "--json", "--stream"],
            ["probe", "--dry-run", "--executor", "build_slice"],
            ["probe", "--dry-run", "--thread-id", "t"],
            ["probe", "--try-fix", "--thread-id", "t"],
            ["probe", "--stream", "--accept-survivors"],
        ]
        for args in invalid {
            XCTAssertNotNil(present(args), "expected gate fail for \(args)")
            // Unknown-flag gate must also stay clean so the constraint owns the reject.
            XCTAssertNil(CLIUsage.validateFlags(args: args, commandName: "run", registry: registry), "\(args)")
        }
    }

    func testValidModeMatrixClearsGate() {
        let valid: [[String]] = [
            ["probe", "--json"],
            ["probe", "--dry-run", "--json"],
            ["probe", "--detach", "--json"],
            ["probe", "--stream"],
            ["probe", "--try-fix"],
            ["probe", "--try-fix", "--executor", "build_slice"],
            ["probe", "--detach", "--thread-id", "t", "--conversation-id", "c", "--message-id", "m", "--json"],
            ["probe", "--retry-of", "run_x", "--accept-survivors"],
            ["probe", "--no-commit"],
            ["probe", "--commit-message", "ship"],
            ["probe", "--dry-run", "--worker", "model_sonnet", "--team", "code_bug_hunt", "--effort", "high"],
        ]
        for args in valid {
            XCTAssertNil(present(args), "unexpected reject for \(args): \(present(args)?.message ?? "")")
        }
    }

    func testUsageErrorExitClassIsTwo() {
        XCTAssertEqual(registry.processExitCode(forErrorCode: "CLI_USAGE_ERROR"), 2)
    }
}
