import XCTest
import Foundation
@testable import AllnighterCore

/// M-C + PO-F3 Works Test: process exit codes are catalog-derived and consistent.
/// Every error code carries an exit class; usage → 2, run-failed → 1, timeout → 3,
/// lane-busy → 4; every error code a CLI handler can emit exists in the catalog;
/// and `error_explain` resolves every catalog code. The stable table is frozen
/// so codes can never be silently renumbered.
final class ExitCodeContractTests: XCTestCase {
    private let registry = ContractRegistry.milestone1

    /// PO-F3: the numeric exit-code table is identity. Renumbering any row is a
    /// contract break; extend only by appending with a docs update.
    func testStableExitCodeTableNeverRenumbered() {
        XCTAssertEqual(ExitCode.success, 0)
        XCTAssertEqual(ExitCode.runFailed, 1)
        XCTAssertEqual(ExitCode.operationalFailure, 1)
        XCTAssertEqual(ExitCode.usageError, 2)
        XCTAssertEqual(ExitCode.timeout, 3)
        XCTAssertEqual(ExitCode.laneBusy, 4)

        let expected: [(Int32, String)] = [
            (0, "success"),
            (1, "runFailed"),
            (2, "usageError"),
            (3, "timeout"),
            (4, "laneBusy"),
        ]
        XCTAssertEqual(ExitCode.stableTable.count, expected.count)
        for (i, row) in ExitCode.stableTable.enumerated() {
            XCTAssertEqual(row.code, expected[i].0, "row \(i) code renumbered")
            XCTAssertEqual(row.name, expected[i].1, "row \(i) name renamed")
        }

        // Exit class → process exit code mapping is frozen with the table.
        XCTAssertEqual(ContractRegistry.ErrorExitClass.operational.processExitCode, 1)
        XCTAssertEqual(ContractRegistry.ErrorExitClass.usage.processExitCode, 2)
        XCTAssertEqual(ContractRegistry.ErrorExitClass.timeout.processExitCode, 3)
        XCTAssertEqual(ContractRegistry.ErrorExitClass.laneBusy.processExitCode, 4)

        // Export rows match the frozen table (byte-stable artifact content).
        let export = ExitCodeExport.rows
        XCTAssertEqual(export.map(\.code), expected.map { Int($0.0) })
        XCTAssertEqual(export.map(\.name), expected.map(\.1))
    }

    func testEveryCatalogCodeHasAnExitClass() {
        let legal: Set<Int32> = [1, 2, 3, 4]
        for spec in registry.errors {
            XCTAssertTrue(
                legal.contains(spec.exitClass.processExitCode),
                "\(spec.code) has illegal exit code \(spec.exitClass.processExitCode)"
            )
        }
    }

    func testUsageErrorsExitTwoOperationalExitOne() {
        XCTAssertEqual(registry.processExitCode(forErrorCode: "CLI_USAGE_ERROR"), ExitCode.usageError)
        XCTAssertEqual(registry.processExitCode(forErrorCode: "AGENT_FAILED"), ExitCode.runFailed)
        XCTAssertEqual(registry.processExitCode(forErrorCode: "THREAD_NOT_FOUND"), ExitCode.runFailed)
        XCTAssertEqual(registry.processExitCode(forErrorCode: "MODEL_NOT_FOUND"), ExitCode.runFailed)
        XCTAssertEqual(registry.processExitCode(forErrorCode: "NO_PROJECT_SELECTED"), ExitCode.usageError)
        // The usage-class (exit 2) codes: bad invocation before any work started.
        let usage = registry.errors.filter { $0.exitClass == .usage }.map(\.code)
        XCTAssertEqual(Set(usage), ["CLI_USAGE_ERROR", "UNKNOWN_FLAG", "CONTRACT_VERSION_NOT_BUMPED", "NO_PROJECT_SELECTED", "DEFAULTS_TIER_INVALID",
                                     "UTILIZATION_SOURCE_NOT_FOUND", "UTILIZATION_SOURCE_UNCONFIGURED", "LOOP_LOCAL_SEAT_CANNOT_LEAD",
                                     "SWEEP_NO_TARGETS", "SWEEP_DUPLICATE_TARGETS"])
    }

