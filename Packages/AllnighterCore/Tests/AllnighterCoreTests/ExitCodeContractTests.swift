import XCTest
import Foundation
@testable import AllnighterCore

/// M-C Works Test: process exit codes are catalog-derived and consistent. Every
/// error code carries an exit class; usage errors map to exit 2 and operational
/// failures to exit 1; every error code a CLI handler can emit exists in the
/// catalog; and `error_explain` resolves every catalog code.
final class ExitCodeContractTests: XCTestCase {
    private let registry = ContractRegistry.milestone1

    func testEveryCatalogCodeHasAnExitClass() {
        // Field is non-optional, but assert the value is one of the two legal classes
        // and that error codes only ever map to exit 1 or 2 (never 0 / >2).
        for spec in registry.errors {
            XCTAssertTrue([1, 2].contains(spec.exitClass.processExitCode), "\(spec.code) has illegal exit code")
        }
    }

    func testUsageErrorsExitTwoOperationalExitOne() {
        XCTAssertEqual(registry.processExitCode(forErrorCode: "CLI_USAGE_ERROR"), ExitCode.usageError)
        XCTAssertEqual(registry.processExitCode(forErrorCode: "WORKER_FAILED"), ExitCode.operationalFailure)
        XCTAssertEqual(registry.processExitCode(forErrorCode: "THREAD_NOT_FOUND"), ExitCode.operationalFailure)
        XCTAssertEqual(registry.processExitCode(forErrorCode: "MODEL_NOT_FOUND"), ExitCode.operationalFailure)
        // CLI_USAGE_ERROR is the only usage-class code today.
        let usage = registry.errors.filter { $0.exitClass == .usage }.map(\.code)
        XCTAssertEqual(usage, ["CLI_USAGE_ERROR"])
    }

    func testUnknownCodeDefaultsToOperationalNeverCrashes() {
        XCTAssertEqual(registry.processExitCode(forErrorCode: "NOT_A_REAL_CODE"), ExitCode.operationalFailure)
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
                    // Only flag tokens that read like error codes (contain an underscore).
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
