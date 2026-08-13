import XCTest
@testable import AllnighterCore

/// The registry is the SSOT for the `alln` contract; these tests enforce that it
/// stays internally consistent and in lock-step with the closed types it owns
/// (docs/archive/phases/CLI_Implementation_Contract.md §Contract Registry).
final class ContractRegistryTests: XCTestCase {
    private let reg = ContractRegistry.milestone1

    func testContractVersionMatchesTeamRunFixture() throws {
        let trj = try Fixtures.decode(TeamRunJSON.self, .teamRunJSON)
        XCTAssertEqual(reg.contractVersion, trj.contractVersion)
    }

    /// Team-run and Pending next-action kinds must match the registry catalog.
    func testNextActionKindParityWithClosedEnum() {
        let teamKinds = Set(TeamRunJSON.NextAction.Kind.allCases.map(\.rawValue))
        let pendingKinds = Set(PendingItemJSON.NextAction.Kind.allCases.map(\.rawValue))
        let registryKinds = Set(reg.nextActionKinds.map(\.kind))
        XCTAssertEqual(registryKinds, teamKinds.union(pendingKinds), "nextActions.kind catalogs drifted from closed enums")
    }

    /// The in-scope M1 command set must equal the documented Milestone Boundary.
    func testM1CommandSetMatchesMilestoneBoundary() {
        let m1 = Set(reg.commands.filter { $0.milestone == .m1 }.map(\.name))
        let expected: Set<String> = [
            "docs", "menu", "menu show", "doctor", "doctor explain", "doctor handoff", "doctor silence", "detect", "capacity", "bootstrap", "install-cli", "uninstall", "version", "update",
            "models", "models enable", "models disable", "models add", "models verify", "models update", "models delete",
            "drivers", "drivers park", "drivers unpark",
            "catalog validate",
            "teams", "teams show", "teams definition", "teams duplicate", "teams new", "teams edit", "teams set-default", "teams delete", "teams restore",
            "skills", "skills show", "skills duplicate", "skills new", "skills edit", "skills restore", "skills delete", "skills gc",
            "team cancel", "team reconcile",
            "ps", "kill", "gc",
            "thread send", "thread get", "thread attachment", "thread rename", "thread status",
            "run", "run resume",
            "continuity receipt",
            "loop start", "loop list", "loop status", "loop stop", "loop resume", "loop wait", "loop step", "loop pm",
            "pair relay", "pair relay-status", "pair relay-resume", "pair relay adopt", "pair relay stop",
            "pair pilot start", "pair pilot handoff", "pair pilot status", "pair pilot watch", "pair pilot adopt", "pair pilot scaffold-handover",
            "show", "floor show", "artifact show", "artifact export", "spec", "history", "export", "dev export-contracts", "serve", "serve status", "serve repair", "serve enable", "serve disable",
            "pending add", "pending list", "pending queue", "pending show", "pending submit", "pending edit",
            "pending reorder", "pending cancel", "pending run",
            "project list", "project add", "project show", "project archive", "project unarchive",
            "project threads", "project pending", "project stalled", "project context",
            "stalled list", "stalled check", "stalled wait", "stalled dismiss",
            "project models", "project recheck-models",
            "defaults show", "defaults tier", "defaults assign", "defaults unassign",
            "defaults substitutions", "defaults reset",
            "boost-window show", "boost-window set", "boost-window seed",
            "boost-window observations clear",
            "help search", "help get", "help topics",
            "opencode-go configure", "opencode-go status",
            "opencode-local setup", "opencode-local undo", "opencode-local status",
        ]
        XCTAssertEqual(m1.sorted(), expected.sorted())
    }

