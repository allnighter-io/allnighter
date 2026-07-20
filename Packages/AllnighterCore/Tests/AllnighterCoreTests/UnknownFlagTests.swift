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
        XCTAssertNil(CLIUsage.validateFlags(args: ["probe", "--project", "/tmp", "--worker", "x"], commandName: "run"))
    }

    func testDryRunRejectedUntilAE_S04() {
        // Safety: a nonexistent safety flag must not no-op.
        let err = CLIUsage.validateFlags(args: ["probe", "--project", "/tmp", "--dry-run"], commandName: "run")
        XCTAssertEqual(err?.flag, "dry-run")
    }

    func testUnknownFlagErrorIsCatalogued() {
        let spec = ContractRegistry.milestone1.errorSpec(for: "UNKNOWN_FLAG")
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.exitClass, .usage)
        XCTAssertFalse(spec?.agentAction.isEmpty ?? true)
    }
}
