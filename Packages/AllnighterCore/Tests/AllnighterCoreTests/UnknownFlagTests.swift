import XCTest
@testable import AllnighterCore

/// AE-S12: unknown flags fail closed against each M1 command's FlagSpec list.
final class UnknownFlagTests: XCTestCase {
    func testBogusFlagRejectedOnEveryM1Command() {
        let registry = ContractRegistry.milestone1
        let m1 = registry.commands.filter { $0.milestone == .m1 }
        XCTAssertFalse(m1.isEmpty)
        var failures: [String] = []
        for spec in m1 {
            let parts = spec.name.split(separator: " ").map(String.init)
            guard let root = parts.first else { continue }
            let rest = Array(parts.dropFirst()) + ["--totally-bogus-flag"]
            guard let resolved = CLIUsage.resolveCommandName(rootCommand: root, args: rest, registry: registry) else {
                failures.append("\(spec.name): unresolved")
                continue
            }
            XCTAssertEqual(resolved, spec.name, "longest-prefix should resolve to \(spec.name)")
            let err = CLIUsage.validateFlags(args: rest, commandName: resolved, registry: registry)
            guard let err else {
                failures.append("\(spec.name): accepted --totally-bogus-flag")
                continue
            }
            XCTAssertEqual(err.flag, "totally-bogus-flag")
            XCTAssertEqual(err.commandName, spec.name)
        }
        XCTAssertTrue(failures.isEmpty, "unknown-flag gate failed:\n" + failures.joined(separator: "\n"))
    }

    func testJsonTypoSuggestsJson() {
        let err = CLIUsage.validateFlags(args: ["--jsonn"], commandName: "version")
        XCTAssertEqual(err?.flag, "jsonn")
        XCTAssertEqual(err?.suggestions, ["json"])
        XCTAssertEqual(ContractRegistry.milestone1.processExitCode(forErrorCode: "UNKNOWN_FLAG"), 2)
    }

    func testKnownFlagsStillPass() {
        XCTAssertNil(CLIUsage.validateFlags(args: ["--lane", "code", "--json"], commandName: "teams"))
        XCTAssertNil(CLIUsage.validateFlags(args: ["--json"], commandName: "version"))
        XCTAssertNil(CLIUsage.validateFlags(args: ["probe", "--project", "/tmp", "--model", "x"], commandName: "run"))
    }

    func testDryRunAcceptedAfterAE_S04() {
        // AE-S04 shipped `--dry-run` on `run`; unknown-flag gate must accept it.
        XCTAssertNil(CLIUsage.validateFlags(
            args: ["probe", "--project", "/tmp", "--dry-run"], commandName: "run"))
        // Invented near-miss still fails closed.
        let err = CLIUsage.validateFlags(
            args: ["probe", "--project", "/tmp", "--dryrun"], commandName: "run")
        XCTAssertEqual(err?.flag, "dryrun")
    }

    func testUnknownFlagErrorIsCatalogued() {
        let spec = ContractRegistry.milestone1.errorSpec(for: "UNKNOWN_FLAG")
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.exitClass, .usage)
        XCTAssertFalse(spec?.agentAction.isEmpty ?? true)
    }

    func testBooleanFlagNamesCoverPilotDefaultAndHandover() {
        let names = ContractRegistry.booleanFlagNames()
        XCTAssertTrue(names.contains("json"))
        XCTAssertTrue(names.contains("dry-run"))
        XCTAssertTrue(names.contains("pilot"), "doctor --pilot must parse as boolean")
        XCTAssertTrue(names.contains("default"), "defaults --default must parse as boolean")
        XCTAssertTrue(names.contains("handover-stdin"))
        XCTAssertFalse(names.contains("project"), "value flags must not be boolean")
        XCTAssertFalse(names.contains("lane"))
    }
}
