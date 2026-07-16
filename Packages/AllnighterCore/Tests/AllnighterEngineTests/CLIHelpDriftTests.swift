import XCTest
import AllnighterCore
@testable import AllnighterCLI

/// Top-level `alln --help` must surface every M1 contract command (or be on an
/// explicit exclusion list). Mirrors `AgentHelloTests.testHelloPayloadCommandsResolveAgainstRegistry`.
final class CLIHelpDriftTests: XCTestCase {
    /// Commands documented via `alln help` / `alln docs` instead of the terse
    /// top-level `--help` banner. Add here with a comment — never silently skip.
    private let excludedFromTopLevelHelp: Set<String> = [
        // Agent bootstrap + dry-run — surfaced via `alln team hello` / preflight docs.
        "team hello",
        "team preflight",
        // Catalog CRUD — `alln teams` / `alln skills` families (not repeated on --help).
        "teams", "teams show", "teams definition", "teams duplicate", "teams edit",
        "teams set-default", "teams delete", "teams restore",
        "skills", "skills show", "skills duplicate", "skills new", "skills edit", "skills delete",
        // Work-thread surface — GUI / project docs.
        "thread send", "thread get", "thread rename", "thread attachment", "thread status",
        // PM Relay + Pilot — long-form `alln help get pm_relay`.
        "pair relay", "pair relay-status", "pair relay-resume", "pair relay adopt",
        "pair pilot start", "pair pilot handoff", "pair pilot status", "pair pilot watch", "pair pilot adopt",
        // Run inspection beyond show/export.
        "floor show", "spec",
        // Pending + project + stalled families.
        "pending add", "pending list", "pending queue", "pending show", "pending submit",
        "pending edit", "pending reorder", "pending cancel", "pending run",
        "project list", "project add", "project show", "project archive", "project unarchive",
        "project threads", "project pending", "project stalled", "project context",
        "project workers", "project recheck-workers",
        "stalled list", "stalled check", "stalled wait", "stalled dismiss",
        // Default model / Auto tiers.
        "defaults show", "defaults tier", "defaults assign", "defaults unassign",
        "defaults substitutions", "defaults reset",
        // Installed help system (distinct from bare `help` subcommand routing).
        "help search", "help get", "help topics",
        // Boost window subcommand spelled differently on --help (`observations` vs `observations clear`;
        // `show|set|seed` pipe notation does not substring-match the spaced command names).
        "boost-window set", "boost-window seed", "boost-window observations clear",
        // Models pipe notation (`enable|disable`, `update|delete`).
        "models disable", "models delete",
    ]

    func testPrintHelpCoversContractRegistryCommands() {
        let help = AllnighterCLI.helpText()
        XCTAssertTrue(help.contains("run "), "top-level help must list `run`")
        XCTAssertTrue(help.contains("--try-fix"), "run help must mention --try-fix")

        let m1 = ContractRegistry.milestone1.commands.filter { $0.milestone == .m1 }.map(\.name)
        for name in m1 {
            if excludedFromTopLevelHelp.contains(name) { continue }
            XCTAssertTrue(
                help.contains(name),
                "top-level help missing contract command `\(name)` — add a line or comment it in excludedFromTopLevelHelp")
        }
    }
}