    func testTimeoutAndLaneBusyClassesMapToDistinctCodes() {
        XCTAssertEqual(registry.processExitCode(forErrorCode: "TEAM_RUN_TIMEOUT"), ExitCode.timeout)
        XCTAssertEqual(registry.processExitCode(forErrorCode: "PM_TURN_WAIT_TIMEOUT"), ExitCode.timeout)
        XCTAssertEqual(registry.processExitCode(forErrorCode: "EXECUTION_LANE_BUSY"), ExitCode.laneBusy)
        XCTAssertEqual(registry.processExitCode(forErrorCode: "RUN_WRITE_LOCK_BUSY"), ExitCode.laneBusy)
        XCTAssertNotEqual(ExitCode.timeout, ExitCode.laneBusy)
        XCTAssertNotEqual(ExitCode.timeout, ExitCode.runFailed)
        XCTAssertNotEqual(ExitCode.laneBusy, ExitCode.usageError)
    }

    func testUnknownCodeDefaultsToOperationalNeverCrashes() {
        XCTAssertEqual(registry.processExitCode(forErrorCode: "NOT_A_REAL_CODE"), ExitCode.runFailed)
        XCTAssertNil(registry.errorSpec(for: "NOT_A_REAL_CODE"))
    }

    func testErrorExplainResolvesEveryCatalogCode() {
        // error_explain looks the code up in exactly this catalog; every code must
        // resolve to a spec with non-empty recovery text.
        for spec in registry.errors {
            let resolved = registry.errorSpec(for: spec.code)
            XCTAssertNotNil(resolved, "\(spec.code) does not resolve")
            XCTAssertFalse(resolved!.agentAction.isEmpty, "\(spec.code) missing agentAction")
            XCTAssertFalse(resolved!.explain.isEmpty, "\(spec.code) missing explain")
        }
    }

    func testExitClassDecodeIsTolerantOfMissingField() throws {
        // A pre-M-C artifact without `exitClass` must decode as operational.
        let json = #"{"code":"X","ruleId":"x","agentAction":"a","requiresManual":false,"retryable":true,"explain":"e"}"#
        let spec = try JSONDecoder().decode(ContractRegistry.ErrorSpec.self, from: Data(json.utf8))
        XCTAssertEqual(spec.exitClass, .operational)
    }

    /// The contract gate: every error-code literal a CLI handler can emit must
    /// exist in the catalog. Scans the AllnighterCLI sources for `code: "..."` and
    /// `("...",` literals and checks catalog membership.
    func testEveryEmittedCliCodeExistsInCatalog() throws {
        let cliDir = packageRoot()
            .appendingPathComponent("Sources/AllnighterCLI", isDirectory: true)
        let fm = FileManager.default
        guard let files = fm.enumerator(at: cliDir, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL }).filter({ $0.pathExtension == "swift" }) else {
            return XCTFail("could not enumerate \(cliDir.path)")
        }
        XCTAssertFalse(files.isEmpty, "no CLI sources found at \(cliDir.path)")

        let known = Set(registry.errors.map(\.code))
        // SCREAMING_SNAKE literals after `code: ` or as the first element of a `("X",` tuple.
        let patterns = [
            try NSRegularExpression(pattern: #"code:\s*"([A-Z][A-Z0-9_]{2,})""#),
            try NSRegularExpression(pattern: #"\(\s*"([A-Z][A-Z0-9_]{2,})"\s*,"#),
        ]
        // Tokens that look like codes but are not catalog error codes.
        let ignore: Set<String> = ["ISO", "UTF", "JSON", "PNG", "JPEG", "GIF", "WEBP"]

        var offenders: [String: String] = [:]   // code -> file
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let ns = text as NSString
            for re in patterns {
                for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    let code = ns.substring(with: m.range(at: 1))
                    if ignore.contains(code) || known.contains(code) { continue }
                    // Only flag tokens that look like error codes (contain an underscore).
                    if code.contains("_") { offenders[code] = file.lastPathComponent }
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "CLI emits error codes absent from the catalog: \(offenders)")
    }

    /// Repo path resolution from this test file: …/Tests/AllnighterCoreTests/<this>.swift
    /// → up 3 → the AllnighterCore package root.
    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AllnighterCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // AllnighterCore (package root)
    }
}
