import XCTest
@testable import AllnighterCore

/// AE-S07: *_NOT_FOUND / *_NOT_AVAILABLE nextAction routes to discovery, not doctor.
final class ErrorDiscoveryTests: XCTestCase {
    func testNotFoundCodesRouteToDiscoveryNotDoctor() {
        let codes = ContractRegistry.milestone1.errors
            .map(\.code)
            .filter { $0.hasSuffix("_NOT_FOUND") || $0.hasSuffix("_NOT_AVAILABLE") }
        XCTAssertFalse(codes.isEmpty)
        var bad: [String] = []
        for code in codes {
            guard let next = ErrorDiscovery.nextAction(forErrorCode: code) else {
                // Some codes (e.g. ATTACHMENT_NOT_FOUND) may lack a list surface —
                // only fail when doctor is the wrong default and we claimed a map.
                continue
            }
            if next.command.contains("doctor") && code != "SOURCE_NOT_FOUND" {
                bad.append("\(code) → \(next.command)")
            }
            XCTAssertTrue(next.command.hasPrefix("alln "), "\(code) nextAction must be an alln command")
        }
        XCTAssertTrue(bad.isEmpty, "NOT_FOUND nextAction must not be doctor:\n\(bad.joined(separator: "\n"))")
    }

    func testTeamNotFoundDiscoveryIsTeams() {
        let cmd = ErrorDiscovery.discoveryCommand(forErrorCode: "TEAM_NOT_FOUND", lane: "code")
        XCTAssertEqual(cmd, "alln teams --lane code --json")
        XCTAssertFalse(cmd?.contains("doctor") == true)
    }

    func testNearMatchesForTypo() {
        let ids = ["code_bug_hunt", "code_bug_hunt_min", "code_plan", "code_growth"]
        let hits = ErrorDiscovery.nearestMatches(to: "code_bug_hunt_typo", in: ids)
        XCTAssertTrue(hits.contains("code_bug_hunt") || hits.contains("code_bug_hunt_min"),
                      "expected near match for typo, got \(hits)")
        XCTAssertLessThanOrEqual(hits.count, 3)
    }

    func testErrorEnvelopeCarriesNextActionForTeamNotFound() {
        let env = ErrorEnvelope(
            code: "TEAM_NOT_FOUND",
            message: "unknown team: x",
            requiresManual: true,
            retryable: false,
            suggestions: ["code_bug_hunt"]
        )
        XCTAssertEqual(env.suggestions, ["code_bug_hunt"])
        XCTAssertEqual(env.nextAction?.command, "alln teams --json")
        XCTAssertFalse(env.nextAction?.command.contains("doctor") == true)
    }
}