    func testCommandNamesAreUnique() {
        let names = reg.commands.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "duplicate command names")
    }

    func testCommandFlagsAreUniquePerCommand() {
        for command in reg.commands {
            let flags = command.flags.map(\.name)
            XCTAssertEqual(flags.count, Set(flags).count, "duplicate flag in \(command.name)")
        }
    }

    /// Mutually-exclusive / requires / onlyWith flag names must actually be declared.
    func testMutualExclusionsReferenceRealFlags() {
        for command in reg.commands {
            let declared = Set(command.flags.map(\.name))
            for group in command.mutuallyExclusiveFlags {
                for flag in group {
                    XCTAssertTrue(declared.contains(flag), "\(command.name) mutual-exclusion references unknown flag \(flag)")
                }
            }
            for constraint in command.flagConstraints {
                XCTAssertTrue(declared.contains(constraint.subject),
                              "\(command.name) constraint subject unknown: \(constraint.subject)")
                for peer in constraint.peers {
                    XCTAssertTrue(declared.contains(peer),
                                  "\(command.name) constraint peer unknown: \(peer)")
                }
            }
        }
        // The contract's M1 mutual exclusion on run: --json | --stream (plus dry-run pairs).
        // CR-S06 deleted --detach, so no exclusion may name it.
        let run = reg.commands.first { $0.name == "run" }
        XCTAssertTrue(run?.mutuallyExclusiveFlags.contains(["json", "stream"]) == true)
        XCTAssertTrue(run?.mutuallyExclusiveFlags.contains(["dry-run", "stream"]) == true)
        XCTAssertFalse(run?.flags.contains { $0.name == "detach" } == true)
        XCTAssertFalse(run?.mutuallyExclusiveFlags.contains { $0.contains("detach") } == true)
        XCTAssertTrue(run?.flagConstraints.contains(where: {
            $0.subject == "executor" && $0.kind == .onlyWith && $0.peers == ["try-fix"]
        }) == true)
    }

    /// Every emitted error code carries the recovery metadata the ladder needs.
    func testEveryErrorHasRecoveryMetadata() {
        XCTAssertFalse(reg.errors.isEmpty)
        let codes = reg.errors.map(\.code)
        XCTAssertEqual(codes.count, Set(codes).count, "duplicate error code")
        for e in reg.errors {
            XCTAssertFalse(e.code.isEmpty)
            XCTAssertFalse(e.ruleId.isEmpty, "\(e.code) missing ruleId")
            XCTAssertFalse(e.agentAction.isEmpty, "\(e.code) missing agentAction")
            XCTAssertFalse(e.explain.isEmpty, "\(e.code) missing explain text")
        }
        // Spot-check the contract's anchor example.
        let auth = reg.errors.first { $0.code == "SOURCE_AUTH_EXPIRED" }
        XCTAssertEqual(auth?.ruleId, "source.auth.expired")
        XCTAssertEqual(auth?.requiresManual, true)
        XCTAssertEqual(auth?.retryable, false)
    }

    /// RSC-HF: `RUN_ID_IN_USE` — internal id collision refusal — carries the
    /// attach-or-omit `agentAction` and has no `exitClass`
    /// override, so it falls through to `ExitCode.operational` (process exit 1),
    /// unchanged from every other run-related refusal.
    func testRunIdInUseErrorSpecRegistered() {
        let spec = reg.errors.first { $0.code == "RUN_ID_IN_USE" }
        XCTAssertNotNil(spec, "RUN_ID_IN_USE must be registered beside RELAY_ROUND_IN_FLIGHT")
        XCTAssertEqual(spec?.ruleId, "run.id.in_use")
        XCTAssertEqual(spec?.requiresManual, true)
        XCTAssertEqual(spec?.retryable, false)
        XCTAssertTrue(spec?.agentAction.contains("alln run resume") == true)
        XCTAssertEqual(reg.processExitCode(forErrorCode: "RUN_ID_IN_USE"), 1)
    }

    func testServeForeignHomeErrorSpecRegistered() {
        let spec = reg.errors.first { $0.code == "SERVE_FOREIGN_HOME" }
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.ruleId, "serve.foreign_home")
        XCTAssertEqual(spec?.requiresManual, true)
        XCTAssertEqual(spec?.retryable, false)
        XCTAssertEqual(reg.processExitCode(forErrorCode: "SERVE_FOREIGN_HOME"), 1)
    }

    func testDoctorChecksAndEventsAreCompleteAndUnique() {
        let checks = reg.doctorChecks.map(\.name)
        XCTAssertEqual(checks.count, Set(checks).count, "duplicate doctor check")
        for required in ["binaryVersion", "docsVersion", "benchReadyCount", "defaultTeamValid", "planWriterReady", "coordinator", "pending.storeReadable", "pending.storeWritable"] {
            XCTAssertTrue(checks.contains(required), "missing doctor check \(required)")
        }
        let events = reg.events.map(\.name)
        XCTAssertEqual(events.count, Set(events).count, "duplicate event")
        for required in ["teamRunStarted", "workerAnswered", "planWritten", "teamRunCompleted", "teamRunFailed", "error"] {
            XCTAssertTrue(events.contains(required), "missing event \(required)")
        }
    }

    /// The registry must serialize cleanly — step 3 exports it as JSON.
    func testRegistryRoundTrips() throws {
        let data = try CoreJSON.encode(reg)
        let back = try CoreJSON.decode(ContractRegistry.self, from: data)
        XCTAssertEqual(reg, back)
    }
}
