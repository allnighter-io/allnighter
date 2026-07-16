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
        "pair pilot start", "pair pilot handoff", "pair pilot status", "pair pilot watch", "pair pilot adopt", "pair pilot scaffold-handover",
        // Panel — long-form `alln help get panel` (top-level help names the family).
        "panel start", "panel round", "panel status", "panel watch", "panel scaffold-brief", "panel done",
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

    /// Every M1 registry command must project usage via the global `--help` funnel.
    func testEveryRegistryCommandHelpProjectsUsage() {
        let registry = ContractRegistry.milestone1
        for spec in registry.commands where spec.milestone == .m1 {
            let (root, args) = Self.invocationParts(for: spec.name)
            guard let text = CLIUsage.helpText(rootCommand: root, args: args, registry: registry) else {
                return XCTFail("no help text for `alln \(spec.name) --help`")
            }
            XCTAssertTrue(text.hasPrefix("usage: alln \(spec.name)"), "`\(spec.name)` help must name the command")
            XCTAssertTrue(text.contains(spec.summary), "`\(spec.name)` help must include the registry summary")
        }
    }

    /// `docs <topic>` and `help get <topic>` share `HelpTopicRegistry` resolution.
    func testEveryHelpTopicResolvesViaDocsAndHelpGet() {
        for topic in HelpTopicRegistry.topics {
            let help = HelpService.get(topic: topic.id)
            XCTAssertTrue(help.found, "help get must resolve `\(topic.id)`")
            XCTAssertEqual(help.topic?.id, topic.id)

            let docs = HelpService.docsMarkdown(topic: topic.id)
            XCTAssertNotNil(docs, "docs must resolve `\(topic.id)`")
            XCTAssertTrue(docs?.contains(topic.title) == true, "docs markdown must include title for `\(topic.id)`")
            XCTAssertTrue(docs?.contains(topic.summary) == true, "docs markdown must include summary for `\(topic.id)`")
        }
    }

  private static func invocationParts(for commandName: String) -> (String, [String]) {
        let parts = commandName.split(separator: " ").map(String.init)
        guard let root = parts.first else { return ("help", ["--help"]) }
        return (root, Array(parts.dropFirst()) + ["--help"])
    }
}
