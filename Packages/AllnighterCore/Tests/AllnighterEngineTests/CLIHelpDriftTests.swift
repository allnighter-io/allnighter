import XCTest
import AllnighterCore
@testable import AllnighterCLI

/// Top-level `alln --help` must surface every M1 contract command — no exclusion allowlist (AE-S01 / Law 5).
final class CLIHelpDriftTests: XCTestCase {
    func testPrintHelpCoversContractRegistryCommands() {
        let help = AllnighterCLI.helpText()
        let m1 = ContractRegistry.milestone1.commands.filter { $0.milestone == .m1 }.map(\.name)
        XCTAssertFalse(m1.isEmpty)
        var missing: [String] = []
        for name in m1 {
            // Match as a help row token (`  <name>` or start-of-line name), not a substring of a longer name.
            let row = "  \(name)"
            if !help.contains(row) && !help.contains("\n\(name)\n") {
                missing.append(name)
            }
        }
        XCTAssertTrue(missing.isEmpty, "top-level help missing contract commands (allowlist banned):\n\(missing.joined(separator: "\n"))")
        XCTAssertTrue(help.contains("menu"), "golden-path `menu` must be visible")
        XCTAssertTrue(help.contains("run"), "golden-path `run` must be visible")
        XCTAssertTrue(help.contains("team status"), "live Team lifecycle must be visible")
        XCTAssertTrue(help.contains("team cancel"), "Team cancellation must be visible")
        XCTAssertTrue(help.contains("team reconcile"), "Team reconciliation must be visible")
        XCTAssertTrue(help.contains("help search"), "`help search` must be visible")
        XCTAssertTrue(
            help.contains("\(m1.count) commands"),
            "help must carry an explicit completeness marker with the command count"
        )
        XCTAssertTrue(help.contains("alln docs <cmd> for schema"), "hydrate path `alln docs <cmd>` must be named")
        XCTAssertTrue(help.contains("alln menu --json"), "machine front door `alln menu --json` must be named")
        XCTAssertTrue(help.contains("alln help search"), "intent search path must be named")
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
            if spec.name == "run" {
                XCTAssertTrue(text.contains("[--effort <low|med|high>]"), "run help must project effort enum domain")
                XCTAssertTrue(text.contains("Mutually exclusive: --json, --stream."), "run help must project json/stream exclusion")
            }
        }
    }

    /// A recovery instruction must be directly discoverable from its parent command.
    /// Otherwise a version mismatch can strand an agent before it can repair the resident.
    func testServeHelpExposesInstallRefreshRecovery() {
        let help = CLIUsage.helpText(rootCommand: "serve", args: ["--help"])
        XCTAssertNotNil(help)
        XCTAssertTrue(help?.contains("serve install") == true)
        XCTAssertTrue(help?.contains("Install or safely refresh") == true)

        let installHelp = CLIUsage.helpText(rootCommand: "serve", args: ["install", "--help"])
        XCTAssertTrue(installHelp?.hasPrefix("usage: alln serve install") == true)
        XCTAssertTrue(installHelp?.contains("--json") == true)
    }

    /// Finding 12: `--help` must not invent usage for a command the registry cannot resolve.
    func testUnknownCommandHelpDoesNotInventUsage() {
        let text = CLIUsage.helpText(rootCommand: "config", args: ["--help"])
        XCTAssertNil(text, "unknown `config --help` must not fabricate usage")
        XCTAssertNil(CLIUsage.usageText(for: "config"))
        XCTAssertNil(CLIUsage.usageTextForPrefix("config"))
    }

    /// Options boolean parsing must use FlagSpec (no parallel hand list).
    func testOptionsBooleanFlagsMatchRegistry() {
        XCTAssertEqual(Options.booleanFlags, ContractRegistry.booleanFlagNames())
        XCTAssertTrue(Options.booleanFlags.contains("pilot"))
        XCTAssertTrue(Options.booleanFlags.contains("dry-run"))
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
