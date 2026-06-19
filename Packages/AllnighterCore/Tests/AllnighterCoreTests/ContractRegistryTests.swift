import XCTest
@testable import AllnighterCore

/// The registry is the SSOT for the `alln` contract; these tests enforce that it
/// stays internally consistent and in lock-step with the closed types it owns
/// (docs/phases/CLI_Implementation_Contract.md §Contract Registry).
final class ContractRegistryTests: XCTestCase {
    private let reg = ContractRegistry.milestone1

    func testContractVersionMatchesTeamRunFixture() throws {
        let trj = try Fixtures.decode(TeamRunJSON.self, .teamRunJSON)
        XCTAssertEqual(reg.contractVersion, trj.contractVersion)
        XCTAssertEqual(reg.contractVersion, "1.0.0")
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
        XCTAssertEqual(m1, [
            "docs", "doctor", "doctor explain",
            "models", "models enable", "models disable", "models add", "models update", "models delete",
            "team show",
            "teams", "teams show", "teams duplicate", "teams edit", "teams set-default", "teams delete",
            "skills", "skills show", "skills duplicate", "skills new", "skills edit", "skills delete",
            "team hello", "team preflight",
            "team start", "team status", "team result", "team cancel",
            "thread send", "thread get", "thread status",
            "team", "show", "floor show", "spec", "history", "export", "dev export-contracts", "serve",
            "pending add", "pending list", "pending show", "pending submit", "pending edit",
            "pending reorder", "pending cancel", "pending run",
            "mcp serve",
            "project list", "project add", "project show", "project archive", "project unarchive",
            "project threads", "project pending", "project stalled", "project context",
            "stalled list",
            "project workers", "project recheck-workers", "project chat",
            "project propose", "project proposals",
            "project approve", "project edit", "project postpone",
        ])
    }

    /// MCP tools are a clean projection of M1 commands — no retired vocabulary.
    func testMCPToolsAreCleanAndDeriveFromCommands() {
        let names = reg.mcpTools.map(\.name)
        XCTAssertEqual(Set(names), [
            "mcp_hello", "teams_list", "teams_show", "teams_duplicate", "teams_save",
            "teams_set_default", "teams_delete",
            "skills_list", "skills_show", "skills_duplicate", "skills_save", "skills_delete",
            "team_preflight",
            "team_start", "team_status", "team_result", "team_cancel",
            "team_ask", "team_show", "history", "show", "doctor", "error_explain", "spec_get", "floor_show",
            "thread_send", "thread_get", "thread_status",
            "pending_list", "pending_show", "pending_run",
            "project_stalled", "stalled_list",
        ])
        XCTAssertFalse(names.contains("team_recall"), "team_recall was retired in step 8")
        XCTAssertFalse(names.contains("team_presets"))
        let deferred = Set(reg.commands.filter { $0.milestone == .deferred }.map(\.name))
        XCTAssertFalse(deferred.contains("team edit"), "retired nested catalog command")
        XCTAssertFalse(deferred.contains("teams edit"), "teams edit is M1 in catalog slice")
        let m1 = Set(reg.commands.filter { $0.milestone == .m1 }.map(\.name))
        for tool in reg.mcpTools {
            XCTAssertTrue(m1.contains(tool.command), "MCP tool \(tool.name) maps to non-M1 command \(tool.command)")
        }
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

    /// Mutually-exclusive flag names must actually be declared on the command.
    func testMutualExclusionsReferenceRealFlags() {
        for command in reg.commands {
            let declared = Set(command.flags.map(\.name))
            for group in command.mutuallyExclusiveFlags {
                for flag in group {
                    XCTAssertTrue(declared.contains(flag), "\(command.name) mutual-exclusion references unknown flag \(flag)")
                }
            }
        }
        // The contract's one M1 mutual exclusion: team --json | --stream.
        let team = reg.commands.first { $0.name == "team" }
        XCTAssertEqual(team?.mutuallyExclusiveFlags, [["json", "stream"]])
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
